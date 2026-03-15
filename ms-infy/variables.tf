
variable "subscription_id" { type = string }
variable "tenant_id"       { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

# Resource Group: create OR existing
variable "resource_group" {
  type = object({
    create   = bool
    name     = string
    location = optional(string) # required when create=true
    tags     = optional(map(string), {})
  })
}

# Log Analytics: create OR existing (AVM for create, data source for existing)
variable "log_analytics" {
  type = object({
    create            = bool
    name              = string
    location          = optional(string)
    sku               = optional(string, "PerGB2018")
    retention_in_days = optional(number, 30)
    tags              = optional(map(string), {})
  })
}

# App Insights: create OR existing (native resource)
variable "application_insights" {
  type = object({
    create                = bool
    name                  = string
    location              = optional(string)
    application_type      = optional(string, "web")
    retention_in_days     = optional(number, 90)
    sampling_percentage   = optional(number, 100)
    disable_ip_masking    = optional(bool, false)
    internet_ingestion_on = optional(bool, true)
    internet_query_on     = optional(bool, true)
    tags                  = optional(map(string), {})
  })
}

# VNets: create OR existing (AVM for create)
# Keys: vnet1, vnet2...
# Real Azure names are inside name=""
variable "virtual_networks" {
  type = map(object({
    create              = bool
    name                = string
    resource_group_name = optional(string)
    location            = optional(string)
    address_space       = optional(list(string))
    dns_servers         = optional(list(string), [])
    enable_ddos_protection = optional(bool, false)
    tags                = optional(map(string), {})

    subnets = map(object({
      name              = string
      address_prefixes  = optional(list(string))
      service_endpoints = optional(list(string))
      delegation = optional(object({
        name = string
        service_delegation = object({
          name    = string
          actions = list(string)
        })
      }))
    }))
  }))
}

# NSGs: create OR existing (AVM for create)
variable "nsgs" {
  type = map(object({
    create              = bool
    name                = string
    resource_group_name = optional(string)
    location            = optional(string)
    tags                = optional(map(string), {})
    security_rules = optional(list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_address_prefix      = string
      destination_address_prefix = string
      source_port_range          = string
      destination_port_range     = string
    })), [])
  }))
  default = {}
}

variable "nsg_associations" {
  type = map(object({
    vnet_key   = string
    subnet_key = string
    nsg_key    = string
  }))
  default = {}
}

# Private DNS Zones (AVM)
variable "private_dns_zones" {
  type = map(object({
    name      = string
    vnet_keys = list(string)
    tags      = optional(map(string), {})
  }))
  default = {}
}

# User Assigned Identities (native)
variable "user_assigned_identities" {
  type = map(object({
    name     = string
    location = optional(string)
    tags     = optional(map(string), {})
  }))
  default = {}
}

# Storage Account (Portal-tabs model)
variable "storage_accounts" {
  type = map(object({
    name     = string
    location = optional(string)
    account_kind             = optional(string, "StorageV2")
    account_tier             = optional(string, "Standard")
    account_replication_type = string
    access_tier              = optional(string, "Hot")

    advanced = optional(object({
      min_tls_version                   = optional(string, "TLS1_2")
      enable_https_traffic_only         = optional(bool, true)
      shared_access_key_enabled         = optional(bool, false)
      allow_blob_public_access          = optional(bool, false)
      allow_nested_items_to_be_public   = optional(bool, false)
      infrastructure_encryption_enabled = optional(bool, true)

      is_hns_enabled     = optional(bool, false)
      nfsv3_enabled      = optional(bool, false)
      sftp_enabled       = optional(bool, false)
      local_user_enabled = optional(bool, false)
    }), {})

    networking = optional(object({
      public_network_access_enabled = optional(bool, true)
      default_action                = optional(string, "Deny")
      bypass                        = optional(list(string), ["AzureServices"])
      ip_rules                      = optional(list(string), [])
      subnet_ids                    = optional(list(string), [])
    }), {})

    data_protection = optional(object({
      versioning_enabled    = optional(bool, true)
      change_feed_enabled   = optional(bool, false)

      blob_soft_delete = optional(object({
        enabled = optional(bool, true)
        days    = optional(number, 7)
      }), {})

      container_soft_delete = optional(object({
        enabled = optional(bool, true)
        days    = optional(number, 7)
      }), {})
    }), {})

    tags = optional(map(string), {})
  }))
  default = {}
}

# Key Vault (Portal-tabs model)
variable "key_vaults" {
  type = map(object({
    name     = string
    location = optional(string)
    sku_name = optional(string, "standard")

    soft_delete_retention_days = optional(number, 7)
    purge_protection_enabled   = optional(bool, true)

    enable_rbac_authorization  = optional(bool, true)

    networking = optional(object({
      public_network_access_enabled = optional(bool, false)
      default_action                = optional(string, "Deny")
      bypass                        = optional(string, "AzureServices")
      ip_rules                      = optional(list(string), [])
      subnet_ids                    = optional(list(string), [])
    }), {})

    tags = optional(map(string), {})
  }))
  default = {}
}

# Private Endpoints (AVM) - ONLY configured here
variable "private_endpoints" {
  type = map(object({
    name       = string
    vnet_key   = string
    subnet_key = string

    target_kind = optional(string) # storage | keyvault | loganalytics | appinsights
    target_key  = optional(string)
    target_resource_id = optional(string)

    subresource_names     = list(string)
    private_dns_zone_key  = string
    tags                  = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, pe in var.private_endpoints :
      (
        (try(pe.target_resource_id, null) != null) ||
        (try(pe.target_kind, null) != null && try(pe.target_key, null) != null)
      )
    ])
    error_message = "Each private_endpoints entry must include either target_resource_id OR (target_kind AND target_key)."
  }
}

# Diagnostic settings (optional)
variable "diagnostic_settings" {
  type = map(object({
    name                       = string
    target_resource_id         = string
    log_analytics_workspace_id = string

    logs = optional(list(object({
      category       = optional(string)
      category_group = optional(string)
      enabled        = optional(bool, true)
    })), [])

    metrics = optional(list(object({
      category = string
      enabled  = optional(bool, true)
    })), [])
  }))
  default = {}
}