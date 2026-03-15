terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Allow both compatible 3.x and 4.x releases so module constraints can resolve
      version = ">= 3.116.0, < 5.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  subscription_id =  "ee485719-86dd-43c5-ab00-4ae86ea6ffd5" #jay
  storage_use_azuread = true
  # subscription_id = var.subscription_id
  # tenant_id       = var.tenant_id
}

data "azurerm_client_config" "current" {}

# variable "subscription_id" {
#   type        = string
#   description = "Azure subscription ID."
# }

# variable "tenant_id" {
#   type        = string
#   description = "Azure tenant ID."
# }