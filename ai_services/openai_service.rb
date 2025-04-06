require_relative 'base_service'

module AiServices
  class OpenaiService < BaseService
    # API Provider constant
    PROVIDER_NAME = 'openai'

    # API URL
    DEFAULT_API_URL = "https://api.openai.com/v1/chat/completions"

    # Default model
    DEFAULT_MODEL = "gpt-4-turbo"

    # Default token limit
    DEFAULT_TOKEN_LIMIT = 4096

    # Initialize with configuration
    def initialize(config)
      super(config)
      @model = config[:model] || DEFAULT_MODEL
      @max_tokens = config[:max_tokens] || DEFAULT_TOKEN_LIMIT
      @api_url = config[:api_url] || DEFAULT_API_URL
      @openai_org_id = config[:openai_org_id]
    end

    # Implementation of provider_name for OpenAI
    def provider_name
      PROVIDER_NAME
    end

    # Call OpenAI API (GPT models)
    def call_api(conversation, allowed_tokens = nil)
      allowed_tokens ||= @max_tokens

      uri = URI(@api_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 300

      request = Net::HTTP::Post.new(uri.path, {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      })

      # Add organization header if provided
      request["OpenAI-Organization"] = @openai_org_id if @openai_org_id

      # Convert conversation format for OpenAI
      openai_messages = conversation.map do |msg|
        {
          "role" => msg["role"],
          "content" => msg["content"]
        }
      end

      # Add system prompt if provided
      if @system_prompt
        openai_messages.unshift({
          "role" => "developer",
          "content" => @system_prompt
        })
      end

      body = {
        "model" => @model,
        "messages" => openai_messages,
        "reasoning_effort"=> "high",
        "max_completion_tokens" => allowed_tokens,
      }

      # Add function calling if schema is provided
      if @schema
        body["tools"] = [convert_schema(@schema)]
        body["tool_choice"] = { "type" => "function", "function" => { "name" => @schema["name"] } }
      end

      request.body = body.to_json

      log_request(body)
      response = http.request(request)
      response_body = JSON.parse(response.body)
      log_response(response)

      if response.is_a?(Net::HTTPSuccess)
        choices = response_body["choices"]
        if !choices || choices.empty?
          raise "Empty choices in OpenAI response"
        end

        message = choices[0]["message"]
        if message["tool_calls"] && !message["tool_calls"].empty?
          tool_call = message["tool_calls"][0]
          return JSON.parse(tool_call["function"]["arguments"])
        else
          return message["content"]
        end
      else
        error_msg = "API error: #{response_body.dig('error', 'message') || response.body}"
        raise error_msg
      end
    end

    private

    # Convert schema to OpenAI format
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
