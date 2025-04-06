#!/usr/bin/env ruby

# Load bundled gems
require 'bundler/setup'
Bundler.require

# Load dotenv manually in case it's not in the Gemfile
begin
  require 'dotenv'
  Dotenv.load
  puts "Loaded environment from .env file"
rescue LoadError
  puts "dotenv gem not found. Environment variables may not be loaded properly."
end

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'time'
require 'logger'
require 'fileutils'
require 'colorize'
require_relative 'ai_service_provider'
require_relative 'config'

# CONSTANTS: START

# AI Provider Selection from config
AI_PROVIDER = DebuggerConfig::DEFAULT_PROVIDER

# Debugger settings from config
DEBUGGER_DIR = DebuggerConfig::DEBUGGER_DIR
SESSION_ID = SecureRandom.hex(3)
LOG_FILE = File.join(DebuggerConfig::LOGS_DIR, "debug_session_#{SESSION_ID}.log")
CONVERSATION_FILE = File.join(DebuggerConfig::LOGS_DIR, "conversation_#{SESSION_ID}.json")

# Load system prompt and response schema from configured paths
SYSTEM_PROMPT = File.read(DebuggerConfig::SYSTEM_PROMPT_PATH)
RESPONSE_SCHEMA_JSON = JSON.parse(File.read(DebuggerConfig::RESPONSE_SCHEMA_PATH))

# CONSTANTS: END
# ==================================================================================================
# Helper methods: START

# Set up a proper logger for file logging
def setup_logger
  logger = Logger.new(LOG_FILE)
  logger.formatter = proc do |severity, datetime, progname, msg|
    formatted_time = datetime.strftime("%Y-%m-%d %H:%M:%S")
    "[#{formatted_time}] #{severity}: #{msg}\n"
  end
  logger
end

# Global logger instance
LOGGER = setup_logger

# Print to screen with formatting based on message type
def print_status(message, type = :info)
  prefix = case type
    when :info then "[INFO] ".blue
    when :success then "[SUCCESS] ".green
    when :warning then "[WARNING] ".yellow
    when :error then "[ERROR] ".red
    when :ai then "[AI] ".magenta
    when :user then "[USER] ".cyan
    when :debug then "[DEBUG] ".light_black
    else "[#{type.to_s.upcase}] "
  end

  puts "#{prefix}#{message}"

  # Also log to file with appropriate level
  case type
  when :error
    LOGGER.error(message)
  when :warning
    LOGGER.warn(message)
  when :debug
    LOGGER.debug(message)
  else
    LOGGER.info(message)
  end
end

# Load a template file from the prompts directory
def load_template(template_name)
  template_path = File.join(DebuggerConfig::PROMPTS_DIR, "templates", "#{template_name}_template.md")

  if File.exist?(template_path)
    content = File.read(template_path)
    print_status("Loaded template: #{template_name}", :debug)
    return content
  else
    print_status("Template #{template_name} not found at #{template_path}", :warning)
    return nil
  end
end

# List all available templates
def list_available_templates
  template_dir = File.join(DebuggerConfig::PROMPTS_DIR, "templates")

  if !File.directory?(template_dir)
    FileUtils.mkdir_p(template_dir)
    print_status("Created templates directory at #{template_dir}", :debug)
    return []
  end

  templates = Dir.glob(File.join(template_dir, "*_template.md"))
                .map { |path| File.basename(path, "_template.md") }
                .sort

  templates.empty? ? [] : templates
end

# Fill in a template with user input
def fill_template(template_content)
  filled_content = template_content.dup

  # Find all placeholders in the template
  placeholders = template_content.scan(/\[(.*?)\]/)

  # Remove duplicates and sort by length (longer first)
  unique_placeholders = placeholders.flatten.uniq.sort_by { |p| -p.length }

  unique_placeholders.each do |placeholder|
    print_status("Please provide input for: #{placeholder}", :user)
    user_input = get_user_input("> ")
    filled_content.gsub!("[#{placeholder}]", user_input)
  end

  filled_content
end

