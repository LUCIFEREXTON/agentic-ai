require_relative 'base_service'

module AiServices
  class DeepseekService < BaseService
    # API Provider constant
    PROVIDER_NAME = 'deepseek'

    # API URL
    DEFAULT_API_URL = "https://api.deepseek.com/beta/chat/completions"

    # Default models
    DEFAULT_MODEL = "deepseek-reasoner"

    # Default token limit
    DEFAULT_TOKEN_LIMIT = 8000

    # Initialize with configuration
    def initialize(config)
      super(config)
      @model = config[:model] || DEFAULT_MODEL
      @max_tokens = config[:max_tokens] || DEFAULT_TOKEN_LIMIT
      @api_url = config[:api_url] || DEFAULT_API_URL
    end

    # Implementation of provider_name for DeepSeek
    def provider_name
      PROVIDER_NAME
    end

    # Call DeepSeek API
    def call_api(conversation, allowed_tokens = nil)
      allowed_tokens ||= @max_tokens

      uri = URI(@api_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 400

      request = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      })

      body = {
        "model" => @model,
        "messages" => conversation,
        "max_tokens" => allowed_tokens
      }


      # Add JSON response format if needed
      if @schema
        body["tools"] = [convert_schema(@schema)]
        body["tool_choice"] = {
          "type" => "function",
          "function" => {
            "name" => @schema["name"]
          }
        }
      end

      request.body = body.to_json

      log_request(body)
      response = http.request(request)
      response_body = JSON.parse(response.body)
      log_response(response)

      if response.is_a?(Net::HTTPSuccess)
        choice = response_body.dig('choices', 0)
        finish_reason = choice['finish_reason']

        # Extract result from JSON output if schema provided
        json_output = choice.dig('message', 'tool_calls', 0, 'function', 'arguments') if @schema
        if @schema && json_output && !json_output.empty?
          result = json_output
        else
          result = choice['message']['content']
        end

        @logger.info "#{response_body['usage']&.to_json} tokens used" if @logger

        return result
      else
        if response.code == '429' || response.code == '503'
          raise "Rate limit exceeded. Please try again later."
        else
          error_msg = "API error: #{response_body.dig('error', 'message') || response.body}"
          raise error_msg
        end
      end
    rescue JSON::ParserError
      raise "Invalid JSON response from DeepSeek API"
    end

    private

    # Convert schema for DeepSeek's format (uses OpenAI-style function calling)
    def convert_schema(schema)
      name, description, inputs = schema.values_at("name", "description", "inputs")
      parameters = {
        "type" => "object",
        "properties" => {}
      }

      inputs.each do |input|
        parameters["properties"][input["name"]] = parse_input_object(input)
      end

      required = inputs.select { |input| input["required"] }.map { |input| input["name"] }
      parameters["required"] = required if !required.empty?

      return {
        "type" => "function",
        "function" => {
          "name" => name,
          "description" => description,
          "parameters" => parameters
        }
      }
    end
  end
end
