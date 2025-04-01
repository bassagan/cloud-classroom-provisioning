#!/bin/bash

# Exit on error
set -e

# Check if required tools are installed
check_prerequisites() {
  command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed. Aborting." >&2; exit 1; }
  command -v az >/dev/null 2>&1 || { echo "Azure CLI is required but not installed. Aborting." >&2; exit 1; }
}

# Function to configure Azure login
configure_azure() {
  echo "Configuring Azure login..."
  echo "Please choose your login method:"
  echo "1) Interactive browser login (recommended)"
  echo "2) Device code login"
  echo "3) Service principal login"
  read -r login_choice
  
  case $login_choice in
    1)
      az login
      ;;
    2)
      az login --use-device-code
      ;;
    3)
      echo "Please enter your Azure Service Principal ID:"
      read -r sp_id
      echo "Please enter your Azure Service Principal Secret:"
      read -r -s sp_secret
      echo "Please enter your Azure Tenant ID:"
      read -r tenant_id
      az login --service-principal -u "$sp_id" -p "$sp_secret" --tenant "$tenant_id"
      ;;
    *)
      echo "Invalid choice. Using interactive browser login..."
      az login
      ;;
  esac
  
  # Check for subscriptions
  echo "Checking available subscriptions..."
  subscription_count=$(az account list --query "length([].id)" -o tsv)
  
  if [ "$subscription_count" -eq 0 ]; then
    echo "No Azure subscriptions found!"
    echo "You need an Azure subscription to proceed. You have two options:"
    echo "1) Create a free Azure account at https://azure.microsoft.com/free/"
    echo "2) Use an existing Azure account with subscription access"
    echo ""
    echo "Would you like to:"
    echo "1) Open the Azure free account page in your browser"
    echo "2) Try logging in with a different account"
    echo "3) Exit"
    read -r action_choice
    
    case $action_choice in
      1)
        if [[ "$OSTYPE" == "darwin"* ]]; then
          open "https://azure.microsoft.com/free/"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
          xdg-open "https://azure.microsoft.com/free/"
        else
          echo "Please visit https://azure.microsoft.com/free/ in your browser"
        fi
        echo "After creating your account, please run this script again."
        exit 1
        ;;
      2)
        echo "Logging out of current account..."
        az logout
        configure_azure
        return
        ;;
      3)
        echo "Exiting..."
        exit 1
        ;;
      *)
        echo "Invalid choice. Exiting..."
        exit 1
        ;;
    esac
  elif [ "$subscription_count" -gt 1 ]; then
    echo "Multiple subscriptions found. Please select one:"
    az account list --query "[].{name:name, id:id}" -o table
    echo "Please enter the subscription ID:"
    read -r subscription_id
    az account set --subscription "$subscription_id"
  fi
  
  # Verify subscription access
  if ! az account show >/dev/null 2>&1; then
    echo "Error: Unable to access Azure subscription. Please ensure you have proper permissions."
    exit 1
  fi
  
  echo "Successfully configured Azure access!"
  echo "Using subscription: $(az account show --query name -o tsv)"
}

# Get parameters
CLASSROOM_NAME="$1"
LOCATION="$2"
ACTION="$3"
CLASSROOM_DIR="classrooms/$CLASSROOM_NAME"

# Check prerequisites
check_prerequisites

# Configure Azure login if needed
if ! az account show >/dev/null 2>&1; then
  echo "Azure not logged in. Please configure Azure login."
  configure_azure
fi

# Get Azure AD tenant domain
echo "Getting Azure AD tenant domain..."
TENANT_ID=$(az account show --query tenantId -o tsv)
TENANT_DOMAIN=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/domains" --headers "Content-Type=application/json" | jq -r '.value[0].id')

if [ -z "$TENANT_DOMAIN" ]; then
  echo "Could not automatically detect tenant domain. Please enter your Azure AD tenant domain (e.g., yourcompany.onmicrosoft.com):"
  read -r TENANT_DOMAIN
fi

# Set up state infrastructure
echo "Setting up Terraform state infrastructure..."
cd iac/azure/state

# Initialize state infrastructure
echo "Initializing state infrastructure..."
terraform init

# Check if state infrastructure already exists
if ! az storage account show --name tfstateclassroom --resource-group terraform-state-rg >/dev/null 2>&1; then
  echo "Creating new state infrastructure..."
  terraform apply -auto-approve
else
  echo "State infrastructure already exists, skipping creation..."
fi

# Get the storage account details
echo "Getting storage account details..."
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
STORAGE_KEY=$(terraform output -raw storage_account_key)

if [ -z "$STORAGE_ACCOUNT" ] || [ -z "$STORAGE_KEY" ]; then
  echo "Error: Failed to get storage account details"
  exit 1
fi

cd ../../..

# Set up classroom directory for functions only
echo "Setting up classroom directory..."
mkdir -p "$CLASSROOM_DIR/functions"
cp -r functions/azure/* "$CLASSROOM_DIR/functions/"

# Initialize and apply Terraform
cd iac/azure
if [ "$ACTION" = "destroy" ]; then
  terraform init \
    -backend-config="resource_group_name=terraform-state-rg" \
    -backend-config="storage_account_name=$STORAGE_ACCOUNT" \
    -backend-config="container_name=tfstate" \
    -backend-config="key=${CLASSROOM_NAME}.tfstate" \
    -backend-config="access_key=$STORAGE_KEY"
  
  # Check if state is locked
  if terraform force-unlock -force 5903e989-4c45-c5a4-a702-8af3a6987b21; then
    echo "State unlocked successfully"
  fi
  
  terraform destroy -auto-approve \
    -var="tenant_domain=$TENANT_DOMAIN" \
    -var="subscription_id=$(az account show --query id -o tsv)" \
    -var="tenant_id=$TENANT_ID"
else
  terraform init \
    -backend-config="resource_group_name=terraform-state-rg" \
    -backend-config="storage_account_name=$STORAGE_ACCOUNT" \
    -backend-config="container_name=tfstate" \
    -backend-config="key=${CLASSROOM_NAME}.tfstate" \
    -backend-config="access_key=$STORAGE_KEY"
  
  # Check if state is locked
  if terraform force-unlock -force 5903e989-4c45-c5a4-a702-8af3a6987b21; then
    echo "State unlocked successfully"
  fi
  
  terraform apply -auto-approve \
    -var="tenant_domain=$TENANT_DOMAIN" \
    -var="subscription_id=$(az account show --query id -o tsv)" \
    -var="tenant_id=$TENANT_ID"

  # Get the app registration details
  CLIENT_ID=$(terraform output -raw client_id)
  CLIENT_SECRET=$(terraform output -raw client_secret)
  TENANT_ID=$(terraform output -raw tenant_id)
  TENANT_DOMAIN=$(terraform output -raw tenant_domain)

  # Create .env file with the app registration details
  cat > ../../.env << EOF
AZURE_CLIENT_ID=$CLIENT_ID
AZURE_CLIENT_SECRET=$CLIENT_SECRET
AZURE_TENANT_ID=$TENANT_ID
AZURE_DOMAIN=$TENANT_DOMAIN
EOF

  echo "Created .env file with app registration details"
fi

cd ../.. 