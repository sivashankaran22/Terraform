data "azurerm_resource_group" "rg" {
  name = "rg-infy-terraform"
}
# data "azurerm_resource_group" "rg_dr" {
#   name = "rg-node-terraform"
# }

# data "azurerm_resource_group" "rg" {
#   name = "rg-infosys-is"
# }

# data "azurerm_resource_group" "rg_dr" {
#   name = "rg-infosys-is-dr"
# }


# data "azuread_group" "ad_group" {
# display_name   = "infy-test"
# security_enabled = true
# }

#--------------------------------------------------------------------
# Virtual Network and Subnet
#--------------------------------------------------------------------
module "avm_res_network_virtualnetwork" {
  source   = "Azure/avm-res-network-virtualnetwork/azurerm"
  version  = "0.16.0"
  for_each = { for k, v in local.vnets_to_create : k => v }
  #for_each = local.vnets_to_create

  name      = each.value.name
  location  = each.value.location
  parent_id = try(each.value.parent_id, data.azurerm_resource_group.rg.id)

  address_space = each.value.address_space

  enable_telemetry = false
  dns_servers      = (try(each.value.dns_servers, null) == null ? null : { dns_servers = each.value.dns_servers })
  # --- Transform your subnet_configs -> module.subnets expected shape ---
  subnets = {
    for sk, s in each.value.subnet_configs : sk => {
      name             = s.name
      address_prefixes = s.address_prefix
      default_outbound_access_enabled = try(s.default_outbound_access_enabled, true)
      service_endpoints_with_location = [
        for svc in try(s.service_endpoints, []) : {
          service = svc
          # locations = [each.value.location] # use only if you want location restriction
        }
      ]

      network_security_group = try((try(s.nsg_key, null) == null ? null : { id = local.nsg_ids[s.nsg_key] }), null)
      route_table = try(s.route_table, null)
      private_endpoint_network_policies = "Disabled"

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
  for_each            = { for k, v in local.vnets_existing : k => v }
  name                = each.value.name
  resource_group_name = coalesce(try(each.value.resource_group_name, null), data.azurerm_resource_group.rg.name)
}
data "azurerm_subnet" "existing" {
  for_each             = { for k, v in local.existing_subnets_flat : k => v }
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
  for_each            = { for k, v in local.nsg_create : k => v }
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
  for_each            = { for k, v in local.nsg_lookup : k => v }
  name                = each.value.nsg_name
  resource_group_name = coalesce(try(each.value.rg_name, null), data.azurerm_resource_group.rg.name)
}

module "avm-res-network-routetable" {
  source  = "Azure/avm-res-network-routetable/azurerm"
  for_each = { for k, v in local.route_table_configs : k => v }
  version = "0.4.1"
  name = each.value.name
  location = each.value.location
  resource_group_name = each.value.resource_group_name
  bgp_route_propagation_enabled = try(each.value.bgp_route_propagation_enabled, false)
  enable_telemetry    = false
  subnet_resource_ids = (
    try(each.value.subnet_resource_ids, {}) == {}
    ? {}
    : { for k, v in each.value.subnet_resource_ids : k => tostring(v) }
  )
  routes = {
    for k, v in try(each.value.routes, {}) : k => {
      name                   = v.name
      address_prefix         = v.address_prefix
      next_hop_type          = v.next_hop_type
      next_hop_in_ip_address = try(v.next_hop_in_ip_address, null)
    }
  }
}

module "avm-res-managedidentity-userassignedidentity" {
  source              = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version             = "0.3.4"
  for_each            = { for k, v in local.user_assigned_identities : k => v }
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


#This is the module call
module "sqlmi_primary" {
  source = "Azure/avm-res-sql-managedinstance/azurerm"
  version = "0.1.3"
  for_each = { for k, v in local.sqlmi-configs : k => v }

  name                         = each.value.name
  location                     = each.value.location
  administrator_login          = each.value.administrator_login
  administrator_login_password = each.value.administrator_login_password
  resource_group_name          = each.value.resource_group_name
  sku_name                     = each.value.sku_name
  vcores                       = each.value.vcores
  storage_size_in_gb           = each.value.storage_size_in_gb
  license_type                 = each.value.license_type
  timezone_id                  = each.value.timezone_id
  proxy_override               = each.value.proxy_override
  public_data_endpoint_enabled = each.value.public_data_endpoint_enabled
  subnet_id                    = each.value.subnet_id
  minimum_tls_version          = each.value.minimum_tls_version
  zone_redundant_enabled = each.value.zone_redundant_enabled
  storage_account_type = "GRS"
  enable_telemetry    = false
  dns_zone_partner_id = try(each.value.dns_zone_partner_id, null)

  managed_identities = {
    user_assigned_resource_ids = toset([
      for id_key in try(each.value.user_assigned_identity_keys, []) :
      module.avm-res-managedidentity-userassignedidentity[id_key].resource_id
    ])
  }

  active_directory_administrator = (
    try(each.value.active_directory_administrator, null) == null
    ? null
    : {
        azuread_authentication_only = each.value.active_directory_administrator.azuread_authentication_only
        object_id                   = each.value.active_directory_administrator.object_id
        tenant_id                   = each.value.active_directory_administrator.tenant_id
        login_username              = each.value.active_directory_administrator.login_username
      }
  )

  private_endpoints_manage_dns_zone_group = try(each.value.private_endpoints_manage_dns_zone_group, false)
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
        log_analytics_destination_type = "AzureDiagnostics"
      }
    }
    : null
  )

