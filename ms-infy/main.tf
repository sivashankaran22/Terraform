
########################################
# Resource Group: create OR existing (native)
# (No verified AVM Terraform module name found in search results.) [2](https://learn.microsoft.com/en-us/community/content/azure-verified-modules)
########################################
resource "azurerm_resource_group" "rg" {
  count    = var.resource_group.create ? 1 : 0
  name     = var.resource_group.name
  location = var.resource_group.location
  tags     = merge(var.tags, try(var.resource_group.tags, {}))
}

data "azurerm_resource_group" "rg" {
  count = var.resource_group.create ? 0 : 1
  name  = var.resource_group.name
}

locals {
  rg_name     = var.resource_group.create ? azurerm_resource_group.rg[0].name     : data.azurerm_resource_group.rg[0].name
  rg_location = var.resource_group.create ? azurerm_resource_group.rg[0].location : data.azurerm_resource_group.rg[0].location
}

########################################
# Log Analytics: create OR existing
# Create uses AVM module (confirmed by AVM TF labs). [1](https://learn.microsoft.com/en-us/samples/azure-samples/avm-terraform-labs/avm-terraform-labs/)
########################################
module "law_created" {
  source = "Azure/avm-res-operationalinsights-workspace/azurerm"
  count  = var.log_analytics.create ? 1 : 0

  name                = var.log_analytics.name
  resource_group_name = local.rg_name
  location            = coalesce(try(var.log_analytics.location, null), local.rg_location)
  sku                 = var.log_analytics.sku
  retention_in_days   = var.log_analytics.retention_in_days
  tags                = merge(var.tags, try(var.log_analytics.tags, {}))
}

data "azurerm_log_analytics_workspace" "law_existing" {
  count               = var.log_analytics.create ? 0 : 1
  name                = var.log_analytics.name
  resource_group_name = local.rg_name
}

locals {
  law_id = var.log_analytics.create
    ? try(module.law_created[0].resource_id, module.law_created[0].id)
    : data.azurerm_log_analytics_workspace.law_existing[0].id
}

########################################
# App Insights: create OR existing (native)
# (No verified AVM Terraform module source found in results I can cite.) [2](https://learn.microsoft.com/en-us/community/content/azure-verified-modules)
########################################
resource "azurerm_application_insights" "appi" {
  count               = var.application_insights.create ? 1 : 0
  name                = var.application_insights.name
  location            = coalesce(try(var.application_insights.location, null), local.rg_location)
  resource_group_name = local.rg_name
  application_type    = var.application_insights.application_type
  workspace_id        = local.law_id

  retention_in_days   = var.application_insights.retention_in_days
  sampling_percentage = var.application_insights.sampling_percentage
  disable_ip_masking  = var.application_insights.disable_ip_masking
  internet_ingestion_enabled = var.application_insights.internet_ingestion_on
  internet_query_enabled     = var.application_insights.internet_query_on

  tags = merge(var.tags, try(var.application_insights.tags, {}))
}

data "azurerm_application_insights" "appi_existing" {
  count               = var.application_insights.create ? 0 : 1
  name                = var.application_insights.name
  resource_group_name = local.rg_name
}

locals {
  appi_id = var.application_insights.create ? azurerm_application_insights.appi[0].id : data.azurerm_application_insights.appi_existing[0].id
}

########################################
# VNets: create OR existing (AVM create)
########################################
locals {
  vnets_to_create = { for k, v in var.virtual_networks : k => v if v.create }
  vnets_existing  = { for k, v in var.virtual_networks : k => v if !v.create }
}

