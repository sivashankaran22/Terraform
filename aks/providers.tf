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
      version = "~> 3.0"
    }

  }
}

provider "azuread" {}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  resource_provider_registrations = "none"
  #subscription_id =  "6a0f429d-3dec-45ca-9dba-8f9847b98a7b" #rat
  subscription_id =  "ee485719-86dd-43c5-ab00-4ae86ea6ffd5" #jay
}

data "azurerm_client_config" "current" {}