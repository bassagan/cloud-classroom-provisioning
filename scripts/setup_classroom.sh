#!/bin/bash

# Exit on error
set -e

# Check if required tools are installed
check_prerequisites() {
  local cloud=$1
  command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed. Aborting." >&2; exit 1; }
  
  if [ "$cloud" = "aws" ]; then
    command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required but not installed. Aborting." >&2; exit 1; }
  elif [ "$cloud" = "azure" ]; then
    command -v az >/dev/null 2>&1 || { echo "Azure CLI is required but not installed. Aborting." >&2; exit 1; }
  fi
}

# Default values
CLASSROOM_NAME=""
CLOUD_PROVIDER="aws"
REGION="eu-west-1"
LOCATION="westeurope"
ACTION="create"

# Function to display usage
usage() {
  echo "Usage: $0 --name <classroom-name> --cloud [aws|azure] [--region <aws-region>] [--location <azure-location>] [--destroy]"
  echo ""
  echo "Options:"
  echo "  --name      Name of the classroom (required)"
  echo "  --cloud     Cloud provider (aws or azure, default: aws)"
  echo "  --region    AWS region (default: eu-west-1)"
  echo "  --location  Azure location (default: westeurope)"
  echo "  --destroy   Destroy the classroom resources instead of creating them"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      CLASSROOM_NAME="$2"
      shift 2
      ;;
    --cloud)
      CLOUD_PROVIDER="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --location)
      LOCATION="$2"
      shift 2
      ;;
    --destroy)
      ACTION="destroy"
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown parameter: $1"
      usage
      ;;
  esac
done

# Validate required parameters
if [ -z "$CLASSROOM_NAME" ]; then
  echo "Error: Classroom name is required (--name)"
  usage
fi

if [ "$CLOUD_PROVIDER" != "aws" ] && [ "$CLOUD_PROVIDER" != "azure" ]; then
  echo "Error: Cloud provider must be either 'aws' or 'azure'"
  usage
fi

# Check prerequisites
check_prerequisites "$CLOUD_PROVIDER"

# Verify cloud provider authentication
if [ "$CLOUD_PROVIDER" = "aws" ]; then
  # Test AWS credentials
  aws sts get-caller-identity >/dev/null || { echo "Error: AWS authentication failed. Please run 'aws configure' first." >&2; exit 1; }
elif [ "$CLOUD_PROVIDER" = "azure" ]; then
  # Test Azure login
  az account show >/dev/null || { echo "Error: Azure authentication failed. Please run 'az login' first." >&2; exit 1; }
fi

# Set classroom directory
CLASSROOM_DIR="classrooms/$CLASSROOM_NAME"

if [ "$ACTION" = "destroy" ]; then
  if [ ! -d "$CLASSROOM_DIR" ]; then
    echo "Error: Classroom directory '$CLASSROOM_DIR' does not exist"
    exit 1
  fi
  
  echo "Destroying classroom '$CLASSROOM_NAME'..."
  cd "$CLASSROOM_DIR"
  terraform init
  terraform destroy -auto-approve
  cd ../..
  echo "Classroom '$CLASSROOM_NAME' has been destroyed successfully!"
  exit 0
fi

# Create classroom directory
mkdir -p "$CLASSROOM_DIR"

# Copy Terraform configuration
if [ "$CLOUD_PROVIDER" = "aws" ]; then
  cp -r iac/aws/* "$CLASSROOM_DIR/"
  mkdir -p "$CLASSROOM_DIR/functions"
  cp -r functions/aws/* "$CLASSROOM_DIR/functions/"
else
  cp -r iac/azure/* "$CLASSROOM_DIR/"
  mkdir -p "$CLASSROOM_DIR/functions"
  cp -r functions/azure/* "$CLASSROOM_DIR/functions/"
fi

# Create terraform.tfvars file
if [ "$CLOUD_PROVIDER" = "aws" ]; then
  cat > "$CLASSROOM_DIR/terraform.tfvars" << EOF
aws_region = "$REGION"
environment = "classroom"
classroom_name = "$CLASSROOM_NAME"
owner = "$USER"
EOF
else
  cat > "$CLASSROOM_DIR/terraform.tfvars" << EOF
azure_location = "$LOCATION"
environment = "classroom"
classroom_name = "$CLASSROOM_NAME"
owner = "$USER"
EOF
fi

# Package Lambda function if using AWS
if [ "$CLOUD_PROVIDER" = "aws" ]; then
  echo "Packaging Lambda function..."
  ./scripts/package_lambda.sh
fi

# Initialize and apply Terraform
cd "$CLASSROOM_DIR"
terraform init
terraform apply -auto-approve

echo "Classroom '$CLASSROOM_NAME' has been set up successfully!"
if [ "$CLOUD_PROVIDER" = "aws" ]; then
  echo "AWS Region: $REGION"
  echo "Lambda Function URL will be available in the Terraform outputs"
  echo "Use this URL to create student accounts on demand"
else
  echo "Azure Location: $LOCATION"
  echo "Function URL will be available in the Terraform outputs"
  echo "Use this URL to create student accounts on demand"
fi
