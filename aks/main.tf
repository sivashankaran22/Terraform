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
  enable_telemetry    = false
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
  #dns_prefix_private_cluster = "dr-aks-03"
  #private_dns_zone_id        = local.private_dns_ids["aks"] 
  dns_prefix = each.value.dns_prefix

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