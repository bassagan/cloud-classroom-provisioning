#!/bin/bash

# Exit on error
set -e

# Function to display usage
usage() {
  echo "Usage: $0 [--create] [--destroy] [--list]"
  echo ""
  echo "Options:"
  echo "  --create  Create RBAC roles"
  echo "  --destroy Destroy RBAC roles"
  echo "  --list    List existing RBAC roles"
  exit 1
}

# Function to check if a role exists
role_exists() {
  local role_name=$1
  az role definition list --name "$role_name" --query "[].roleName" -o tsv | grep -q "^$role_name$"
  return $?
}

# Function to create RBAC roles
create_rbac_roles() {
  echo "Creating RBAC roles..."
  
  # Get subscription ID
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "No subscription found. Please set up a subscription first."
    exit 1
  fi

  # Function App User Role
  if ! role_exists "FunctionAppUser"; then
    echo "Creating FunctionAppUser role..."
    az role definition create --role-definition '{
      "Name": "FunctionAppUser",
      "Description": "Allows users to manage their own Function Apps",
      "Actions": [
        "Microsoft.Web/sites/read",
        "Microsoft.Web/sites/functions/read",
        "Microsoft.Web/sites/functions/listKeys/action",
        "Microsoft.Web/sites/functions/keys/write"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "FunctionAppUser role already exists, skipping..."
  fi

  # Storage User Role
  if ! role_exists "StorageUser"; then
    echo "Creating StorageUser role..."
    az role definition create --role-definition '{
      "Name": "StorageUser",
      "Description": "Allows users to manage their own Storage Accounts",
      "Actions": [
        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "StorageUser role already exists, skipping..."
  fi

  # Event Hub User Role
  if ! role_exists "EventHubUser"; then
    echo "Creating EventHubUser role..."
    az role definition create --role-definition '{
      "Name": "EventHubUser",
      "Description": "Allows users to manage their own Event Hubs",
      "Actions": [
        "Microsoft.EventHub/namespaces/read",
        "Microsoft.EventHub/namespaces/eventhubs/read",
        "Microsoft.EventHub/namespaces/eventhubs/write",
        "Microsoft.EventHub/namespaces/eventhubs/consumergroups/read"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "EventHubUser role already exists, skipping..."
  fi

  # Cosmos DB User Role
  if ! role_exists "CosmosDBUser"; then
    echo "Creating CosmosDBUser role..."
    az role definition create --role-definition '{
      "Name": "CosmosDBUser",
      "Description": "Allows users to manage their own Cosmos DB resources",
      "Actions": [
        "Microsoft.DocumentDB/databaseAccounts/read",
        "Microsoft.DocumentDB/databaseAccounts/listKeys/action",
        "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read",
        "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/read"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "CosmosDBUser role already exists, skipping..."
  fi

  # CICD User Role
  if ! role_exists "CICDUser"; then
    echo "Creating CICDUser role..."
    az role definition create --role-definition '{
      "Name": "CICDUser",
      "Description": "Allows users to manage their own CICD resources",
      "Actions": [
        "Microsoft.Web/sites/read",
        "Microsoft.Web/sites/write",
        "Microsoft.Web/sites/delete",
        "Microsoft.Web/sites/start/action",
        "Microsoft.Web/sites/stop/action"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "CICDUser role already exists, skipping..."
  fi

  # Resource Group User Role
  if ! role_exists "ResourceGroupUser"; then
    echo "Creating ResourceGroupUser role..."
    az role definition create --role-definition '{
      "Name": "ResourceGroupUser",
      "Description": "Allows users to manage their own Resource Groups",
      "Actions": [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resourceGroups/write",
        "Microsoft.Resources/subscriptions/resourceGroups/delete",
        "Microsoft.Resources/tags/read",
        "Microsoft.Resources/tags/write"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "ResourceGroupUser role already exists, skipping..."
  fi

  # Service Principal Role
  if ! role_exists "ServicePrincipalRole"; then
    echo "Creating ServicePrincipalRole role..."
    az role definition create --role-definition '{
      "Name": "ServicePrincipalRole",
      "Description": "Allows service principals to manage resources for ETL execution",
      "Actions": [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resourceGroups/write",
        "Microsoft.Resources/subscriptions/resourceGroups/delete",
        "Microsoft.Resources/deployments/read",
        "Microsoft.Resources/deployments/write",
        "Microsoft.Resources/deployments/delete",
        "Microsoft.Resources/deployments/validate/action",
        "Microsoft.Resources/tags/read",
        "Microsoft.Resources/tags/write"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  else
    echo "ServicePrincipalRole role already exists, skipping..."
  fi

  # Student Console User Role
  if ! role_exists "StudentConsoleUser"; then
    echo "Creating StudentConsoleUser role..."
    az role definition create --role-definition '{
      "Name": "StudentConsoleUser",
      "Description": "Allows students to view and manage their assigned resources",
      "Actions": [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
        "Microsoft.Web/sites/read",
        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.KeyVault/vaults/read",
        "Microsoft.OperationalInsights/workspaces/read"
      ],
      "NotActions": [
        "Microsoft.Authorization/*/write",
        "Microsoft.Authorization/*/delete"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  fi

  # Student Service Principal Role
  if ! role_exists "StudentServicePrincipalRole"; then
    echo "Creating StudentServicePrincipalRole role..."
    az role definition create --role-definition '{
      "Name": "StudentServicePrincipalRole",
      "Description": "Allows service principals to deploy and manage student resources",
      "Actions": [
        "Microsoft.Resources/subscriptions/resourceGroups/write",
        "Microsoft.Resources/deployments/*",
        "Microsoft.Storage/storageAccounts/*",
        "Microsoft.Web/serverfarms/*",
        "Microsoft.Web/sites/*",
        "Microsoft.KeyVault/vaults/*"
      ],
      "NotActions": [
        "Microsoft.Authorization/*/write",
        "Microsoft.Authorization/*/delete"
      ],
      "AssignableScopes": ["/subscriptions/'$SUBSCRIPTION_ID'"]
    }'
  fi

  echo "RBAC roles setup completed!"
}

# Function to destroy RBAC roles
destroy_rbac_roles() {
  echo "Destroying RBAC roles..."
  
  # Delete each role
  for role in "FunctionAppUser" "StorageUser" "EventHubUser" "CosmosDBUser" "CICDUser" "ResourceGroupUser" "ServicePrincipalRole" "StudentConsoleUser" "StudentServicePrincipalRole"; do
    echo "Deleting role: $role"
    az role definition delete --name "$role" --yes
  done

  echo "RBAC roles destroyed successfully!"
}

# Function to list RBAC roles
list_rbac_roles() {
  echo "Listing RBAC roles..."
  az role definition list --query "[?contains(roleName, 'User') || contains(roleName, 'ServicePrincipal')].{name:roleName,description:description}" -o table
}

# Parse command line arguments
if [ $# -eq 0 ]; then
  usage
fi

case "$1" in
  --create)
    create_rbac_roles
    ;;
  --destroy)
    destroy_rbac_roles
    ;;
  --list)
    list_rbac_roles
    ;;
  *)
    usage
    ;;
esac 