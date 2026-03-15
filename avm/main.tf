

data "azurerm_resource_group" "rg" {
  name = "rg-infy-terraform"  #"rg-infosys-is"  #"madan-test"
}
#--------------------------------------------------------------------
# Virtual Network and Subnet
#--------------------------------------------------------------------
module "avm_res_network_virtualnetwork" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  version  = "0.16.0"
  for_each = { for k, v in local.vnets_to_create : k => v if var.enable_virtual_networks }
  #for_each = local.vnets_to_create

  name      = each.value.name
  location  = each.value.location
  parent_id = data.azurerm_resource_group.rg.id

  address_space = each.value.address_space

  enable_telemetry = false
  dns_servers      = (try(each.value.dns_servers, null) == null ? null : { dns_servers = each.value.dns_servers })
  # --- Transform your subnet_configs -> module.subnets expected shape ---
  subnets = {
    for sk, s in each.value.subnet_configs : sk => {
      name             = s.name
      address_prefixes = s.address_prefix
      service_endpoints_with_location = [
        for svc in try(s.service_endpoints, []) : {
          service = svc
          # locations = [each.value.location] # use only if you want location restriction
        }
      ]

      network_security_group = try((try(s.nsg_key, null) == null ? null : { id = local.nsg_ids[s.nsg_key] }), null)

      # If delegation exists, create list; else empty
      delegations = try([
        {
          name = s.delegation.name
          service_delegation = {
            name    = s.delegation.service_delegation.name
            actions = s.delegation.service_delegation.actions
          }
        }
      ], [])
    }
  }
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
}

data "azurerm_virtual_network" "existing" {
  for_each            = { for k, v in local.vnets_existing : k => v if var.enable_virtual_networks }
  name                = each.value.name
  resource_group_name = coalesce(try(each.value.resource_group_name, null), data.azurerm_resource_group.rg.name)
}
data "azurerm_subnet" "existing" {
  for_each             = { for k, v in local.existing_subnets_flat : k => v if var.enable_virtual_networks }
  name                 = each.value.subnet_name
  resource_group_name  = each.value.rg_name
  virtual_network_name = data.azurerm_virtual_network.existing[each.value.vnet_key].name
}

#--------------------------------------------------------------------
# Network Security Group
#--------------------------------------------------------------------
module "nsg" {
  source              = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version             = "0.5.0"
  for_each            = { for k, v in local.nsg_create : k => v if var.enable_nsg }
  name                = each.value.nsg_name
  resource_group_name = coalesce(try(each.value.rg_name, null), data.azurerm_resource_group.rg.name)
  location            = coalesce(try(each.value.location, null), data.azurerm_resource_group.rg.location)
  security_rules      = try(local.nsg_security_rules[each.key], {})
  enable_telemetry    = false
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
}
# 4) Lookup only for create_nsg=false
data "azurerm_network_security_group" "existing" {
  for_each            = { for k, v in local.nsg_lookup : k => v if var.enable_nsg }
  name                = each.value.nsg_name
  resource_group_name = coalesce(try(each.value.rg_name, null), data.azurerm_resource_group.rg.name)
}
output "nsg_ids" {
  value = local.nsg_ids
}

#--------------------------------------------------------------------
#Key Vault
#--------------------------------------------------------------------
module "keyvault" {
  source   = "Azure/avm-res-keyvault-vault/azurerm"
  version  = "0.10.2"
  for_each = { for k, v in local.keyvault_configs : k => v if var.enable_kv }

