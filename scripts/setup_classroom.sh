#!/bin/bash

# Exit on error
set -e

# Function to display usage
usage() {
  echo "Usage: $0 --name <classroom-name> --cloud [aws|azure] [--region <aws-region>] [--location <azure-location>] [--destroy] [--parallelism <number>] [--force-unlock] [--setup-rbac]"
  echo ""
  echo "Options:"
  echo "  --name         Name of the classroom (required)"
  echo "  --cloud        Cloud provider (aws or azure, default: aws)"
  echo "  --region       AWS region (default: eu-west-1)"
  echo "  --location     Azure location (default: centralus)"
  echo "  --destroy      Destroy the classroom resources instead of creating them"
  echo "  --parallelism  Number of parallel operations (default: 4)"
  echo "  --force-unlock Force unlock the state if it's locked"
  echo "  --setup-rbac   Setup RBAC roles for Azure (only for Azure)"
  exit 1
}

# Function to handle Azure login
azure_login() {
  echo "Logging into Azure..."
  az login
  if [ $? -ne 0 ]; then
    echo "Failed to login to Azure. Please try again."
    exit 1
  fi
  
  # Get subscription ID
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "No subscription found. Please set up a subscription first."
    exit 1
  fi
  
  # Get tenant ID
  TENANT_ID=$(az account show --query tenantId -o tsv)
  if [ -z "$TENANT_ID" ]; then
    echo "No tenant ID found. Please check your Azure account."
    exit 1
  fi
  
  # Set the subscription
  az account set --subscription "$SUBSCRIPTION_ID"
  
  # Export the values for Terraform
  export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
  export ARM_TENANT_ID="$TENANT_ID"
}

# Function to run terraform with parallelism
run_terraform() {
  local action=$1
  local dir=$2
  cd "$dir"
  
  if [ "$action" = "destroy" ]; then
    echo "Destroying resources in $dir..."
    terraform destroy -auto-approve -parallelism="$PARALLELISM"
  else
    echo "Creating resources in $dir..."
    terraform init
    terraform apply -auto-approve -parallelism="$PARALLELISM"
  fi
  cd - > /dev/null
}

# Default values
CLASSROOM_NAME=""
CLOUD_PROVIDER="aws"
REGION="eu-west-1"
LOCATION="centralus"
ACTION="create"
PARALLELISM=4
FORCE_UNLOCK=false
SETUP_RBAC=false

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
    --parallelism)
      PARALLELISM="$2"
      shift 2
      ;;
    --force-unlock)
      FORCE_UNLOCK=true
      shift
      ;;
    --setup-rbac)
      SETUP_RBAC=true
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

# Package the function code first
#echo "Packaging function code for $CLOUD_PROVIDER..."
#if ! ./scripts/package_lambda.sh --cloud "$CLOUD_PROVIDER"; then
#  echo "Error: Failed to package function code"
#  exit 1
#fi

# Handle Azure login if needed
if [ "$CLOUD_PROVIDER" = "azure" ]; then
  azure_login
  
  # Setup RBAC roles if requested
  if [ "$SETUP_RBAC" = true ]; then
    echo "Setting up Azure RBAC roles..."
    ./scripts/setup_azure_rbac.sh --create
  fi

  # Run terraform first
  run_terraform "$ACTION" "iac/azure"
  
  # Only deploy function if we're not destroying and terraform apply was successful
  if [ "$ACTION" != "destroy" ]; then
    echo "Deploying Azure function..."
    # Get the values directly from terraform outputs
    cd "iac/azure"
    FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
    RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
    cd - > /dev/null

    # Deploy the function using the dedicated script
    if [ -n "$FUNCTION_APP_NAME" ] && [ -n "$RESOURCE_GROUP_NAME" ]; then
        ./scripts/deploy_azure_function.sh \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP_NAME"
    else
        echo "Error: Could not get function app name or resource group from Terraform outputs"
        exit 1
    fi
  fi
else
  # AWS path remains unchanged
  run_terraform "$ACTION" "iac/aws"
fi

if [ "$ACTION" = "create" ]; then
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
else
  echo "Classroom '$CLASSROOM_NAME' has been destroyed successfully!"
fi 