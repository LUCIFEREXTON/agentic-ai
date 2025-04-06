#!/usr/bin/env ruby

require_relative 'ai_services/service_factory'

class AiServiceProvider
  # Provider constants
  PROVIDER_ANTHROPIC = AiServices::ServiceFactory::PROVIDER_ANTHROPIC
  PROVIDER_OPENAI = AiServices::ServiceFactory::PROVIDER_OPENAI
  PROVIDER_GEMINI = AiServices::ServiceFactory::PROVIDER_GEMINI
  PROVIDER_DEEPSEEK = AiServices::ServiceFactory::PROVIDER_DEEPSEEK

  # Initialize with configuration
  def initialize(config)
    @service = AiServices::ServiceFactory.create(config)
  end

  # Main method to call the selected AI API
  def call_api(conversation, allowed_tokens = nil)
    @service.call_api(conversation, allowed_tokens)
  end

  # Get model information
  def get_model_info
    @service.get_model_info
  end

  # Get available providers
  def self.available_providers
    AiServices::ServiceFactory.available_providers
  end

  # Get default model for a provider
  def self.default_model(provider)
    AiServices::ServiceFactory.default_model(provider)
  end

  # Get default token limit for a provider
  def self.default_token_limit(provider)
    AiServices::ServiceFactory.default_token_limit(provider)
  end

  # Get API URL for a provider
  def self.provider_url(provider)
    AiServices::ServiceFactory.provider_url(provider)
  end
end