# Load appropriate system prompt for the selected use case
def load_system_prompt(use_case_type)
  system_prompt_path = case use_case_type
  when :debugging
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "debugging_system_prompt.md")
  when :feature
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "feature_system_prompt.md")
  when :refactoring
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "refactoring_system_prompt.md")
  when :performance
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "performance_system_prompt.md")
  when :explanation
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "explanation_system_prompt.md")
  when :security
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "security_system_prompt.md")
  else
    File.join(DebuggerConfig::PROMPTS_DIR, "system", "general_system_prompt.md")
  end

  if File.exist?(system_prompt_path)
    print_status("Using specialized system prompt for #{use_case_type}", :debug)
    return File.read(system_prompt_path)
  else
    print_status("Specialized system prompt not found, using default", :warning)
    return File.read(DebuggerConfig::SYSTEM_PROMPT_PATH)
  end
end

def get_initial_prompt
  puts "\n" + "=" * 80
  puts " Select a use case: ".center(80, "=").blue
  puts "=" * 80

  # Display built-in options first
  puts "1. Debug code issue".green
  puts "2. Design a new feature".cyan
  puts "3. Refactor existing code".yellow
  puts "4. Optimize performance".magenta
  puts "5. Explain complex code".light_blue
  puts "6. Fix security vulnerability".red

  # Get available templates
  templates = list_available_templates - ["debugging", "feature", "refactoring", "performance", "explanation", "security"]

  # Display available templates
  template_offset = 7
  templates.each_with_index do |template, idx|
    puts "#{idx + template_offset}. Template: #{template.capitalize}".white
  end

  # Always show custom prompt option last
  puts "0. Custom prompt (free-form)".white

  choice = get_user_input("Enter your choice (0-#{templates.length + template_offset - 1}):")

  # Track which use case was selected
  selected_use_case = :general

  # Handle custom prompt first as it's special
  if choice == "0"
    selected_use_case = :custom
    prompt = get_multiline_input("Enter your custom prompt:")
    return [prompt, selected_use_case]
  end

  choice = choice.to_i

  # Handle built-in options
  case choice
  when 1 # Debug code issue
    selected_use_case = :debugging
    template = load_template("debugging")
    if template
      return [fill_template(template), selected_use_case]
    end

    description = get_multiline_input("Describe the problem you're facing:")
    file_path = get_optional_input("Which file should I start looking at? (press Enter to skip):")

    prompt = "I'm facing an issue where #{description}. "
    prompt += "The feature is rendered by the component in #{file_path}. " unless file_path.empty?
    prompt += "Can you help me debug this?"

  when 2 # Design a new feature
    selected_use_case = :feature
    template = load_template("feature")
    if template
      return [fill_template(template), selected_use_case]
    end

    feature = get_multiline_input("Describe the feature you want to implement:")
    tech_stack = get_optional_input("What technologies are you using? (press Enter to skip):")
    constraints = get_optional_input("Any specific constraints or requirements? (press Enter to skip):")

    prompt = "I need to implement a new feature: #{feature}. "
    prompt += "I'm using #{tech_stack}. " unless tech_stack.empty?
    prompt += "The following constraints apply: #{constraints}. " unless constraints.empty?
    prompt += "Can you help me design and implement this feature?"

  when 3 # Refactor existing code
    selected_use_case = :refactoring
    template = load_template("refactoring")
    if template
      return [fill_template(template), selected_use_case]
    end

    description = get_multiline_input("Describe what code you want to refactor:")
    file_path = get_optional_input("Which file contains the code to refactor? (press Enter to skip):")
    goals = get_optional_input("What are your refactoring goals? (press Enter to skip):")

    prompt = "I need to refactor some code: #{description}. "
    prompt += "The code is in #{file_path}. " unless file_path.empty?
    prompt += "My refactoring goals are: #{goals}. " unless goals.empty?
    prompt += "Can you help me improve this code?"

  when 4 # Optimize performance
    selected_use_case = :performance
    template = load_template("performance")
    if template
      return [fill_template(template), selected_use_case]
    end

    issue = get_multiline_input("Describe the performance issue:")
    metrics = get_optional_input("Any metrics or measurements? (press Enter to skip):")

    prompt = "I'm experiencing performance issues: #{issue}. "
    prompt += "Here are the metrics: #{metrics}. " unless metrics.empty?
    prompt += "Can you help me optimize this for better performance?"

  when 5 # Explain complex code
    selected_use_case = :explanation
    template = load_template("explanation")
    if template
      return [fill_template(template), selected_use_case]
    end

    code_description = get_multiline_input("Describe the code you need explained:")
    file_path = get_optional_input("Which file contains this code? (press Enter to skip):")

    prompt = "I need to understand the following code: #{code_description}. "
    prompt += "It's located in #{file_path}. " unless file_path.empty?
    prompt += "Can you explain how it works and what it's doing?"

  when 6 # Fix security vulnerability
    selected_use_case = :security
    template = load_template("security")
    if template
      return [fill_template(template), selected_use_case]
    end

    vulnerability = get_multiline_input("Describe the security vulnerability:")
    file_path = get_optional_input("Which file is affected? (press Enter to skip):")

    prompt = "I've identified a security vulnerability: #{vulnerability}. "
    prompt += "It affects the code in #{file_path}. " unless file_path.empty?
    prompt += "Can you help me fix this security issue?"

  else # Handle template choices
    template_index = choice - template_offset

    if template_index >= 0 && template_index < templates.length
      template_name = templates[template_index]
      selected_use_case = template_name.to_sym
      template = load_template(template_name)
      if template
        return [fill_template(template), selected_use_case]
      end
    end

    # Fallback to default prompt
    prompt = get_multiline_input("What problem are you facing?")
  end

  [prompt, selected_use_case]
