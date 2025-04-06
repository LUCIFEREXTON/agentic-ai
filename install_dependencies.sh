#!/bin/bash

echo "Installing dependencies for the debugger..."

# Check if Ruby is installed
if ! command -v ruby >/dev/null 2>&1; then
  echo "Ruby is not installed. Please install Ruby and try again."
  exit 1
fi

# Check if Bundler is installed
if ! command -v bundle >/dev/null 2>&1; then
  echo "Installing Bundler..."
  gem install bundler
fi

# Install dependencies using Bundler
echo "Installing dependencies from Gemfile..."
bundle install

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
  echo "Creating .env file from template..."
  cp .env.example .env
  echo ".env file created. Please edit it with your API keys."
else
  echo ".env file already exists."
fi

# Create required directories
mkdir -p ~/debugger/logs
mkdir -p ~/debugger/prompts

echo "Setup complete! You can now use the debugger with your preferred AI provider."
echo "To switch providers, edit your .env file and set DEBUGGER_AI_PROVIDER to one of: anthropic, openai, gemini"
echo "Run the debugger using: ./run_debug.sh"
