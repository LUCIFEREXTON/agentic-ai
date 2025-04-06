#!/usr/bin/env ruby

require 'fileutils'
begin
  require 'dotenv'
  Dotenv.load
rescue LoadError
  puts "dotenv gem not found. To use .env files, install it with: gem install dotenv"
  # Continue without dotenv - will use hardcoded defaults or ENV variables
end

# Configuration file for debugger
# Contains all configurable parameters for the debugging tool

module DebuggerConfig
  # General settings
  DEBUGGER_DIR = File.expand_path("~/debugger")

  # Paths and directories
  LOGS_DIR = File.join(DEBUGGER_DIR, "logs")
  PROMPTS_DIR = File.join(DEBUGGER_DIR, "prompts")

  # System prompts and schemas
  SYSTEM_PROMPT_PATH = ENV["DEBUGGER_SYSTEM_PROMPT"] || File.join(DEBUGGER_DIR, "system_prompt.md")
  RESPONSE_SCHEMA_PATH = ENV["DEBUGGER_RESPONSE_SCHEMA"] || File.join(DEBUGGER_DIR, "general_schema.json")

  # API Keys with environment variable fallbacks
  # Use ENV variables first, then fallback to default values
  ANTHROPIC_API_KEY = ENV["ANTHROPIC_API_KEY"] || "your_anthropic_api_key_here"
  OPENAI_API_KEY = ENV["OPENAI_API_KEY"] || "your_openai_api_key_here"
  GEMINI_API_KEY = ENV["GEMINI_API_KEY"] || "your_gemini_api_key_here"
  DEEPSEEK_API_KEY = ENV["DEEPSEEK_API_KEY"] || "your_deepseek_api_key_here"

  # AI provider configuration (can be overridden with env var)
  DEFAULT_PROVIDER = ENV["DEBUGGER_AI_PROVIDER"] || "anthropic" # Options: "anthropic", "openai", "gemini", "deepseek"

  # Provider-specific configurations
  PROVIDER_CONFIG = {
    "anthropic" => {
      "model" => ENV["ANTHROPIC_MODEL"],
      "token_limit" => ENV["ANTHROPIC_TOKEN_LIMIT"]&.to_i,
      "version" => ENV["ANTHROPIC_VERSION"] || "2023-06-01",
      "beta" => ENV["ANTHROPIC_BETA"] || "prompt-caching-2024-07-31"
    },
    "openai" => {
      "model" => ENV["OPENAI_MODEL"],
      "token_limit" => ENV["OPENAI_TOKEN_LIMIT"]&.to_i,
      "org_id" => ENV["OPENAI_ORG_ID"]
    },
    "gemini" => {
      "model" => ENV["GEMINI_MODEL"],
      "token_limit" => ENV["GEMINI_TOKEN_LIMIT"]&.to_i
    },
    "deepseek" => {
      "model" => ENV["DEEPSEEK_MODEL"],
      "token_limit" => ENV["DEEPSEEK_TOKEN_LIMIT"]&.to_i
    }
  }

  # Create the necessary directories if they don't exist
  def self.setup_directories
    [LOGS_DIR, PROMPTS_DIR].each do |dir|
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end
  end

  # Get API key for the selected provider
  def self.get_api_key(provider)
    case provider
    when "anthropic", AiServiceProvider::PROVIDER_ANTHROPIC
      ANTHROPIC_API_KEY
    when "openai", AiServiceProvider::PROVIDER_OPENAI
      OPENAI_API_KEY
    when "gemini", AiServiceProvider::PROVIDER_GEMINI
      GEMINI_API_KEY
    when "deepseek", AiServiceProvider::PROVIDER_DEEPSEEK
      DEEPSEEK_API_KEY
    else
      raise "Unknown provider: #{provider}"
    end
  end

  # Get custom model if set, otherwise return nil to use default
  def self.get_custom_model(provider)
    PROVIDER_CONFIG.dig(provider, "model")
  end

  # Get custom token limit if set, otherwise return nil to use default
  def self.get_custom_token_limit(provider)
    PROVIDER_CONFIG.dig(provider, "token_limit")
  end

  # Get additional provider-specific configuration
  def self.get_provider_config(provider)
    PROVIDER_CONFIG[provider] || {}
  end

  # Validate that the current configuration is valid
  def self.validate_config
    errors = []

    # Check that required directories exist
    errors << "Root directory does not exist: #{DEBUGGER_DIR}" unless File.directory?(DEBUGGER_DIR)

    # Check that required files exist
    errors << "System prompt file not found: #{SYSTEM_PROMPT_PATH}" unless File.exist?(SYSTEM_PROMPT_PATH)
    errors << "Response schema file not found: #{RESPONSE_SCHEMA_PATH}" unless File.exist?(RESPONSE_SCHEMA_PATH)

    # Check API keys
    case DEFAULT_PROVIDER
    when "anthropic", AiServiceProvider::PROVIDER_ANTHROPIC
      errors << "Anthropic API key looks invalid" if ANTHROPIC_API_KEY.nil? || ANTHROPIC_API_KEY == "your_anthropic_api_key_here"
    when "openai", AiServiceProvider::PROVIDER_OPENAI
      errors << "OpenAI API key looks invalid" if OPENAI_API_KEY.nil? || OPENAI_API_KEY == "your_openai_api_key_here"
    when "gemini", AiServiceProvider::PROVIDER_GEMINI
      errors << "Gemini API key looks invalid" if GEMINI_API_KEY.nil? || GEMINI_API_KEY == "your_gemini_api_key_here"
    when "deepseek", AiServiceProvider::PROVIDER_DEEPSEEK
      errors << "DeepSeek API key looks invalid" if DEEPSEEK_API_KEY.nil? || DEEPSEEK_API_KEY == "your_deepseek_api_key_here"
    end

    if errors.any?
      puts "Configuration errors:"
      errors.each { |error| puts "- #{error}" }
      puts "Please fix these issues before continuing."
    end

    errors.empty?
  end

  # Display current configuration
  def self.display_config
    puts "Current Configuration:"
    puts "---------------------"
    puts "AI Provider: #{DEFAULT_PROVIDER}"

    model = get_custom_model(DEFAULT_PROVIDER) || "default"
    token_limit = get_custom_token_limit(DEFAULT_PROVIDER) || "default"

    puts "Model: #{model}"
    puts "Token Limit: #{token_limit}"
    puts "System Prompt: #{SYSTEM_PROMPT_PATH}"
    puts "Response Schema: #{RESPONSE_SCHEMA_PATH}"
    puts "Log Directory: #{LOGS_DIR}"
  end

  # Initialize configuration when module is loaded
  setup_directories
end