end

def get_multiline_input(prompt_text)
  print_status(prompt_text, :user)
  lines = []
  while (line = $stdin.gets.chomp) != ""
    lines << line
  end
  lines.join("\n")
end

def get_optional_input(prompt_text)
  print_status(prompt_text, :user)
  $stdin.gets.chomp
end

# Enhanced save_conversation to include metadata with use case type
def save_conversation(conversation, use_case_type = nil)
  begin
    unless File.directory?(File.dirname(CONVERSATION_FILE))
      Dir.mkdir(File.dirname(CONVERSATION_FILE))
    end

    # Create a full data structure with metadata
    conversation_data = {
      "metadata": {
        "use_case_type": use_case_type.to_s,
        "session_id": SESSION_ID,
        "provider": AI_PROVIDER,
        "timestamp": Time.now.iso8601
      },
      "messages": conversation
    }

    File.write(CONVERSATION_FILE, JSON.pretty_generate(conversation_data))
    # Only log to debug, don't print to console
    LOGGER.debug("Conversation saved to #{CONVERSATION_FILE}")
  rescue StandardError => e
    print_status("Failed to save conversation: #{e.message}", :warning)
  end
end

# Helper to extract conversation messages from conversation data
def extract_conversation(conversation_data)
  if conversation_data.is_a?(Hash) && conversation_data["messages"].is_a?(Array)
    return conversation_data["messages"], conversation_data.dig("metadata", "use_case_type")&.to_sym
  else
    return conversation_data, nil
  end
end

# Initialize AI service provider with configuration from config.rb
def init_ai_service_provider(provider, system_prompt = nil, schema = nil, logger = nil)
  # Get custom settings or fallback to defaults
  custom_model = DebuggerConfig.get_custom_model(provider)
  custom_token_limit = DebuggerConfig.get_custom_token_limit(provider)

  model_info = custom_model || AiServiceProvider.default_model(provider)
  token_info = custom_token_limit || AiServiceProvider.default_token_limit(provider)

  print_status("Using #{provider.capitalize} model: #{model_info} (max tokens: #{token_info})", :debug)

  config = {
    provider: provider,
    api_key: DebuggerConfig.get_api_key(provider),
    model: custom_model,
    max_tokens: custom_token_limit,
    system_prompt: system_prompt,
    schema: schema,
    logger: logger
  }

  # Add OpenAI specific config if needed
  if provider == AiServiceProvider::PROVIDER_OPENAI && DebuggerConfig::OPENAI_ORG_ID
    config[:openai_org_id] = DebuggerConfig::OPENAI_ORG_ID
  end

  AiServiceProvider.new(config)