  name                            = each.value.name
  location                        = each.value.location
  resource_group_name             = each.value.resource_group_name
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = each.value.sku_name
  soft_delete_retention_days      = each.value.soft_delete_retention_days
  purge_protection_enabled        = each.value.purge_protection_enabled
  legacy_access_policies_enabled  = each.value.legacy_access_policies_enabled
  enabled_for_deployment          = each.value.enabled_for_deployment
  enabled_for_disk_encryption     = each.value.enabled_for_disk_encryption
  enabled_for_template_deployment = each.value.enabled_for_template_deployment
  public_network_access_enabled   = each.value.public_network_access_enabled
  enable_telemetry                = false
  # ---- network ACLs: convert vnet/subnet refs -> subnet IDs ----
  network_acls = merge(
    try(each.value.network_acls, {}),
    {
      virtual_network_subnet_ids = [
        for r in try(each.value.network_acls.virtual_network_subnet_refs, []) :
        local.subnet_ids["${r.vnet_key}.${r.subnet_key}"]
      ]
    }
  )
  # ---- private endpoints: derive subnet_resource_id from vnet1.snet1 etc ----
  private_endpoints = {
    for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
      name                          = try(pe.name, null)
      subnet_resource_id            = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
      private_dns_zone_resource_ids = try(pe.private_dns_zone_resource_ids, [])
      tags                          = try(pe.tags, null)
    }
  }

  diagnostic_settings = (
    contains(keys(each.value), "diagnostic_settings") && length(each.value.diagnostic_settings) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
      }
    }
    : null
  )
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.law]

}

#--------------------------------------------------------------------
# Log Analytics Workspace
#--------------------------------------------------------------------
module "law" {
  source                                    = "Azure/avm-res-operationalinsights-workspace/azurerm"
  count                                     = var.enable_log_analytics_workspace ? 1 : 0
  version                                   = "0.4.2"
  name                                      = "IL-log-cind-test"
  location                                  = data.azurerm_resource_group.rg.location
  resource_group_name                       = data.azurerm_resource_group.rg.name
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = 30
  enable_telemetry                          = false
  tags = {
    created_by = "terraform"
  }
}

#--------------------------------------------------------------------
# #Storage Account
#--------------------------------------------------------------------
module "avm-res-storage-storageaccount" {
  source                            = "Azure/avm-res-storage-storageaccount/azurerm"
  for_each                          = { for k, v in local.storage_account_configs : k => v if var.enable_storage_account }
  version                           = "0.6.7"
  account_replication_type          = each.value.account_replication_type
  account_tier                      = each.value.account_tier
  location                          = each.value.location
  name                              = each.value.name
  resource_group_name               = each.value.resource_group_name
  access_tier                       = each.value.access_tier
  account_kind                      = each.value.account_kind
  allow_nested_items_to_be_public   = each.value.allow_nested_items_to_be_public
  default_to_oauth_authentication   = each.value.default_to_oauth_authentication
  https_traffic_only_enabled        = each.value.https_traffic_only_enabled
  infrastructure_encryption_enabled = each.value.infrastructure_encryption_enabled
  enable_telemetry                  = each.value.enable_telemetry
  local_user_enabled                = each.value.local_user_enabled
  min_tls_version                   = each.value.min_tls_version
  public_network_access_enabled     = each.value.public_network_access_enabled
  sftp_enabled                      = each.value.sftp_enabled
  shared_access_key_enabled         = each.value.shared_access_key_enabled
  network_rules = (
    length(try(each.value.network_rules_subnet_refs, [])) == 0
    ? null
    : {
      # optional - you can add default_action/bypass here if your module expects it
      virtual_network_subnet_ids = [
        for r in each.value.network_rules_subnet_refs :
        local.subnet_ids["${r.vnet_key}.${r.subnet_key}"]
      ]
    }
  )