module "vnet_created" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  for_each = local.vnets_to_create

  name                = each.value.name
  location            = each.value.location
  resource_group_name = coalesce(try(each.value.resource_group_name, null), local.rg_name)
  address_space       = each.value.address_space
  dns_servers         = try(each.value.dns_servers, [])

  subnets = {
    for sk, s in each.value.subnets : s.name => {
      address_prefixes  = s.address_prefixes
      service_endpoints = try(s.service_endpoints, null)
      delegation        = try(s.delegation, null)
    }
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

data "azurerm_virtual_network" "vnet_existing" {
  for_each            = local.vnets_existing
  name                = each.value.name
  resource_group_name = coalesce(try(each.value.resource_group_name, null), local.rg_name)
}

locals {
  existing_subnets_flat = merge([
    for vk, v in local.vnets_existing : {
      for sk, s in v.subnets :
      "${vk}.${sk}" => {
        subnet_name         = s.name
        vnet_name           = v.name
        resource_group_name = coalesce(try(v.resource_group_name, null), local.rg_name)
      }
    }
  ]...)
}

data "azurerm_subnet" "existing_subnet" {
  for_each             = local.existing_subnets_flat
  name                 = each.value.subnet_name
  virtual_network_name = each.value.vnet_name
  resource_group_name  = each.value.resource_group_name
}

locals {
  vnet_resource_id_by_key = merge(
    { for k, v in module.vnet_created : k => v.resource_id },
    { for k, v in data.azurerm_virtual_network.vnet_existing : k => v.id }
  )

  subnet_id_by_key = merge(
    merge([
      for vk, v in local.vnets_to_create : {
        for sk, s in v.subnets :
        "${vk}.${sk}" => module.vnet_created[vk].subnet_ids[s.name]
      }
    ]...),
    { for k, s in data.azurerm_subnet.existing_subnet : k => s.id }
  )
}

########################################
# NSGs: create OR existing (AVM create)
########################################
locals {
  nsgs_to_create = { for k, v in var.nsgs : k => v if v.create }
  nsgs_existing  = { for k, v in var.nsgs : k => v if !v.create }
}

module "nsg_created" {
  source   = "Azure/avm-res-network-networksecuritygroup/azurerm"
  for_each = local.nsgs_to_create

  name                = each.value.name
  location            = coalesce(try(each.value.location, null), local.rg_location)
  resource_group_name = coalesce(try(each.value.resource_group_name, null), local.rg_name)
  security_rules      = each.value.security_rules
  tags                = merge(var.tags, try(each.value.tags, {}))
}

data "azurerm_network_security_group" "nsg_existing" {
  for_each            = local.nsgs_existing
  name                = each.value.name
  resource_group_name = coalesce(try(each.value.resource_group_name, null), local.rg_name)
}

locals {
  nsg_id_by_key = merge(
    { for k, v in module.nsg_created : k => v.nsg_id },
    { for k, v in data.azurerm_network_security_group.nsg_existing : k => v.id }
  )
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  for_each = var.nsg_associations
  subnet_id                 = local.subnet_id_by_key["${each.value.vnet_key}.${each.value.subnet_key}"]
  network_security_group_id = local.nsg_id_by_key[each.value.nsg_key]
}

########################################
# Private DNS Zones (AVM)
########################################
module "private_dns_zone" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  for_each = var.private_dns_zones

  name                = each.value.name
  resource_group_name = local.rg_name

  virtual_network_links = {
    for vnet_key in each.value.vnet_keys : "${each.key}-${vnet_key}" => {
      virtual_network_id = local.vnet_resource_id_by_key[vnet_key]
    }
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

########################################
# Identities (native)
########################################
resource "azurerm_user_assigned_identity" "uami" {
  for_each            = var.user_assigned_identities
  name                = each.value.name
  location            = coalesce(try(each.value.location, null), local.rg_location)
  resource_group_name = local.rg_name
  tags                = merge(var.tags, try(each.value.tags, {}))
}

########################################
# Storage (native - portal tabs)
########################################
resource "azurerm_storage_account" "sa" {
  for_each            = var.storage_accounts
  name                = each.value.name
  location            = coalesce(try(each.value.location, null), local.rg_location)
  resource_group_name = local.rg_name

  account_kind             = try(each.value.account_kind, "StorageV2")
  account_tier             = try(each.value.account_tier, "Standard")
  account_replication_type = each.value.account_replication_type
  access_tier              = try(each.value.access_tier, null)

  min_tls_version           = try(each.value.advanced.min_tls_version, "TLS1_2")
  enable_https_traffic_only = try(each.value.advanced.enable_https_traffic_only, true)
  shared_access_key_enabled = try(each.value.advanced.shared_access_key_enabled, false)
  allow_blob_public_access  = try(each.value.advanced.allow_blob_public_access, false)
  allow_nested_items_to_be_public = try(each.value.advanced.allow_nested_items_to_be_public, false)
  infrastructure_encryption_enabled = try(each.value.advanced.infrastructure_encryption_enabled, true)

  is_hns_enabled     = try(each.value.advanced.is_hns_enabled, false)
  nfsv3_enabled      = try(each.value.advanced.nfsv3_enabled, false)
  sftp_enabled       = try(each.value.advanced.sftp_enabled, false)
  local_user_enabled = try(each.value.advanced.local_user_enabled, false)

  public_network_access_enabled = try(each.value.networking.public_network_access_enabled, true)

  dynamic "network_rules" {
    for_each = (try(each.value.networking, null) == null) ? [] : [1]
    content {
      default_action             = try(each.value.networking.default_action, "Deny")
      bypass                     = try(each.value.networking.bypass, ["AzureServices"])
      ip_rules                   = try(each.value.networking.ip_rules, [])
      virtual_network_subnet_ids = try(each.value.networking.subnet_ids, [])
    }
  }

  blob_properties {
    versioning_enabled  = try(each.value.data_protection.versioning_enabled, true)
    change_feed_enabled = try(each.value.data_protection.change_feed_enabled, false)

    dynamic "delete_retention_policy" {
      for_each = try(each.value.data_protection.blob_soft_delete.enabled, false) ? [1] : []
      content { days = try(each.value.data_protection.blob_soft_delete.days, 7) }
    }

    dynamic "container_delete_retention_policy" {
      for_each = try(each.value.data_protection.container_soft_delete.enabled, false) ? [1] : []
      content { days = try(each.value.data_protection.container_soft_delete.days, 7) }
    }
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

########################################
# Key Vault (native - portal tabs)
########################################
resource "azurerm_key_vault" "kv" {
  for_each            = var.key_vaults
  name                = each.value.name
  location            = coalesce(try(each.value.location, null), local.rg_location)
  resource_group_name = local.rg_name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = try(each.value.sku_name, "standard")

  soft_delete_retention_days = try(each.value.soft_delete_retention_days, 7)
  purge_protection_enabled   = try(each.value.purge_protection_enabled, true)
  enable_rbac_authorization  = try(each.value.enable_rbac_authorization, true)

  public_network_access_enabled = try(each.value.networking.public_network_access_enabled, false)

  dynamic "network_acls" {
    for_each = (try(each.value.networking, null) == null) ? [] : [1]
    content {
      default_action             = try(each.value.networking.default_action, "Deny")
      bypass                     = try(each.value.networking.bypass, "AzureServices")
      ip_rules                   = try(each.value.networking.ip_rules, [])
      virtual_network_subnet_ids = try(each.value.networking.subnet_ids, [])
    }
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

########################################
# ONE Generic Private Endpoint module (AVM) driven by private_endpoints
########################################
locals {
  pe_target_id = {
    for k, pe in var.private_endpoints :
    k => (
      try(pe.target_resource_id, null) != null ? pe.target_resource_id :
      pe.target_kind == "storage"     ? azurerm_storage_account.sa[pe.target_key].id :
      pe.target_kind == "keyvault"    ? azurerm_key_vault.kv[pe.target_key].id :
      pe.target_kind == "loganalytics"? local.law_id :
      pe.target_kind == "appinsights" ? local.appi_id :
      null
    )
  }

  invalid_pe = [ for k, pe in var.private_endpoints : k if local.pe_target_id[k] == null ]
}

resource "null_resource" "validate_pe" {
  count = length(local.invalid_pe) > 0 ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(local.invalid_pe) == 0
      error_message = "Invalid private_endpoints targets for: ${join(", ", local.invalid_pe)}."
    }
  }
}

module "private_endpoint" {
  source   = "Azure/avm-res-network-privateendpoint/azurerm"
  for_each = var.private_endpoints

  name                = each.value.name
  location            = local.rg_location
  resource_group_name = local.rg_name

  subnet_id = local.subnet_id_by_key["${each.value.vnet_key}.${each.value.subnet_key}"]

  private_service_connection = {
    name                           = "psc-${each.value.name}"
    private_connection_resource_id = local.pe_target_id[each.key]
    subresource_names              = each.value.subresource_names
    is_manual_connection           = false
  }

  private_dns_zone_group = {
    name                 = "pdzg-${each.value.name}"
    private_dns_zone_ids = [module.private_dns_zone[each.value.private_dns_zone_key].private_dns_zone_id]
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

########################################
# Diagnostic settings (optional)
########################################
resource "azurerm_monitor_diagnostic_setting" "diag" {
  for_each                   = var.diagnostic_settings
  name                       = each.value.name
  target_resource_id         = each.value.target_resource_id
  log_analytics_workspace_id = each.value.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = each.value.logs
    content {
      category       = try(enabled_log.value.category, null)
      category_group = try(enabled_log.value.category_group, null)
      enabled        = try(enabled_log.value.enabled, true)
    }
  }

  dynamic "metric" {
    for_each = each.value.metrics
    content {
      category = metric.value.category
      enabled  = try(metric.value.enabled, true)
    }
  }

  lifecycle { ignore_changes = [log_analytics_destination_type] }
}
