terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-storage"
    storage_account_name = "rp233424323"
    container_name       = "docker-terraform-state"
    # key will be provided during init via -backend-config="key=${subscription}_${resource}.tfstate"
    use_msi              = true
  }
}