  private_endpoints = {
    for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
      name                          = try(pe.name, null)
      subnet_resource_id            = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
      subresource_name              = pe.subresource_name
      private_dns_zone_resource_ids = try(pe.private_dns_zone_resource_ids, [])
      tags                          = try(pe.tags, null)
    }
  }
  blob_properties = (
    try(each.value.blob_properties, null) == null
    ? null
    : {
      change_feed_enabled           = try(each.value.blob_properties.change_feed_enabled, null)
      change_feed_retention_in_days = try(each.value.blob_properties.change_feed_retention_in_days, null)
      default_service_version       = try(each.value.blob_properties.default_service_version, null)
      last_access_time_enabled      = try(each.value.blob_properties.last_access_time_enabled, null)
      versioning_enabled            = try(each.value.blob_properties.versioning_enabled, null)

      delete_retention_policy = (try(each.value.blob_properties.delete_retention_policy, null) == null ? null : {
        days = each.value.blob_properties.delete_retention_policy.days
        permanent_delete_enabled = each.value.blob_properties.delete_retention_policy.permanent_delete_enabled
      })
      container_delete_retention_policy = (try(each.value.blob_properties.container_delete_retention_policy, null) == null ? null : {
        days = each.value.blob_properties.container_delete_retention_policy.days
        #enabled = each.value.blob_properties.container_delete_retention_policy.enabled
      })
    }
  )

  immutability_policy = (
    try(each.value.immutability_policy, null) == null
    ? null
    : {
      state         = each.value.immutability_policy.state
      period_since_creation_in_days = each.value.immutability_policy.period_since_creation_in_days
      allow_protected_append_writes = each.value.immutability_policy.allow_protected_append_writes
    }
  )

  diagnostic_settings_blob = (
    contains(keys(each.value), "diagnostic_settings_blob") && length(each.value.diagnostic_settings_blob) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings_blob :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
        metric_categories     = try(toset(diag.metric_categories), null)
      }
    }
    : null
  )
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.law]
}

#--------------------------------------------------------------------
# Function App
#--------------------------------------------------------------------
module "avm-res-web-site" {
  source                                         = "Azure/avm-res-web-site/azurerm"
  for_each                                       = { for k, v in local.function_app_configs : k => v if var.enable_function_app }
  version                                        = "0.19.1"
  name                                           = each.value.name
  location                                       = each.value.location
  resource_group_name                            = each.value.resource_group_name
  kind                                           = each.value.kind
  os_type                                        = each.value.os_type
  https_only                                     = each.value.https_only
  service_plan_resource_id                       = each.value.service_plan_resource_id #module.avm-res-web-serverfarm.resource_id
  storage_account_name                           = each.value.storage_account_name     #module.avm-res-storage-storageaccount["st1"].name
  public_network_access_enabled                  = each.value.public_network_access_enabled
  enable_application_insights                    = each.value.enable_application_insights
  virtual_network_subnet_id                      = each.value.virtual_network_subnet_id
  ftp_publish_basic_authentication_enabled       = each.value.ftp_publish_basic_authentication_enabled
  webdeploy_publish_basic_authentication_enabled = each.value.webdeploy_publish_basic_authentication_enabled
  enable_telemetry                               = each.value.enable_telemetry
  app_settings = (
    try(each.value.app_settings, null) == null
    ? null
    : { for k, v in each.value.app_settings : k => tostring(v) }
  )
  site_config = {
    always_on         = try(each.value.site_config.always_on, null)
    application_stack = try(each.value.site_config.application_stack, null)

    application_insights_connection_string = (
      each.value.enable_application_insights == true
      ? module.avm-res-insights-component[each.value.site_config.app_insights_key].connection_string
      : null
    )

    application_insights_key = (
      each.value.enable_application_insights == true
      ? module.avm-res-insights-component[each.value.site_config.app_insights_key].instrumentation_key
      : null
    )
  }

  managed_identities = {
    user_assigned_resource_ids = toset([
      for id_key in try(each.value.user_assigned_identity_keys, []) :
      module.avm-res-managedidentity-userassignedidentity[id_key].resource_id
    ])
  }

  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.avm-res-storage-storageaccount, module.avm-res-web-serverfarm]
}

#--------------------------------------------------------------------
# App Service Plan
#--------------------------------------------------------------------
module "avm-res-web-serverfarm" {
  source              = "Azure/avm-res-web-serverfarm/azurerm"
  version             = "1.0.0"
  for_each            = { for k, v in local.app_service_plan : k => v if var.enable_app_service_plan }
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  sku_name            = each.value.sku_name
  os_type             = each.value.os_type
  enable_telemetry    = false
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
}