  depends_on = [
    module.avm-res-managedidentity-userassignedidentity, module.nsg
  ]
}

module "sqlmi_secondary" {
  source = "Azure/avm-res-sql-managedinstance/azurerm"
  version = "0.1.3"
  for_each = { for k, v in local.sqlmi-configs-secondary : k => v }

  name                         = each.value.name
  location                     = each.value.location
  administrator_login          = each.value.administrator_login
  administrator_login_password = each.value.administrator_login_password
  resource_group_name          = each.value.resource_group_name
  sku_name                     = each.value.sku_name
  vcores                       = each.value.vcores
  storage_size_in_gb           = each.value.storage_size_in_gb
  license_type                 = each.value.license_type
  timezone_id                  = each.value.timezone_id
  proxy_override               = each.value.proxy_override
  public_data_endpoint_enabled = each.value.public_data_endpoint_enabled
  subnet_id                    = each.value.subnet_id
  minimum_tls_version          = each.value.minimum_tls_version
  zone_redundant_enabled = each.value.zone_redundant_enabled
  storage_account_type = "GRS"
  enable_telemetry    = false
  dns_zone_partner_id = try(each.value.dns_zone_partner_id, null)

  managed_identities = {
    user_assigned_resource_ids = toset([
      for id_key in try(each.value.user_assigned_identity_keys, []) :
      module.avm-res-managedidentity-userassignedidentity[id_key].resource_id
    ])
  }

  active_directory_administrator = (
    try(each.value.active_directory_administrator, null) == null
    ? null
    : {
        azuread_authentication_only = each.value.active_directory_administrator.azuread_authentication_only
        object_id                   = each.value.active_directory_administrator.object_id
        tenant_id                   = each.value.active_directory_administrator.tenant_id
        login_username              = each.value.active_directory_administrator.login_username
      }
  )

  private_endpoints_manage_dns_zone_group = try(each.value.private_endpoints_manage_dns_zone_group, false)
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
        log_analytics_destination_type = "AzureDiagnostics"
      }
    }
    : null
  )

  depends_on = [
    module.avm-res-managedidentity-userassignedidentity, module.nsg, module.sqlmi_primary, module.avm_res_network_virtualnetwork
  ]
}


#Peering primary <-> DR VNets
# resource "azurerm_virtual_network_peering" "primary_to_dr" {
#   name                      = "peer-primary-to-dr"
#   resource_group_name       = data.azurerm_resource_group.rg.name
#   virtual_network_name      = module.avm_res_network_virtualnetwork["vnet-primary"].name
#   remote_virtual_network_id = module.avm_res_network_virtualnetwork["vnet-dr"].resource_id
#   allow_virtual_network_access = true
#   allow_forwarded_traffic      = true
#   use_remote_gateways          = false
#   depends_on = [module.avm_res_network_virtualnetwork]
# }

# resource "azurerm_virtual_network_peering" "dr_to_primary" {
#   name                      = "peer-dr-to-primary"
#   resource_group_name       = data.azurerm_resource_group.rg_dr.name
#   virtual_network_name      = module.avm_res_network_virtualnetwork["vnet-dr"].name
#   remote_virtual_network_id = module.avm_res_network_virtualnetwork["vnet-primary"].resource_id
#   allow_virtual_network_access = true
#   allow_forwarded_traffic      = true
#   use_remote_gateways          = false
#   depends_on = [module.avm_res_network_virtualnetwork]
# }


