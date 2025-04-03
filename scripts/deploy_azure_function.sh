#!/bin/bash

# Exit on error
set -e

# Function to display usage
usage() {
    echo "Usage: $0 --name <function-app-name> --resource-group <resource-group-name> [--remote-build]"
    echo ""
    echo "Options:"
    echo "  --name            Name of the function app (required)"
    echo "  --resource-group  Name of the resource group (required)"
    echo "  --remote-build    Use remote build on Azure instead of local build"
    exit 1
}

# Parse command line arguments
REMOTE_BUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            FUNCTION_APP_NAME="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --remote-build)
            REMOTE_BUILD=true
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
if [ -z "$FUNCTION_APP_NAME" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "Error: Function app name and resource group are required"
    usage
fi

# Navigate to the Azure function directory
cd "$(dirname "$0")/../functions/azure"

echo "Setting up Python virtual environment..."
python -m venv .venv
source .venv/bin/activate

echo "Installing dependencies..."
python -m pip install --upgrade pip
pip install --upgrade setuptools wheel
pip install -r requirements.txt

echo "Building and deploying Azure function..."

if [ "$REMOTE_BUILD" = true ]; then
    echo "Using remote build on Azure..."
    func azure functionapp publish "$FUNCTION_APP_NAME" --build remote --python
else
    echo "Using local build..."
    # Clean up any existing packages
    rm -rf .python_packages

    # Create the deployment package
    mkdir -p .python_packages/lib/site-packages
    cp -r .venv/lib/python*/site-packages/* .python_packages/lib/site-packages/

    # Deploy using func core tools
    func azure functionapp publish "$FUNCTION_APP_NAME" --build-native-deps --python
fi

echo "Setting up Azure AD permissions..."

# Get the function app's managed identity object ID
FUNCTION_APP_ID=$(az functionapp identity show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)

if [ -z "$FUNCTION_APP_ID" ]; then
    echo "Enabling system-assigned managed identity..."
    az functionapp identity assign \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP"
    
    FUNCTION_APP_ID=$(az functionapp identity show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
fi

echo "Adding Azure AD permissions..."
# Get the Microsoft Graph API service principal ID
GRAPH_API_ID=$(az ad sp show --id 00000003-0000-0000-c000-000000000000 --query id -o tsv)

# Get the app registration client ID from function app settings
APP_CLIENT_ID=$(az functionapp config appsettings list \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='AZURE_CLIENT_ID'].value" -o tsv)

# Get the app registration object ID
APP_OBJECT_ID=$(az ad app show --id "$APP_CLIENT_ID" --query id -o tsv)

echo "Assigning User.ReadWrite.All application permission to app registration..."
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body "{
        \"requiredResourceAccess\": [
            {
                \"resourceAppId\": \"00000003-0000-0000-c000-000000000000\",
                \"resourceAccess\": [
                    {
                        \"id\": \"741f803b-c850-494e-b5df-cde7c675a1ca\",
                        \"type\": \"Role\"
                    }
                ]
            }
        ]
    }"

# Grant admin consent for the application permission
echo "Granting admin consent for application permissions..."
az ad app permission admin-consent --id "$APP_CLIENT_ID"

# Add RBAC roles if not already assigned
echo "Assigning RBAC roles..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Add role assignments for the app registration
echo "Adding required role assignments for app registration..."
# Get the service principal ID using the client ID
APP_PRINCIPAL_ID=$(az ad sp list --filter "appId eq '$APP_CLIENT_ID'" --query '[0].id' -o tsv)

if [ -z "$APP_PRINCIPAL_ID" ]; then
    echo "Error: Could not find service principal ID for client ID: $APP_CLIENT_ID"
    exit 1
fi

echo "Found service principal ID: $APP_PRINCIPAL_ID"

# Assign Role Based Access Control Administrator
echo "Assigning RBAC Administrator role..."
az role assignment create \
    --assignee "$APP_PRINCIPAL_ID" \
    --role "Role Based Access Control Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --only-show-errors || true

# Assign Contributor role
echo "Assigning Contributor role..."
az role assignment create \
    --assignee "$APP_PRINCIPAL_ID" \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --only-show-errors || true

# Assign Contributor role to the function app's managed identity
echo "Assigning Contributor role to function app..."
az role assignment create \
    --assignee "$FUNCTION_APP_ID" \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    --only-show-errors || true

# Assign Storage Blob Data Owner role to the function app's managed identity
echo "Assigning Storage Blob Data Owner role to function app..."
STORAGE_ACCOUNT_NAME=$(az functionapp config appsettings list \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='AzureWebJobsStorage'].value" -o tsv | sed -n 's/.*AccountName=\([^;]*\).*/\1/p')

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "Warning: Could not extract storage account name from connection string"
else
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)

    az role assignment create \
        --assignee "$FUNCTION_APP_ID" \
        --role "Storage Blob Data Owner" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --only-show-errors || true
fi

# Set required app settings
echo "Setting up application settings..."
az functionapp config appsettings set \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
    "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID" \
    "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)" \
    "AZURE_DOMAIN=paulabassaganasgmail.onmicrosoft.com"

# Restart the function app to apply changes
echo "Restarting function app..."
az functionapp restart --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP"

# Deactivate virtual environment
deactivate

echo "Azure AD permissions and roles setup completed!"
echo "Deployment completed successfully!"

# Function to handle Azure login
azure_login() {
  echo "Logging into Azure..."
  
  # Check if already logged in
  if ! az account show &>/dev/null; then
    # Get number of tenants
    TENANT_COUNT=$(az tenant list --query 'length([])' -o tsv 2>/dev/null || echo "0")
    
    if [ "$TENANT_COUNT" -eq 1 ]; then
      # If only one tenant exists, use it directly
      TENANT_ID=$(az tenant list --query '[0].tenantId' -o tsv)
      az login --tenant "$TENANT_ID" --only-show-errors
    else
      # Regular login if multiple tenants or count couldn't be determined
      az login
    fi
  fi
  
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
