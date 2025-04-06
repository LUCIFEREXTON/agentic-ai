#!/bin/bash

# Create a random temporary file
output_file=$(mktemp /tmp/code_wrapper.XXXXXX)

process_file() {
  local file="$1"
  if [ -f "$file" ]; then
    # Create the opening tag
    echo "<example-code name=\"$file\">" >> "$output_file"
    # Output file contents
    cat "$file" >> "$output_file"
    # Create the closing tag
    echo "</example-code>
" >> "$output_file"
  fi
}

# Check if any arguments were provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 [file(s) or directory]"
  exit 1
fi

# Process all arguments
for path in "$@"; do
  if [ -d "$path" ]; then
    # If argument is a directory, process all files in it
    find "$path" -type f | while read file; do
      process_file "$file"
    done
  elif [ -f "$path" ]; then
    # If argument is a file, process it directly
    process_file "$path"
  else
    echo "Error: '$path' is not a valid file or directory" >&2
  fi
done

echo "Output written to: $output_file"
