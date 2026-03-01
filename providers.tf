provider "azurerm" {
  features {}
  subscription_id = var.target_subscription_id
  use_msi         = true
}
