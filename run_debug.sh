#!/bin/bash

# Ensure we're in the right directory
cd "$(dirname "$0")"

# Check if Bundler is installed
if ! command -v bundle >/dev/null 2>&1; then
  echo "Bundler is not installed. Please run ./install_dependencies.sh first."
  exit 1
fi

# Create required directories if they don't exist
mkdir -p ~/debugger/prompts/system
mkdir -p ~/debugger/prompts/templates

# Run the debugger with Bundler to ensure all dependencies are available
# Pass any command-line arguments along to the script
bundle exec ruby debug.rb "$@"
