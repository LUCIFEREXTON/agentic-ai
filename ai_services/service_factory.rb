require_relative 'anthropic_service'
require_relative 'openai_service'
require_relative 'gemini_service'
require_relative 'deepseek_service'

module AiServices
  class ServiceFactory
    # Provider constants
    PROVIDER_ANTHROPIC = 'anthropic'
    PROVIDER_OPENAI = 'openai'
    PROVIDER_GEMINI = 'gemini'
    PROVIDER_DEEPSEEK = 'deepseek'

    # Create a service instance based on the provider
    def self.create(config)
      provider = config[:provider]

      case provider
      when PROVIDER_ANTHROPIC
        AnthropicService.new(config)
      when PROVIDER_OPENAI
        OpenaiService.new(config)
      when PROVIDER_GEMINI
        GeminiService.new(config)
      when PROVIDER_DEEPSEEK
        DeepseekService.new(config)
      else
        raise "Unknown provider: #{provider}"
      end
    end

    # Get available providers
    def self.available_providers
      [PROVIDER_ANTHROPIC, PROVIDER_OPENAI, PROVIDER_GEMINI, PROVIDER_DEEPSEEK]
    end

    # Get default model for a provider
    def self.default_model(provider)
      case provider
      when PROVIDER_ANTHROPIC
        AnthropicService::DEFAULT_MODEL
      when PROVIDER_OPENAI
        OpenaiService::DEFAULT_MODEL
      when PROVIDER_GEMINI
        GeminiService::DEFAULT_MODEL
      when PROVIDER_DEEPSEEK
        DeepseekService::DEFAULT_MODEL
      else
        raise "Unknown provider: #{provider}"
      end
    end

    # Get default token limit for a provider
    def self.default_token_limit(provider)
      case provider
      when PROVIDER_ANTHROPIC
        AnthropicService::DEFAULT_TOKEN_LIMIT
      when PROVIDER_OPENAI
        OpenaiService::DEFAULT_TOKEN_LIMIT
      when PROVIDER_GEMINI
        GeminiService::DEFAULT_TOKEN_LIMIT
      when PROVIDER_DEEPSEEK
        DeepseekService::DEFAULT_TOKEN_LIMIT
      else
        raise "Unknown provider: #{provider}"
      end
    end

    # Get API URL for a provider
    def self.provider_url(provider)
      case provider
      when PROVIDER_ANTHROPIC
        AnthropicService::DEFAULT_API_URL
      when PROVIDER_OPENAI
        OpenaiService::DEFAULT_API_URL
      when PROVIDER_GEMINI
        GeminiService::DEFAULT_API_URL
      when PROVIDER_DEEPSEEK
        DeepseekService::DEFAULT_API_URL
      else
        raise "Unknown provider: #{provider}"
      end
    end
  end
end
