locals {
  resource_group_name  = "rg-${var.classroom_name}-${var.environment}"
  function_app_name    = "func-${var.classroom_name}-${var.environment}"
  storage_account_name = "st${var.classroom_name}${var.environment}"
  key_vault_name       = "kv-${var.classroom_name}-${var.environment}"
}

# Resource Group
resource "azurerm_resource_group" "classroom" {
  name     = local.resource_group_name
  location = var.location
  tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = "classroom"
  }
}

# Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.classroom.name
  location                 = azurerm_resource_group.classroom.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan
resource "azurerm_service_plan" "function_plan" {
  name                = "asp-${var.classroom_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.classroom.name
  location            = azurerm_resource_group.classroom.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan
}

# Function App
resource "azurerm_linux_function_app" "user_management" {
  name                = local.function_app_name
  resource_group_name = azurerm_resource_group.classroom.name
  location            = azurerm_resource_group.classroom.location

  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan.id

  site_config {
    application_stack {
      python_version = "3.9"
    }
    cors {
      allowed_origins = ["*"]
      allowed_methods = ["GET", "POST"]
      allowed_headers = ["*"]
      expose_headers  = ["*"]
      max_age         = 86400
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = "classroom"
  }
}

# Key Vault for secrets
resource "azurerm_key_vault" "classroom" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.classroom.location
  resource_group_name = azurerm_resource_group.classroom.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_linux_function_app.user_management.identity[0].principal_id

    secret_permissions = [
      "Get", "List", "Set"
    ]
  }

  tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = "classroom"
  }
}

# Role Assignment for Function App
resource "azurerm_role_assignment" "function_role" {
  scope                = azurerm_resource_group.classroom.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.user_management.identity[0].principal_id
}

# Azure AD Application for student access
resource "azuread_application" "student_app" {
  display_name = "classroom-${var.classroom_name}-${var.environment}"
}

# Azure AD Service Principal
resource "azuread_service_principal" "student_sp" {
  client_id = azuread_application.student_app.client_id
}

# Role Assignment for students
resource "azurerm_role_assignment" "student_role" {
  count                = var.student_count
  scope                = azurerm_resource_group.classroom.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.student_sp.object_id
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {} 