#--------------------------------------------------------------------
# User Assigned Identity
#--------------------------------------------------------------------
module "avm-res-managedidentity-userassignedidentity" {
  source              = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version             = "0.3.4"
  for_each            = { for k, v in local.user_assigned_identities : k => v if var.enable_user_assigned_identities }
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  enable_telemetry    = false
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
}
#--------------------------------------------------------------------
# Application Insights
#--------------------------------------------------------------------
module "avm-res-insights-component" {
  source              = "Azure/avm-res-insights-component/azurerm"
  version             = "0.2.0"
  for_each            = { for k, v in local.app_insights_configs : k => v if var.enable_application_insights }
  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  workspace_id        = each.value.workspace_id
  enable_telemetry    = false
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
}

#--------------------------------------------------------------------
# AML Workspace
#--------------------------------------------------------------------
module "avm-res-machinelearningservices-workspace" {
  source                        = "Azure/avm-res-machinelearningservices-workspace/azurerm"
  version                       = "0.9.0"
  for_each                      = { for k, v in local.aml_workspace : k => v if var.enable_aml_workspace }
  name                          = each.value.name
  location                      = each.value.location
  resource_group_name           = each.value.resource_group_name
  enable_telemetry              = each.value.enable_telemetry
  public_network_access_enabled = each.value.public_network_access_enabled
  application_insights = {
    resource_id = try(module.avm-res-insights-component[each.value.application_insights_key].resource_id, null)
  }
  key_vault = {
    resource_id = try(module.keyvault[each.value.key_vault_key].resource_id, null)
  }
  storage_account = {
    resource_id = try(module.avm-res-storage-storageaccount[each.value.storage_account_key].resource_id, null)
  }
  managed_identities = {
    system_assigned = try(each.value.managed_identities.system_assigned, false)
  }
  private_endpoints = {
    for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
      name                            = try(pe.name, null)
      subnet_resource_id              = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
      private_dns_zone_resource_ids   = try(pe.private_dns_zone_resource_ids, [])
      private_service_connection_name = try(pe.name, null)
      tags                            = try(pe.tags, null)
    }
  }
  diagnostic_settings = (
    contains(keys(each.value), "diagnostic_settings") && length(each.value.diagnostic_settings) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
      }
    }
    : null
  )
  workspace_managed_network = try(each.value.workspace_managed_network, null)
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.avm-res-insights-component, module.keyvault, module.avm-res-storage-storageaccount, module.law]
}

