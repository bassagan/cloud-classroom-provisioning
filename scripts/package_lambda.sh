#!/bin/bash

# Exit on error
set -e

# Get the absolute path of the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create the user_management directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/functions/user_management"

# Check if virtualenv is installed
if ! command -v virtualenv &> /dev/null; then
    echo "virtualenv is not installed. Installing..."
    pip install virtualenv
fi

# Create a temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Create and activate virtual environment
python3 -m venv "$TEMP_DIR/venv"
source "$TEMP_DIR/venv/bin/activate"

# Install dependencies
echo "Installing dependencies..."
pip install -r "$PROJECT_ROOT/functions/aws/requirements.txt"

# Copy function code
echo "Copying function code..."
cp "$PROJECT_ROOT/functions/aws/lambda_function.py" "$TEMP_DIR/"

# Create deployment package
echo "Creating deployment package..."
cd "$TEMP_DIR"
zip -r9 "$PROJECT_ROOT/functions/user_management/lambda_function.zip" .

# Clean up
echo "Cleaning up..."
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo "Lambda function packaged successfully as functions/user_management/lambda_function.zip" 