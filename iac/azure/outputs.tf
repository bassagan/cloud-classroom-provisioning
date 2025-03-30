output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.user_management.id
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.user_management.default_hostname}"
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.function_storage.id
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.classroom.id
} 