#--------------------------------------------------------------------
# Cognitive Services Account
#--------------------------------------------------------------------
module "avm-res-cognitiveservices-account" {
  source                = "Azure/avm-res-cognitiveservices-account/azurerm"
  for_each              = { for k, v in local.cognitiveservices : k => v if var.enable_cognitiveservices && v.enable_account }
  version               = "0.10.2"
  name                  = each.value.name
  parent_id             = each.value.parent_id
  location              = each.value.location
  sku_name              = each.value.sku_name
  kind                  = each.value.kind
  local_auth_enabled    = each.value.local_auth_enabled
  public_network_access_enabled = each.value.public_network_access_enabled
  custom_subdomain_name = try(each.value.custom_subdomain_name, each.value.name)
  enable_telemetry              = each.value.enable_telemetry
  private_endpoints = {
    for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
      name                          = try(pe.name, null)
      subnet_resource_id            = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
      private_dns_zone_resource_ids = try(pe.private_dns_zone_resource_ids, [])
      location                      = try(pe.location, each.value.location)
      tags                          = try(pe.tags, null)
    }
  }

  diagnostic_settings = (
    contains(keys(each.value), "diagnostic_settings") && length(each.value.diagnostic_settings) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
      }
    }
    : null
  )
  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.law]
}
#--------------------------------------------------------------------
# Cosmos DB Account configuration
#--------------------------------------------------------------------
module "avm-res-documentdb-databaseaccount" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.10.0"

  for_each = var.enable_cosmosdb_account ? local.cosmosdb_account_configs : {}

  name                = each.value.name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name
  minimal_tls_version = try(each.value.minimal_tls_version, null)
  enable_telemetry    = each.value.enable_telemetry
  public_network_access_enabled = try(each.value.public_network_access_enabled, false)
  backup                        = try(each.value.backup, {})
  mongo_databases      = try(each.value.mongo_databases, {})
  mongo_server_version = try(each.value.mongo_server_version, null)
  geo_locations = try(each.value.geo_locations, null)
  private_endpoints_manage_dns_zone_group = try(each.value.private_endpoints_manage_dns_zone_group, false)

  consistency_policy = {
    consistency_level = "Session"
  }

  capabilities = [
    {
      name = "EnableMongo"
    }
  ]
  managed_identities = {
    user_assigned_resource_ids = toset([
      for id_key in try(each.value.user_assigned_identity_keys, []) :
      module.avm-res-managedidentity-userassignedidentity[id_key].resource_id
    ])
  }

  private_endpoints = {
    for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
      name                          = try(pe.name, null)
      subnet_resource_id            = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
      subresource_name              = pe.subresource_name
      private_dns_zone_resource_ids = try(pe.private_dns_zone_resource_ids, [])
      tags                          = try(pe.tags, null)
    }
  }

  diagnostic_settings = (
    contains(keys(each.value), "diagnostic_settings") && length(each.value.diagnostic_settings) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
        metric_categories     = try(diag.metric_categories, ["SLI", "Requests"])
        # optional (safe): log groups/categories if you want
        log_groups            = try(diag.log_groups, null)
        log_categories        = try(diag.log_categories, null)

      }
    }
    : null
  )

  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )
  depends_on = [module.law]
}

#--------------------------------------------------------------------
# Virtual Network Locals to check the condition to create or use existing
#--------------------------------------------------------------------
locals {
  vnets_to_create = {
    for k, v in local.virtual_networks : k => v
    if try(v.create_vnet, true)
  }

  vnets_existing = {
    for k, v in local.virtual_networks : k => v
    if !try(v.create_vnet, true)
  }
}
locals {
  existing_subnets_flat = merge([
    for vnet_key, vnet in local.vnets_existing : {
      for subnet_key, subnet in try(vnet.existing_subnets, {}) :
      "${vnet_key}.${subnet_key}" => {
        vnet_key    = vnet_key
        subnet_key  = subnet_key
        subnet_name = subnet.name
        rg_name     = coalesce(try(vnet.resource_group_name, null), data.azurerm_resource_group.rg.name)
      }
    }
  ]...)
}
locals {
  vnet_ids = merge(
    { for k, m in module.avm_res_network_virtualnetwork : k => m.resource_id },
    { for k, d in data.azurerm_virtual_network.existing : k => d.id }
  )
}
locals {
  created_subnet_ids = merge([
    for vnet_key, vnet_mod in module.avm_res_network_virtualnetwork : {
      for subnet_key, subnet_mod in vnet_mod.subnets :
      "${vnet_key}.${subnet_key}" => subnet_mod.resource_id
    }
  ]...)

  existing_subnet_ids = {
    for k, s in data.azurerm_subnet.existing : k => s.id
  }

  subnet_ids = merge(local.created_subnet_ids, local.existing_subnet_ids)
}
#--------------------------------------------------------------------
# NSG Locals to check the condition to create or use existing
#--------------------------------------------------------------------
locals {
  # 1) Split: create vs lookup
  nsg_create = {
    for k, v in local.nsg_configs : k => v
    if try(v.create_nsg, true)
  }

  nsg_lookup = {
    for k, v in local.nsg_configs : k => v
    if !try(v.create_nsg, true)
  }

  # 2) Convert rules list -> map keyed by rule name (module requires map(object(...))) [1](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup)
  nsg_security_rules = {
    for nsg_key, nsg in local.nsg_create : nsg_key => {
      for r in try(nsg.security_rules, []) : r.name => {
        # required fields
        name      = r.name
        priority  = r.priority
        direction = r.direction
        access    = r.access
        protocol  = r.protocol

        # optional fields (pass only if present)
        source_address_prefix      = try(r.source_address_prefix, null)
        destination_address_prefix = try(r.destination_address_prefix, null)

        source_port_range      = try(r.source_port_range, null)
        destination_port_range = try(r.destination_port_range, null)

        # If in future you use *ranges*, module supports these too [1](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup)
        source_address_prefixes      = try(r.source_address_prefixes, null)
        destination_address_prefixes = try(r.destination_address_prefixes, null)
        source_port_ranges           = try(r.source_port_ranges, null)
        destination_port_ranges      = try(r.destination_port_ranges, null)

        description = try(r.description, null)
      }
    }
  }
  # 5) Unified outputs (IDs of created + existing)
  nsg_ids = merge(
    { for k, m in module.nsg : k => m.resource_id },
    { for k, d in data.azurerm_network_security_group.existing : k => d.id }
  )
}
#--------------------------------------------------------------------
# rbac Role Assignment
#--------------------------------------------------------------------
module "avm-res-authorization-roleassignment" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.0"
  count = var.enable_role_assignments ? 1 : 0
  role_assignments_azure_resource_manager = {
    user_identity_function_stoage = {
      scope                = try(module.avm-res-storage-storageaccount["st1"].resource_id, null)
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = try(module.avm-res-managedidentity-userassignedidentity["function"].principal_id, null)
    }
  }
  enable_telemetry = false
}

