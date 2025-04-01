#!/bin/bash

# Exit on error
set -e

# Get the absolute path of the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse command line arguments
CLOUD_PROVIDER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --cloud)
      CLOUD_PROVIDER="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Usage: $0 --cloud [aws|azure]"
      exit 1
      ;;
  esac
done

if [ -z "$CLOUD_PROVIDER" ] || [[ ! "$CLOUD_PROVIDER" =~ ^(aws|azure)$ ]]; then
  echo "Error: --cloud parameter must be either 'aws' or 'azure'"
  exit 1
fi

# Create the packages directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/functions/packages"

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

if [ "$CLOUD_PROVIDER" == "aws" ]; then
    # AWS Lambda packaging
    echo "Packaging AWS Lambda function..."
    PACKAGE_PATH="$PROJECT_ROOT/functions/packages/lambda_function.zip"
    
    # Install dependencies
    pip install -r "$PROJECT_ROOT/functions/aws/requirements.txt"
    
    # Copy function code
    cp "$PROJECT_ROOT/functions/aws/lambda_function.py" "$TEMP_DIR/"
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip -r9 "$PACKAGE_PATH" .
    
    # Verify package
    if [ ! -f "$PACKAGE_PATH" ]; then
        echo "Error: Failed to create AWS Lambda package at $PACKAGE_PATH"
        exit 1
    fi
    
    echo "AWS Lambda function packaged successfully at: $PACKAGE_PATH"
else
    # Azure Function packaging
    echo "Packaging Azure Function..."
    PACKAGE_PATH="$PROJECT_ROOT/functions/packages/azure_function.zip"
    
    # Install dependencies
    pip install -r "$PROJECT_ROOT/functions/azure/requirements.txt"
    
    # Copy all Azure function files
    cp -r "$PROJECT_ROOT/functions/azure/"* "$TEMP_DIR/"
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip -r9 "$PACKAGE_PATH" . -x "*.pyc" "__pycache__/*" "*.git*"
    
    # Verify package
    if [ ! -f "$PACKAGE_PATH" ]; then
        echo "Error: Failed to create Azure Function package at $PACKAGE_PATH"
        exit 1
    fi
    
    # Verify package contents
    echo "Verifying package contents..."
    if ! unzip -l "$PACKAGE_PATH" | grep -q "function_app.py"; then
        echo "Error: Package is missing function_app.py"
        exit 1
    fi
    if ! unzip -l "$PACKAGE_PATH" | grep -q "requirements.txt"; then
        echo "Error: Package is missing requirements.txt"
        exit 1
    fi
    if ! unzip -l "$PACKAGE_PATH" | grep -q "function.json"; then
        echo "Error: Package is missing function.json"
        exit 1
    fi
    
    echo "Azure Function packaged successfully at: $PACKAGE_PATH"
    echo "Package contents verified successfully"
fi

# Clean up
echo "Cleaning up..."
deactivate
cd - > /dev/null
rm -rf "$TEMP_DIR" 