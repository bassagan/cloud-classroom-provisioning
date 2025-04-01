#!/bin/bash

# Exit on error
set -e

# Function to display usage
usage() {
    echo "Usage: $0 --name <function-app-name> --resource-group <resource-group-name>"
    echo ""
    echo "Options:"
    echo "  --name            Name of the function app (required)"
    echo "  --resource-group  Name of the resource group (required)"
    exit 1
}

# Parse command line arguments
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

# Clean up any existing packages
rm -rf .python_packages

# Create the deployment package
mkdir -p .python_packages/lib/site-packages
cp -r .venv/lib/python*/site-packages/* .python_packages/lib/site-packages/

# Deploy using func core tools
func azure functionapp publish "$FUNCTION_APP_NAME" --build-native-deps --python

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
    "AZURE_DOMAIN=$(az account show --query user.name -o tsv | cut -d'@' -f2)"

# Restart the function app to apply changes
echo "Restarting function app..."
az functionapp restart --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP"

# Deactivate virtual environment
deactivate

echo "Azure AD permissions and roles setup completed!"
echo "Deployment completed successfully!"
