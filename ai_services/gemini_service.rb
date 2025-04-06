require_relative 'base_service'

module AiServices
  class GeminiService < BaseService
    # API Provider constant
    PROVIDER_NAME = 'gemini'

    # API URL
    DEFAULT_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/"

    # Default model
    DEFAULT_MODEL = "gemini-1.5-pro"

    # Default token limit
    DEFAULT_TOKEN_LIMIT = 4096

    # Initialize with configuration
    def initialize(config)
      super(config)
      @model = config[:model] || DEFAULT_MODEL
      @max_tokens = config[:max_tokens] || DEFAULT_TOKEN_LIMIT
      @api_url = config[:api_url] || DEFAULT_API_URL
    end

    # Implementation of provider_name for Gemini
    def provider_name
      PROVIDER_NAME
    end

    # Call Gemini API (Google models)
    def call_api(conversation, allowed_tokens = nil)
      allowed_tokens ||= @max_tokens

      uri = URI("#{@api_url}#{@model}:generateContent?key=#{@api_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 400

      request = Net::HTTP::Post.new(uri, {
        "Content-Type" => "application/json"
      })

      # Convert conversation format for Gemini
      gemini_contents = []

      conversation.each do |msg|
        role = msg["role"] == "assistant" ? "model" : msg["role"]
        gemini_contents << {
          "role" => role,
          "parts" => [{"text" => msg["content"]}]
        }
      end

      body = {
        "contents" => gemini_contents,
        "generationConfig" => {
          "maxOutputTokens" => allowed_tokens
        }
      }

      # Add system instructions if provided
      if @system_prompt
        body["systemInstruction"] = {
          "parts" => [{"text" => @system_prompt}]
        }
      end

      # Add response schema if needed
      if @schema
        body["generationConfig"]["responseMimeType"] = "application/json"
        body["generationConfig"]["responseSchema"] = convert_schema(@schema)
      end

      request.body = body.to_json

      log_request(body)
      response = http.request(request)
      response_body = JSON.parse(response.body)
      log_response(response)

      if response.is_a?(Net::HTTPSuccess)
        candidate = response_body.dig("candidates", 0)
        if !candidate
          raise "No candidates in Gemini response"
        end

        content = candidate.dig("content", "parts", 0, "text")
        if content.nil?
          raise "No content in Gemini response"
        end

        return content
      else
        error_msg = "API error: #{response_body.dig('error', 'message') || response.body}"
        raise error_msg
      end
    end

    private

    # Convert schema to Gemini format
    def convert_schema(schema)
      name, description, inputs = schema.values_at("name", "description", "inputs")
      gemini_schema = {
        "type" => "OBJECT",
        "properties" => {}
      }

      inputs.each do |input|
        gemini_schema["properties"][input["name"]] = parse_input_object_for_gemini(input)
      end

      required = inputs.select { |input| input["required"] }.map { |input| input["name"] }
      gemini_schema["required"] = required if !required.empty?

      return gemini_schema
    end

    # Parse input object specifically for Gemini (with uppercase types)
    def parse_input_object_for_gemini(input)
      type, description, enum, properties, item = input.values_at("type", "description", "enum", "properties", "item")
      parsed_input = {
        "type" => type.upcase,
        "description" => description
      }
      if ["string", "number"].include?(type) && enum && !enum.empty?
        parsed_input["enum"] = enum.map(&:upcase)
      elsif type == "object"
        parsed_input["properties"] = {}
        properties.each do |property|
          parsed_input["properties"][property["name"]] = parse_input_object_for_gemini(property)
        end
        required = properties.select { |property| property["required"] }.map { |property| property["name"] }
        parsed_input["required"] = required if !required.empty?
      elsif type == "array"
        parsed_input["items"] = parse_input_object_for_gemini(item)
      end
      parsed_input
    end
  end
end