#--------------------------------------------------------------------
# Private Endpoint
#--------------------------------------------------------------------
locals {
  private_endpoint_configs = { 
    pe_cosmosdb = {
      name                          = "pe-cosmosdb"
      subnet_resource_id            = try(local.subnet_ids["vnet1_manual.snet1"], null)
      private_connection_resource_id = try(module.avm-res-documentdb-databaseaccount["cosmosdb1"].resource_id, null)
      subresource_names       = ["MongoDB"]
      private_dns_zone_resource_ids = []
      location                      = data.azurerm_resource_group.rg.location
      tags                          = {
        environment = "test"
      }
    }
  }
}
module "avm-res-network-privateendpoint" {
  source  = "Azure/avm-res-network-privateendpoint/azurerm"
  version = "0.2.0"
  for_each = { for k, v in local.private_endpoint_configs : k => v if var.enable_private_endpoints }
  name                 = each.value.name
  location             = each.value.location
  resource_group_name  = data.azurerm_resource_group.rg.name
  subnet_resource_id   = each.value.subnet_resource_id
  network_interface_name = each.value.name
  private_connection_resource_id = each.value.private_connection_resource_id
  subresource_names       = each.value.subresource_names
  enable_telemetry        = false
}

#--------------------------------------------------------------------
# Private DNS zone avm module to create and data block to use existing.
#--------------------------------------------------------------------
module "avm-res-network-privatednszone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.4"
  for_each = {for k, v in local.private_dns_zones : k => v if var.enable_private_dns_zone && v.create_private_dns_zone }
  enable_telemetry      = false
  domain_name = each.value.private_dns_zone_name
  parent_id = data.azurerm_resource_group.rg.id
  virtual_network_links = {
    vnet_link = {
      name                  = "${each.value.private_dns_zone_name}-vnetlink"
      virtual_network_id    = each.value.vnet_id
      registration_enabled  = false
    }
  }
}
data "azurerm_private_dns_zone" "existing" {
  for_each = {for k, v in local.private_dns_zones : k => v if var.enable_private_dns_zone && !v.create_private_dns_zone }
  name                = each.value.private_dns_zone_name
  resource_group_name = each.value.resource_group_name
}