end

def call_api(conversation, system_prompt = nil, schema = nil, allowed_tokens = nil)
  save_conversation(conversation, USE_CASE_TYPE)
  @service_provider ||= init_ai_service_provider(AI_PROVIDER, system_prompt, schema, LOGGER)

  print_status("Sending request to #{AI_PROVIDER.capitalize}...", :ai)
  result = @service_provider.call_api(conversation, allowed_tokens)
  print_status("Received response from #{AI_PROVIDER.capitalize}", :ai)

  return result
rescue StandardError => e
  print_status("API call failed: #{e.message}", :error)
  print_status("Check log file for details: #{LOG_FILE}")
  print_status("You can resume this session with: #{$0} #{CONVERSATION_FILE}", :info)
  exit 1
end

def parse_json(content)
  begin
    JSON.parse(content)
  rescue JSON::ParserError => e
    return false
  end
end

def parse_response(response)
  if response.is_a?(Hash)
    response
  elsif response.is_a?(String)
    if response.match(/```json\s*([\s\S]*?)\s*```/)
      json_content = $1
      JSON.parse(json_content)
    elsif parse_json(response)
      JSON.parse(response)
    else
      { "action" => "message", "message" => response }
    end
  else
    raise "Invalid response format"
  end
rescue StandardError => e
  print_status("Failed to parse AI response: #{e.message}", :error)
  print_status("Raw response: #{response.inspect}", :debug)
  print_status("Check log file for details: #{LOG_FILE}")
  print_status("You can resume this session with: #{$0} #{CONVERSATION_FILE}")
  exit 1
end

def get_user_input(prompt)
  print "#{prompt}\n> ".cyan
  input = $stdin.gets.chomp
  input.to_s
end

def is_command_safe(command)
  print_status("Checking if command is safe: '#{command}'", :debug)
  system_prompt = <<~PROMPT
    Evaluate the safety of the following shell command in the context of a project located at: #{Dir.pwd}.
    Ensure the command:
    - Does not perform any destructive actions (e.g., delete system files).
    - Operates strictly within the specified project directory.
    - Is relevant to the problem or context at hand.

    Please respond with 1 or 0, and suggest a safer alternative if deemed unsafe, 1 for safe and 0 for unsafe.
  PROMPT

  service_provider = init_ai_service_provider(AI_PROVIDER, system_prompt, {
    "name"=> "command_evaluation",
    "description"=> "Evaluate the safety of shell commands",
    "inputs"=> [
      {
        "name"=> "is_ok",
        "type"=> "string",
        "description"=> "1 for safe, 0 for unsafe",
        "enum"=> ["1", "0"],
        "required"=> true
      }
    ]
  }, LOGGER)
  response = service_provider.call_api([{ "role" => "user", "content" => "Command: #{command}" }], 1000)
  parsed_response = parse_response(response)
  response = parsed_response["is_ok"] || parsed_response["message"]
  if response == "1"
    print_status("Command evaluated as safe", :success)
    return true
  else
    print_status("Command evaluated as potentially unsafe", :warning)
    return false
  end
end

# Helper methods: END
# ==================================================================================================
# Main logic: START

# Ensure logs directory exists
unless File.directory?(DebuggerConfig::LOGS_DIR)
  FileUtils.mkdir_p(DebuggerConfig::LOGS_DIR)
end

# Print welcome message
puts "\n" + "=" * 80
puts " AI Debug Assistant ".center(80, "=").green
puts "=" * 80

print_status("Debug session #{SESSION_ID} started with #{AI_PROVIDER.capitalize}")
print_status("Logs will be saved to #{LOG_FILE}", :debug)
print_status("Conversation will be saved to #{CONVERSATION_FILE}", :debug)

conversation = []