# resource "azurerm_mssql_managed_instance_failover_group" "example" {
#   name                        = "sqlmi-infy-failover-group"
#   location                    = data.azurerm_resource_group.rg.location
#   managed_instance_id         = module.sqlmi_primary["sqlmi_primary"].resource_id
#   partner_managed_instance_id = module.sqlmi_secondary["sqlmi_dr"].resource_id
#   secondary_type              = "Geo"
#   read_write_endpoint_failover_policy {
#     mode          = "Automatic"
#     grace_minutes = 60
#   }
#   depends_on = [ module.nsg ]
# }



# --------------------------------------------------------------------
# AKS
# --------------------------------------------------------------------
# note:
# 1: dns_prefix_private_cluster required private_dns_zone_id
# 2: if local_account_disabled true then role_based_access_control_enabled must be true and it required azure_active_directory_role_based_access_control
# 3: api_server_access_profile required then subnet is not allowed to be same with agent node subnet

module "avm-res-containerservice-managedcluster" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.3.3"
  for_each = { for k, v in local.aks_configs : k => v }

  name                       = each.value.name
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = each.value.resource_group_name
  kubernetes_version         = each.value.kubernetes_version # optional; omit to use default
  sku_tier                   = each.value.sku_tier   # "Free" | "Standard" (AKS Uptime SLA)
  enable_telemetry           = false    
  oidc_issuer_enabled        = each.value.oidc_issuer_enabled
  workload_identity_enabled  = each.value.workload_identity_enabled
  azure_policy_enabled       = each.value.azure_policy_enabled

  private_cluster_enabled    = each.value.private_cluster_enabled                    # force replacement of the cluster if changed
  dns_prefix_private_cluster = each.value.private_cluster_enabled ? each.value.dns_prefix : null 
  private_dns_zone_id        = each.value.private_cluster_enabled ? local.private_dns_ids["aks"] : null
  dns_prefix                 = each.value.private_cluster_enabled ? null : each.value.dns_prefix

  local_account_disabled = each.value.local_account_disabled
  role_based_access_control_enabled = each.value.role_based_access_control_enabled #Enabling Azure Active Directory integration requires that `role_based_access_control_enabled` be set to true."
  
  azure_active_directory_role_based_access_control = (
    try(each.value.azure_active_directory_role_based_access_control, null) == null
    ? null
    : {
        tenant_id = data.azurerm_client_config.current.tenant_id
        admin_group_object_ids = each.value.azure_active_directory_role_based_access_control.admin_group_object_ids
        azure_rbac_enabled = each.value.azure_active_directory_role_based_access_control.azure_rbac_enabled
      }
  ) 
  

  network_profile = {
    network_plugin      = each.value.network_profile.network_plugin      # "azure" (CNI) or "kubenet"
    network_policy      = each.value.network_profile.network_policy      # "azure" | "calico" (depends on plugin/region)
    network_data_plane     = each.value.network_profile.network_data_plane     # "cilium" (preview in some regions) or null
    network_plugin_mode = each.value.network_profile.network_plugin_mode # "overlay"
    dns_service_ip      = each.value.network_profile.dns_service_ip
    service_cidr        = each.value.network_profile.service_cidr
    outbound_type     = each.value.network_profile.outbound_type # "loadBalancer" | "userDefinedRouting" | "managedNATGateway" | "userAssignedNATGateway"
    load_balancer_sku = each.value.network_profile.load_balancer_sku     # "Basic" | "standard"
  }

  default_node_pool = {
    name            = each.value.default_node_pool.name
    vm_size         = each.value.default_node_pool.vm_size
    os_disk_size_gb = each.value.default_node_pool.os_disk_size_gb
    os_disk_type    = each.value.default_node_pool.os_disk_type # "Managed"|"Ephemeral"
    zones           = try(each.value.default_node_pool.zones, null)
    min_count            = each.value.default_node_pool.min_count # set both min/max to enable cluster autoscaler
    type                 = each.value.default_node_pool.type  # "VirtualMachineScaleSets" | "AvailabilitySet"
    max_count            = each.value.default_node_pool.max_count
    auto_scaling_enabled = each.value.default_node_pool.auto_scaling_enabled
    max_pods             = each.value.default_node_pool.max_pods
    vnet_subnet_id       = each.value.default_node_pool.vnet_subnet_id
    orchestrator_version = null # inherit cluster version if null
    # Optional
    kubelet_config = {
      cpu_manager_policy        = null
      cpu_cfs_quota_enabled     = null
      cpu_cfs_quota_period      = null
      image_gc_high_threshold   = 85
      image_gc_low_threshold    = 70
      topology_manager_policy   = null
      allowed_unsafe_sysctls    = []
      container_log_max_size_mb = 25
      container_log_max_line    = 5
    }
    linux_os_config = {
      swap_file_size_mb = 0
      sysctl_config = {
        net_core_somaxconn           = 16384
        net_ipv4_tcp_tw_reuse        = false
        net_ipv4_ip_local_port_range = "1024 65535"
      }
      transparent_huge_page_defrag = "madvise"
    }
    upgrade_settings = {
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
      max_surge                     = "10%"
    }
    node_labels = (
      try(each.value.default_node_pool.node_labels, null) == null
      ? null
      : { for k, v in each.value.default_node_pool.node_labels : k => tostring(v) }
    )
    node_taints = try(each.value.default_node_pool.node_taints, []) # e.g., ["CriticalAddonsOnly=true:NoSchedule"]
  }

  # Additional user pools (Portal: Node pools → Add node pool)
  node_resource_group_name = try(each.value.node_resource_group_name, null) # if not specified, node RG will be named MC_<RG>_<clusterName>_<location>
  node_pools = {
    for np_key, np_value in try(each.value.node_pools, {}) : np_key => {
      name    = np_value.name
      vm_size = np_value.vm_size
      mode    = np_value.mode  # "System" | "User"
      min_count            = np_value.min_count
      max_count            = np_value.max_count
      auto_scaling_enabled = np_value.auto_scaling_enabled
      vnet_subnet_id       = np_value.vnet_subnet_id
      os_sku               = np_value.os_sku       # "Ubuntu" | "CBLMariner"
      os_type              = np_value.os_type      # "Linux" | "Windows"
      os_disk_size_gb      = np_value.os_disk_size_gb
      os_disk_type         = np_value.os_disk_type # "Managed" | "Ephemeral"
      max_pods             = np_value.max_pods
      node_labels = (
        try(np_value.node_labels, null) == null
        ? null
        : { for k, v in np_value.node_labels : k => tostring(v) }
      )
      node_taints          = try(np_value.node_taints, [])
      zones                = try(np_value.zones, null)
      upgrade_settings = {
        drain_timeout_in_minutes      = 0
        node_soak_duration_in_minutes = 0
        max_surge                     = "10%"
      }
    }
  }

  managed_identities = {
    user_assigned_resource_ids = toset([
      for id_key in try(each.value.user_assigned_identity_keys, []) :
      module.avm-res-managedidentity-userassignedidentity[id_key].resource_id
    ])
  }

  diagnostic_settings = (
    contains(keys(each.value), "diagnostic_settings") && length(each.value.diagnostic_settings) > 0
    ? {
      for diag_k, diag in each.value.diagnostic_settings :
      diag_k => {
        name                  = try(diag.name, null)
        workspace_resource_id = try(diag.workspace_resource_id, null)
        log_analytics_destination_type = "AzureDiagnostics"
      }
    }
    : null
  )
  open_service_mesh_enabled = false
  service_mesh_profile = (
    try(each.value.service_mesh_profile, null) == null
    ? null
    : { 
        mode = each.value.service_mesh_profile.mode
        revisions = each.value.service_mesh_profile.revisions
        external_ingress_gateway_enabled = each.value.service_mesh_profile.external_ingress_gateway_enabled
        internal_ingress_gateway_enabled = each.value.service_mesh_profile.internal_ingress_gateway_enabled
     }
  )
  #disk_encryption_set_id = azurerm_disk_encryption_set.example.id

  tags = (
    try(each.value.tags, null) == null
    ? null
    : { for k, v in each.value.tags : k => tostring(v) }
  )

  # API server access (Basics → API server)
  # api_server_access_profile = {
  #   authorized_ip_ranges = [ # Only for Public clusters
  #     # "x.x.x.x/32"
  #   ]
  #   subnet_id                           = data.azurerm_subnet.existing["vnet1_manual:snet1"].id # Required if enable_vnet_integration=true
  #   virtual_network_integration_enabled = true
  # }
}


