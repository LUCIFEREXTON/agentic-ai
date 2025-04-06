require_relative 'base_service'

module AiServices
  class AnthropicService < BaseService
    # API Provider constant
    PROVIDER_NAME = 'anthropic'

    # API URL
    DEFAULT_API_URL = "https://api.anthropic.com/v1/messages"

    # Default models
    DEFAULT_MODEL = "claude-3-7-sonnet-20250219"

    # Default token limit
    DEFAULT_TOKEN_LIMIT = 8192

    # Anthropic specific headers
    DEFAULT_VERSION = "2023-06-01"
    DEFAULT_BETA = "prompt-caching-2024-07-31"

    # Initialize with configuration
    def initialize(config)
      super(config)
      @model = config[:model] || DEFAULT_MODEL
      @max_tokens = config[:max_tokens] || DEFAULT_TOKEN_LIMIT
      @api_url = config[:api_url] || DEFAULT_API_URL
      provider_config = config[:provider_config] || {}
      @anthropic_version = provider_config["version"] || DEFAULT_VERSION
      @anthropic_beta = provider_config["beta"] || DEFAULT_BETA
    end

    # Implementation of provider_name for Anthropic
    def provider_name
      PROVIDER_NAME
    end

    # Call Anthropic API (Claude models)
    def call_api(conversation, allowed_tokens = nil)
      allowed_tokens ||= @max_tokens

      uri = URI(@api_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 400

      request = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "x-api-key" => @api_key,
        "anthropic-version" => @anthropic_version,
        "anthropic-beta" => @anthropic_beta
      })

      body = {
        "model" => @model,
        "messages" => conversation,
        "max_tokens" => allowed_tokens
      }

      if @system_prompt
        body["system"] = [{ "type" => "text", "text" => @system_prompt }]
      end

      if @schema
        body["tools"] = [convert_schema(@schema)]
        body["tool_choice"] = { "type" => "tool", "name" => @schema["name"] }
      end

      request.body = body.to_json

      log_request(body)
      response = http.request(request)
      response_body = JSON.parse(response.body)
      log_response(response)

      if response.is_a?(Net::HTTPSuccess)
        content_array = response_body["content"]
        unless content_array && !content_array.empty?
          raise "Empty response content from Anthropic API"
        end

        content = content_array.find { |c| c['type'] == 'tool_use' }
        text_content = content_array.find { |c| c['type'] == 'text' }
        if content
          return content['input']
        elsif text_content
          return text_content['text']
        else
          raise "No valid content found in Anthropic response"
        end
      else
        error_msg = "API error: #{response_body.dig('error', 'message') || response.body}"
        raise error_msg
      end
    end

    private

    # Convert schema to Anthropic format
    def convert_schema(schema)
      name, description, inputs = schema.values_at("name", "description", "inputs")
      input_schema = {
        "type" => "object",
        "properties" => {}
      }

      inputs.each do |input|
        input_schema["properties"][input["name"]] = parse_input_object(input)
      end

      required = inputs.select { |input| input["required"] }.map { |input| input["name"] }
      tool_hash = {
        "name" => name,
        "description" => description,
        "input_schema" => input_schema,
      }

      tool_hash["input_schema"]["required"] = required if !required.empty?
      return tool_hash
    end
  end
end