if ARGV.length > 0 && File.exist?(ARGV[0])
  begin
    conversation_data = JSON.parse(File.read(ARGV[0]))
    messages, stored_use_case = extract_conversation(conversation_data)

    # Set the conversation to just the messages part
    conversation = messages

    # If there are messages, use the first one as the initial prompt
    if conversation.is_a?(Array) && !conversation.empty?
      INITIAL_PROMPT = conversation.first["content"]
      # Use the stored use case if available, otherwise default to general
      USE_CASE_TYPE = stored_use_case || :general
      print_status("Resuming previous session from #{ARGV[0]} (Use case: #{USE_CASE_TYPE})", :info)
    else
      # Handle empty/invalid conversation array
      print_status("Invalid conversation data in file, starting new conversation", :warning)
      INITIAL_PROMPT, USE_CASE_TYPE = get_initial_prompt
      conversation = [{ "role" => "user", "content" => INITIAL_PROMPT }]
    end
  rescue JSON::ParserError => e
    print_status("Error parsing conversation file: #{e.message}", :warning)
    print_status("Starting new conversation", :info)
    INITIAL_PROMPT, USE_CASE_TYPE = get_initial_prompt
    conversation = [{ "role" => "user", "content" => INITIAL_PROMPT }]
  end
else
  INITIAL_PROMPT, USE_CASE_TYPE = get_initial_prompt
  conversation = [{ "role" => "user", "content" => INITIAL_PROMPT }]
  save_conversation(conversation, USE_CASE_TYPE)
end

LOGGER.info("Starting session with #{AI_PROVIDER} provider for use case: #{USE_CASE_TYPE}")
LOGGER.info("Initial user prompt: #{INITIAL_PROMPT}")

# Load the appropriate system prompt
SYSTEM_PROMPT = load_system_prompt(USE_CASE_TYPE)