#--------------------------------------------------------------------
# App Service Plan
#--------------------------------------------------------------------
module "avm-res-web-serverfarm" {
  source              = "Azure/avm-res-web-serverfarm/azurerm"
  version             = "1.0.0"
  for_each            = { for k, v in local.app_service_plan : k => v }
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
# App Service Plan configurations
#--------------------------------------------------------------------
locals {
  app_service_plan = {
    plan1 = {
      name                = "infy-claims-functions-plan1"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      sku_name            = "P1v2"
      os_type             = "Windows"
      enable_telemetry    = false
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }
    }
  }
}

# locals {
#   app_service_plan = {
#     plan1 = {
#       name                = "infy-claims-functions-plan"
#       location            = data.azurerm_resource_group.rg.location
#       resource_group_name = data.azurerm_resource_group.rg.name
#       sku_name            = "EP1"
#       os_type             = "Windows"
#       maximum_elastic_worker_count = 20
#       zone_balancing_enabled = false
#       enable_telemetry    = false
#       tags = {
#         environment = "testing"
#         created_by  = "terraform"
#       }
#     }
#   }
# }

#--------------------------------------------------------------------
# Function App
#--------------------------------------------------------------------
module "avm-res-web-site" {
  source                                         = "Azure/avm-res-web-site/azurerm"
  for_each                                       = { for k, v in local.function_app_configs : k => v }
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

