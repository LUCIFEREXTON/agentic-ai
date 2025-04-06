require 'net/http'
require 'uri'
require 'json'
require 'time'

module AiServices
  class BaseService
    # Default token limits
    DEFAULT_TOKEN_LIMIT = 4096

    # Initialize with configuration
    def initialize(config)
      @api_key = config[:api_key]
      @model = config[:model]
      @max_tokens = config[:max_tokens] || DEFAULT_TOKEN_LIMIT
      @api_url = config[:api_url]
      @system_prompt = config[:system_prompt]
      @schema = config[:schema]
      @logger = config[:logger]
    end

    # Call the AI API - to be implemented by subclasses
    def call_api(conversation, allowed_tokens = nil)
      raise NotImplementedError, "Subclasses must implement call_api method"
    end

    # Get model information
    def get_model_info
      {
        provider: provider_name,
        model: @model,
        max_tokens: @max_tokens
      }
    end

    # Provider name - to be implemented by subclasses
    def provider_name
      raise NotImplementedError, "Subclasses must implement provider_name method"
    end

    protected

    # Log request details if logger is available
    def log_request(body)
      return unless @logger
      @logger.debug("#{provider_name.upcase} REQUEST: #{body.to_json}")
    end

    # Log response details if logger is available
    def log_response(response)
      return unless @logger
      @logger.debug("#{provider_name.upcase} RESPONSE - Status: #{response.code}\n#{response.body}")
    end

    # Parse input object for schema
    def parse_input_object(input)
      type, description, enum, properties, item = input.values_at("type", "description", "enum", "properties", "item")
      parsed_input = {
        "type" => type,
        "description" => description
      }
      if ["string", "number"].include?(type) && enum && !enum.empty?
        parsed_input["enum"] = enum
      elsif type == "object"
        parsed_input["properties"] = {}
        properties.each do |property|
          parsed_input["properties"][property["name"]] = parse_input_object(property)
        end
        required = properties.select { |property| property["required"] }
                            .map { |property| property["name"] }
        parsed_input["required"] = required if !required.empty?
      elsif type == "array"
        parsed_input["items"] = parse_input_object(item)
      end
      parsed_input
    end
  end
end