loop do
  response = call_api(conversation, SYSTEM_PROMPT, RESPONSE_SCHEMA_JSON)
  LOGGER.info("AI response received")

  data = parse_response(response)
  action = data["action"]&.downcase
  details = data["details"] || {}
  message = data["message"]

  reply = ""
  case action
  when "request_file"
    requested_files = details["file_paths"] || []
    if requested_files.empty?
      print_status("AI requested files but didn't specify any file paths", :warning)
      reply = "[Error: No file paths specified]"
    else
      print_status("AI is reading #{requested_files.length} file(s): #{requested_files.join(', ')}", :ai)
      reply = "Here is the content of the requested files:\n\n"

      requested_files.each do |path|
        # full_path = File.join(Dir.pwd, path)
        full_path = path
        begin
          content = File.read(full_path)
          print_status("Read file: #{path} (#{content.lines.count} lines)", :debug)
          reply << "<file name=\"#{path}\">\n#{content}\n</file>\n"
        rescue Errno::ENOENT
          print_status("File not found: #{path}", :warning)
          reply << "<file name=\"#{path}\">\n[Error: File not found]\n</file>\n"
        rescue Errno::EISDIR
          print_status("Cannot read directory as file: #{path}", :warning)
          reply << "<file name=\"#{path}\">\n[Error: Cannot read directory as a file]\n</file>\n"
        rescue Errno::EACCES
          print_status("Permission denied: #{path}", :warning)
          reply << "<file name=\"#{path}\">\n[Error: Permission denied]\n</file>\n"
        rescue StandardError => e
          print_status("Error reading file #{path}: #{e.message}", :warning)
          reply << "<file name=\"#{path}\">\n[Error: #{e.message}]\n</file>\n"
        end
      end
    end

  when "update_file"
    file_path = details["file_path"]
    content = details["content"]

    if file_path.nil? || content.nil?
      print_status("AI tried to update a file but didn't provide required details", :warning)
      reply = "Error: No file path or content specified."
    else
      full_path = File.join(Dir.pwd, file_path)
      print_status("AI is updating file: #{file_path}", :ai)

      begin
        File.write(full_path, content)
        print_status("Successfully updated #{file_path} (#{content.lines.count} lines)", :success)
        reply = "Updated #{file_path}."
      rescue Errno::EISDIR
        print_status("Cannot write to a directory: #{file_path}", :warning)
        reply = "Error: Cannot write to a directory. Please specify a file path."
      rescue Errno::EACCES
        print_status("Permission denied to write to file: #{file_path}", :warning)
        reply = "Error: Permission denied to write to the file."
      rescue Errno::ENOENT
        print_status("Directory does not exist for file: #{file_path}", :warning)
        reply = "Error: Directory does not exist."
      rescue StandardError => e
        print_status("Error updating file #{file_path}: #{e.message}", :warning)
        reply = "Error: #{e.message}"
      end
    end

  when "run_command"
    command = details["command"]
    print_status("AI wants to run command: '#{command}'", :ai)

    is_ok_run = is_command_safe(command)
    if !is_ok_run
      confirmation = get_user_input("Run '#{command}'? [y/n]")
      if confirmation.downcase == "y"
        is_ok_run = true
      end
    end

    if is_ok_run
      begin
        print_status("Executing command: #{command}", :info)
        output = `#{command} 2>&1`
        status = $?
        if status.success?
          print_status("Command executed successfully", :success)
          reply = "Command executed successfully. Output: #{output}"
        else
          print_status("Command failed with exit status #{status.exitstatus}", :warning)
          reply = "Command failed with exit status #{status.exitstatus}. Output: #{output}"
        end
      rescue Errno::ENOENT
        print_status("Command not found: #{command}", :warning)
        reply = "Error: Command '#{command}' not found."
      end
    else
      print_status("Command execution skipped", :info)
      reply = "Command skipped."
    end

  when "request_input"
    print_status("AI is requesting additional information", :ai)
    if message
      puts "\n" + message.yellow
    end
    reply = get_user_input(details["question"] || "Please provide more information:")
    print_status("Provided additional information to AI", :user)

  when "issue_resolved"
    print_status("AI suggests the issue is resolved", :success)
    puts "\n" + message.green
    puts "Solution: ".green + details['solution'].to_s

    reply = get_user_input("Is the issue resolved? [y/n]")
    if reply.downcase == "n"
      extra_feedback = get_user_input("Please explain why the issue is not resolved:")
      reply += "\nExplanation: #{extra_feedback}"
      print_status("Provided feedback that the issue is not resolved", :user)
    else
      print_status("Confirmed issue is resolved", :success)
    end

    if action == "issue_resolved" && reply.downcase == "y"
      LOGGER.info("Issue resolved. Session ended.")
      print_status("Issue resolved. Debug session completed.", :success)
      print_status("Log saved to #{LOG_FILE}")
      print_status("Conversation saved to #{CONVERSATION_FILE}", :info) # Make sure to display this only at the end
      print_status("You can resume this session with: #{$0} #{CONVERSATION_FILE}", :info)
      break
    end

  when "message"
    print_status("AI message:", :ai)
    puts "\n" + (details['message'] || message || "").yellow
    reply = get_user_input("Your response:")
    print_status("Sent response to AI", :user)

  else
    print_status("Unknown action from AI: '#{action}'", :warning)
    reply = "Error: Unknown action '#{action}'. Please specify a valid action."
  end

  conversation << { "role" => "assistant", "content" => response.to_json }
  conversation << { "role" => "user", "content" => reply }

  truncated_reply = reply.length > 100 ? "#{reply[0...97]}..." : reply
  LOGGER.info("User reply: #{truncated_reply}")

  save_conversation(conversation, USE_CASE_TYPE)

  if action == "issue_resolved" && reply.downcase == "y"
    LOGGER.info("Issue resolved. Session ended.")
    print_status("Issue resolved. Debug session completed.", :success)
    print_status("Log saved to #{LOG_FILE}")
    print_status("Conversation saved to #{CONVERSATION_FILE}", :info) # Make sure to display this only at the end
    print_status("You can resume this session with: #{$0} #{CONVERSATION_FILE}", :info)
    break
  end
end

# Main logic: END
# ==================================================================================================