    # application_insights_connection_string = (
    #   each.value.enable_application_insights == true
    #   ? module.avm-res-insights-component[each.value.site_config.app_insights_key].connection_string
    #   : null
    # )

    # application_insights_key = (
    #   each.value.enable_application_insights == true
    #   ? module.avm-res-insights-component[each.value.site_config.app_insights_key].instrumentation_key
    #   : null
    # )
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
  depends_on = [module.avm-res-storage-storageaccount, module.avm-res-web-serverfarm, module.avm-res-storage-storageaccount["st1"].shares]
}
#--------------------------------------------------------------------
# Function App configurations
#--------------------------------------------------------------------
locals {
  function_app_configs = {
    function1 = {
      name                                           = "infy-claims-function-app"
      location                                       = data.azurerm_resource_group.rg.location
      resource_group_name                            = data.azurerm_resource_group.rg.name
      kind                                           = "functionapp"
      os_type                                        = "Windows"
      https_only                                     = true
      service_plan_resource_id                       = try(module.avm-res-web-serverfarm["plan1"].resource_id, null)
      storage_account_name                           = try(module.avm-res-storage-storageaccount["st1"].name, null)
      public_network_access_enabled                  = false
      enable_application_insights                    = false
      virtual_network_subnet_id                      = try(local.subnet_ids["vnet_pass.snet_func"], null)
      ftp_publish_basic_authentication_enabled       = false
      webdeploy_publish_basic_authentication_enabled = false
      user_assigned_identity_keys                    = ["function"]
      enable_telemetry                               = false
      site_config = {
        always_on        = false
        app_insights_key = "app_insights1"
        application_stack = {
          dotnet = { dotnet_version = "v8.0" }
        }
      }
      # site_config = {
      #   always_on        = false
      #   app_insights_key = "app_insights1"
      #   application_stack = {
      #     java = { java_version = "21" }
      #   }
      # }
      app_settings = {
        FUNCTIONS_WORKER_RUNTIME = "dotnet"
        dotnet_version             = "v8"
        # Add more app settings as needed
      }
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }
    }
  }
}
#--------------------------------------------------------------------
# #Storage Account configurations
#--------------------------------------------------------------------
locals {
  storage_account_configs = {
    st1 = {
      name                              = "sttestinfytes1201"
      resource_group_name               = data.azurerm_resource_group.rg.name
      location                          = data.azurerm_resource_group.rg.location
      account_tier                      = "Standard"
      account_replication_type          = "LRS"
      access_tier                       = "Hot"
      account_kind                      = "StorageV2"
      allow_nested_items_to_be_public   = false
      default_to_oauth_authentication   = false
      https_traffic_only_enabled        = true
      infrastructure_encryption_enabled = true
      local_user_enabled                = false
      min_tls_version                   = "TLS1_2"
      public_network_access_enabled     = false
      sftp_enabled                      = false
      shared_access_key_enabled         = true
      enable_telemetry                  = false
      blob_properties = {
        versioning_enabled            = true
        container_delete_retention_policy = {
          enabled = true
          days    = 7
        }
        delete_retention_policy = {
          days = 7
          permanent_delete_enabled = true
        }
      }
      network_rules_subnet_refs = [
        {
          vnet_key   = "vnet_pass"
          subnet_key = "snet_pass"
        }
      ]
      # private_endpoints = {
      #   stpe = {
      #     name                          = "pe-st003testinfy-blob"
      #     vnet_key                      = "vnet_pass"
      #     subnet_key                    = "snet_pass"
      #     subresource_name              = "blob"
      #     private_dns_zone_resource_ids = [local.private_dns_ids["storage"]]
      #     tags                          = { env = "test" }
      #   }
      # }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# #Storage Account
#--------------------------------------------------------------------
module "avm-res-storage-storageaccount" {
  source                            = "Azure/avm-res-storage-storageaccount/azurerm"
  for_each                          = { for k, v in local.storage_account_configs : k => v }
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
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  
    virtual_network_subnet_ids = [
      local.subnet_ids["vnet_pass.snet_pass"], local.subnet_ids["vnet_pass.snet_func"]
    ]
  }
  private_endpoints_manage_dns_zone_group = try(each.value.private_endpoints_manage_dns_zone_group, true)
  # private_endpoints = {
  #   for pe_key, pe in try(each.value.private_endpoints, {}) : pe_key => {
  #     name                          = try(pe.name, null)
  #     subnet_resource_id            = local.subnet_ids["${pe.vnet_key}.${pe.subnet_key}"]
  #     subresource_name              = pe.subresource_name
  #     private_dns_zone_resource_ids = try(pe.private_dns_zone_resource_ids, [])
  #     tags                          = try(pe.tags, null)
  #   }
  # }
  private_endpoints = {
    stpe = {
      name                          = "pe-st003testinfy-blob"
      subnet_resource_id            = local.subnet_ids["vnet_pass.snet_pass"]
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [local.private_dns_ids["storage"]]
    }
    stpe_file = {
      name                          = "pe-st003testinfy-file"
      subnet_resource_id            = local.subnet_ids["vnet_pass.snet_pass"]
      subresource_name              = "file"
      private_dns_zone_resource_ids = [local.private_dns_ids["storage_file"]]
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
  shares = {
    share1 = {
      name = "share1"
      quota = 100
      #root_squash = "NoRootSquash"
      #identity_based_authentication = {
      #  active_directory = {
      #    domain_name = "contoso.com"
      #    netbios_domain_name = "CONTOSO"
      #    forest_name = "contoso.com"
      #  }
      #}
    }
  }

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
}
#--------------------------------------------------------------------
# rbac Role Assignment
#--------------------------------------------------------------------
module "avm-res-authorization-roleassignment" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.0"
  role_assignments_azure_resource_manager = {
    user_identity_function_stoage = {
      scope                = try(module.avm-res-storage-storageaccount["st1"].resource_id, null)
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = try(module.avm-res-managedidentity-userassignedidentity["function"].principal_id, null)
    }
    user_identity_function_stoage_file = {
      scope                = try(module.avm-res-storage-storageaccount["st1"].resource_id, null)
      role_definition_name = "Contributor"
      principal_id         = try(module.avm-res-managedidentity-userassignedidentity["function"].principal_id, null)
    }
    # user_identity_privatedns_aks = {
    #   scope                = local.private_dns_ids["aks"]
    #   role_definition_name = "Contributor"
    #   principal_id         = try(module.avm-res-managedidentity-userassignedidentity["aks"].principal_id, null)
    # }
  }
  enable_telemetry = false
}


#--------------------------------------------------------------------
# Private DNS zone avm module to create and data block to use existing.
#--------------------------------------------------------------------
module "avm-res-network-privatednszone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.4.4"
  for_each = {for k, v in local.private_dns_zones : k => v }
  enable_telemetry      = false
  domain_name = each.value.private_dns_zone_name
  parent_id = each.value.parent_id
  virtual_network_links = {
    vnet_link = {
      name                  = "${each.value.private_dns_zone_name}-vnetlink"
      virtual_network_id    = each.value.vnet_id
      registration_enabled  = false
    }
  }
}

#--------------------------------------------------------------------
# Private DNS zone avm module to create and data block to use existing.
#--------------------------------------------------------------------
locals {
  private_dns_zones = {
    storage = {
      create_private_dns_zone = true
      private_dns_zone_name = "privatelink.blob.core.windows.net"
      parent_id = data.azurerm_resource_group.rg.id
      vnet_id             = local.vnet_ids["vnet_pass"]
    }
    storage_file = {
      create_private_dns_zone = true
      private_dns_zone_name = "privatelink.file.core.windows.net"
      parent_id = data.azurerm_resource_group.rg.id
      vnet_id             = local.vnet_ids["vnet_pass"]
    }
    aks = {
      create_private_dns_zone = true
      private_dns_zone_name = "privatelink.centralindia.azmk8s.io"
      parent_id = data.azurerm_resource_group.rg.id
      vnet_id               = try(local.vnet_ids["vnet_aks"], null)
    }
  }
  private_dns_ids = merge(
    { for k, m in module.avm-res-network-privatednszone : k => m.resource_id },
    #{ for k, d in data.azurerm_private_dns_zone.existing : k => d.id }
  )
}

# #--------------------------------------------------------------------
# # Private Endpoint
# #--------------------------------------------------------------------
# locals {
#   private_endpoint_configs = { 
#     pe_cosmosdb = {
#       name                          = "pe-storage-blob"
#       subnet_resource_id            = try(local.subnet_ids["vnet_pass.snet_pass"], null)
#       private_connection_resource_id = try(module.avm-res-storage-storageaccount["st1"].resource_id, null)
#       subresource_names              = ["blob"]
#       private_dns_zone_resource_ids = [module.avm-res-network-privatednszone["storage"].resource_id]
#       location                      = data.azurerm_resource_group.rg.location
#       tags                          = {
#         environment = "test"
#       }
#     }
#   }
# }
# module "avm-res-network-privateendpoint" {
#   source  = "Azure/avm-res-network-privateendpoint/azurerm"
#   version = "0.2.0"
#   for_each = { for k, v in local.private_endpoint_configs : k => v }
#   name                 = each.value.name
#   location             = each.value.location
#   resource_group_name  = data.azurerm_resource_group.rg.name
#   subnet_resource_id   = each.value.subnet_resource_id
#   network_interface_name = each.value.name
#   private_connection_resource_id = each.value.private_connection_resource_id
#   subresource_names       = each.value.subresource_names
#   enable_telemetry        = false
# }

#--------------------------------------------------------------------
#Key Vault
#--------------------------------------------------------------------
module "keyvault" {
  source   = "Azure/avm-res-keyvault-vault/azurerm"
  version  = "0.10.2"
  for_each = { for k, v in local.keyvault_configs : k => v }

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
  #depends_on = [module.law]

}


# module "avm-res-compute-diskencryptionset" {
#   source  = "Azure/avm-res-compute-diskencryptionset/azurerm"
#   version = "0.1.0"
#   key_vault_key_id = azurerm_key_vault_key.example.id
#   key_vault_resource_id = module.keyvault["kv"].resource_id
#   location = data.azurerm_resource_group.rg.location
#   resource_group_name = data.azurerm_resource_group.rg.name
#   name = "infy-disk-encryption-set"
# }

# data "azurerm_role_definition" "kv_crypto_user" {
#   name = "Key Vault Crypto Service Encryption User"
# }

# resource "azurerm_role_assignment" "des_kv_crypto" {
#   scope              = azurerm_key_vault_key.example.id
#   role_definition_id = data.azurerm_role_definition.kv_crypto_user.id
#   principal_id       = azurerm_disk_encryption_set.example.identity[0].principal_id
# }

# resource "azurerm_disk_encryption_set" "example" {
#   name                = "des"
#   location = data.azurerm_resource_group.rg.location
#   resource_group_name = data.azurerm_resource_group.rg.name
#   key_vault_key_id    = azurerm_key_vault_key.example.id

#   identity {
#     type = "SystemAssigned"
#   }
# }

# resource "azurerm_key_vault_key" "example" {
#   name         = "des-example-key"
#   key_vault_id = module.keyvault["kv"].resource_id
#   key_type     = "RSA"
#   key_size     = 2048

#   key_opts = [
#     "decrypt",
#     "encrypt",
#     "sign",
#     "unwrapKey",
#     "verify",
#     "wrapKey",
#   ]
# }