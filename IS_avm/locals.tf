locals {
  virtual_networks = {
    vnet-primary = {
      create_vnet            = true
      parent_id             = data.azurerm_resource_group.rg.id
      name                   = "vent-infy-is-primary"
      location               = data.azurerm_resource_group.rg.location
      address_space          = ["10.0.0.0/16"]
      enable_ddos_protection = false
      dns_servers            = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
      }
      subnet_configs = {
        snetmi = {
          name           = "subnet-mi"
          address_prefix = ["10.0.1.0/24"]
          nsg_key        = "nsg_primary"
          route_table   = { id = module.avm-res-network-routetable["rt_primary"].resource_id }

          delegation = {
            name = "managedinstancedelegation"
            service_delegation = {
              name    = "Microsoft.Sql/managedInstances"
              actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
            }
          }
        }
        snet1 = {
          name           = "subnet-pvt"
          address_prefix = ["10.0.2.0/24"]
          nsg_key        = "nsg_primary"
          route_table   = { id = module.avm-res-network-routetable["rt_primary"].resource_id }
        }
        snet2 = {
          name           = "subnet-aks"
          address_prefix = ["10.0.3.0/24"]
          nsg_key        = "nsg_primary"
        }
      }
    }
    vnet-dr = {
      create_vnet            = true
      parent_id             = data.azurerm_resource_group.rg_dr.id
      name                   = "vent-infy-is-dr"
      location               = data.azurerm_resource_group.rg_dr.location
      address_space          = ["10.1.0.0/16"]
      enable_ddos_protection = false
      dns_servers            = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
      }
      subnet_configs = {
        snetmi = {
          name           = "subnet-mi"
          address_prefix = ["10.1.1.0/24"]
          nsg_key        = "nsg_dr"
          route_table   = { id = module.avm-res-network-routetable["rt_dr"].resource_id }

          delegation = {
            name = "managedinstancedelegation"
            service_delegation = {
              name    = "Microsoft.Sql/managedInstances"
              actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
            }
          }
        }
        snet1 = {
          name           = "subnet-pvt"
          address_prefix = ["10.1.2.0/24"]
          nsg_key        = "nsg_dr"
          route_table   = { id = module.avm-res-network-routetable["rt_dr"].resource_id }
        }
      }
    }
  }
}

#--------------------------------------------------------------------
# Network Security Group configurations
#--------------------------------------------------------------------
locals {
  nsg_configs = {
    nsg_primary = {
      create_nsg = true
      nsg_name   = "mi-security-group-primary"
      location   = data.azurerm_resource_group.rg.location
      rg_name    = data.azurerm_resource_group.rg.name

      security_rules = [
        # Management ports
        {
          name                       = "allow_management_inbound"
          priority                   = 410
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["9000", "9003", "1438", "1440", "1452"]
        },
        # Health probe
        {
          name                       = "allow_health_probe_inbound"
          priority                   = 200
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_address_prefix      = "AzureLoadBalancer"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        },
        # TDS (SQL client)
        {
          name                       = "allow_tds_inbound"
          priority                   = 300
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "VirtualNetwork"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "1433"
        },
        # Replication ports from DR
        {
          name                       = "allow_replication_inbound_5022"
          priority                   = 400
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "10.1.0.0/16"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "5022"
        },
        {
          name                       = "allow_replication_inbound_range"
          priority                   = 401
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "10.1.0.0/16"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["11000-11999"]
        },
        # Outbound rules
        {
          name                       = "allow_management_outbound"
          priority                   = 106
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["80", "443", "12000"]
        },
        {
          name                       = "allow_replication_outbound_5022"
          priority                   = 200
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "10.1.0.0/16"
          source_port_range          = "*"
          destination_port_range     = "5022"
        },
        {
          name                       = "allow_replication_outbound_range"
          priority                   = 201
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "10.1.0.0/16"
          source_port_range          = "*"
          destination_port_ranges    = ["11000-11999"]
        },
        # Deny all
        {
          name                       = "deny_all_inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        },
        {
          name                       = "deny_all_outbound"
          priority                   = 4096
          direction                  = "Outbound"
          access                     = "Deny"
          protocol                   = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        }
      ]
      tags = {
        created_by = "terraform"
      }
    }
    nsg_dr = {
      create_nsg = true
      nsg_name   = "mi-security-group-dr"
      location   = data.azurerm_resource_group.rg_dr.location
      rg_name    = data.azurerm_resource_group.rg_dr.name

      security_rules = [
        # Management ports
        {
          name                       = "allow_management_inbound"
          priority                   = 410
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["9000", "9003", "1438", "1440", "1452"]
        },
        # Health probe
        {
          name                       = "allow_health_probe_inbound"
          priority                   = 200
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_address_prefix      = "AzureLoadBalancer"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        },
        # TDS (SQL client)
        {
          name                       = "allow_tds_inbound"
          priority                   = 300
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "VirtualNetwork"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "1433"
        },
        # Replication ports from DR
        {
          name                       = "allow_replication_inbound_5022"
          priority                   = 400
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "10.0.0.0/16"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "5022"
        },
        {
          name                       = "allow_replication_inbound_range"
          priority                   = 401
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "10.0.0.0/16"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["11000-11999"]
        },
        # Outbound rules
        {
          name                       = "allow_management_outbound"
          priority                   = 401
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_ranges    = ["80", "443", "12000"]
        },
        {
          name                       = "allow_replication_outbound_5022"
          priority                   = 200
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "10.0.0.0/16"
          source_port_range          = "*"
          destination_port_range     = "5022"
        },
        {
          name                       = "allow_replication_outbound_range"
          priority                   = 201
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "10.0.0.0/16"
          source_port_range          = "*"
          destination_port_ranges    = ["11000-11999"]
        },
        # Deny all
        {
          name                       = "deny_all_inbound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        },
        {
          name                       = "deny_all_outbound"
          priority                   = 4096
          direction                  = "Outbound"
          access                     = "Deny"
          protocol                   = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
        }
      ]
      tags = {
        created_by = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# Route Table configurations
#--------------------------------------------------------------------
locals {
  route_table_configs = {
    rt_primary = {
      name = "sqlmi-route-table-primary"
      location = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
    rt_dr = {
      name = "sqlmi-route-table-dr"
      location = data.azurerm_resource_group.rg_dr.location
      resource_group_name = data.azurerm_resource_group.rg_dr.name
    }
  }
}

#--------------------------------------------------------------------
# User Assigned Identity
#--------------------------------------------------------------------
locals {
  user_assigned_identities = {
    sqlmi = {
      name                = "mi-sqlmi-identity"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
    secondary = {
      name                = "mi-sqlmi-identity-dr"
      location            = data.azurerm_resource_group.rg_dr.location
      resource_group_name = data.azurerm_resource_group.rg_dr.name
    }
    aks = {
      name                = "mi-aks-identity"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
  }
}


variable "sqlmi_adminpass" {
  description = "Admin password for the primary SQL Managed Instance"
  type        = string
  sensitive   = true
  validation {
    condition  = length(var.sqlmi_adminpass) >= 16 && can(regex("[A-Z]", var.sqlmi_adminpass)) && can(regex("[a-z]", var.sqlmi_adminpass)) && can(regex("[0-9]", var.sqlmi_adminpass)) && can(regex("[^A-Za-z0-9]", var.sqlmi_adminpass))
    error_message = "admin password must be at least 16 characters long and include at least one uppercase letter, one lowercase letter, one number, and one special character."
  }
}
locals {
  sqlmi-configs = {
    sqlmi_primary = {
      name                = "sql-mk-primary-01"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      subnet_id = local.subnet_ids["vnet-primary.snetmi"]  #subnet should be delegated to Microsoft.Sql/managedInstances and nsg rules applied as per sql mi requirements
      administrator_login          = "sqladminuser"
      administrator_login_password = var.sqlmi_adminpass
      sku_name                     = "GP_Gen5"
      vcores                       = 4
      storage_size_in_gb           = 128
      license_type                 = "LicenseIncluded"
      timezone_id                  = "India Standard Time"
      proxy_override               = "Proxy"
      public_data_endpoint_enabled = false
      minimum_tls_version          = "1.2"
      zone_redundant_enabled       = false
      user_assigned_identity_keys  = ["sqlmi"]
      private_endpoints_manage_dns_zone_group = true
      private_endpoints = {
        sqlmipe = {
          name                          = "pvt-endpoint-sqlmi001"
          vnet_key                      = "vnet-primary"
          subnet_key                    = "snet1"
          subresource_name              = "managedInstance"
        }
      }
      diagnostic_settings = {
        di_diag = {
          name                  = "diag-di-sqlmi-01"
          workspace_resource_id = try(module.law.resource_id, null)
        }
      }
    }
  }
  sqlmi-configs-secondary = {
    sqlmi_dr = {
      name                = "sql-mk-infy-01-dr"
      location            = data.azurerm_resource_group.rg_dr.location
      resource_group_name = data.azurerm_resource_group.rg_dr.name
      subnet_id = local.subnet_ids["vnet-dr.snetmi"]  #subnet should be delegated to Microsoft.Sql/managedInstances and nsg rules applied as per sql mi requirements
      administrator_login          = "sqladminuser"
      administrator_login_password = var.sqlmi_adminpass
      sku_name                     = "GP_Gen5"
      vcores                       = 4
      storage_size_in_gb           = 128
      license_type                 = "LicenseIncluded"
      timezone_id                  = "India Standard Time"
      proxy_override               = "Proxy"
      public_data_endpoint_enabled = false
      minimum_tls_version          = "1.2"
      zone_redundant_enabled       = false
      user_assigned_identity_keys  = ["secondary"]
      private_endpoints_manage_dns_zone_group = true
      dns_zone_partner_id = module.sqlmi_primary["sqlmi_primary"].resource_id
      private_endpoints = {
        sqlmipe = {
          name                          = "pvt-endpoint-sql-mk-infy-01-dr"
          vnet_key                      = "vnet-dr"
          subnet_key                    = "snet1"
          subresource_name              = "managedInstance"
        }
      }
      diagnostic_settings = {
        di_diag = {
          name                  = "diag-di-sql-mk-infy-01-dr"
          workspace_resource_id = try(module.law.resource_id, null)
        }
      }
    }
  }
}


#--------------------------------------------------------------------
# #AKS configurations
#--------------------------------------------------------------------
locals {
  aks_configs = {
    aks_dr = {
      name = "aks-dr-004"
      resource_group_name = data.azurerm_resource_group.rg.name
      location = data.azurerm_resource_group.rg.location
      kubernetes_version         = "1.34.1"
      sku_tier                   = "Free"
      oidc_issuer_enabled        = true
      workload_identity_enabled  = true
      azure_policy_enabled       = true
      dns_prefix = "aks-dr-004"
      local_account_disabled = true
      user_assigned_identity_keys                    = ["aks"]
      private_cluster_enabled    = true                    # force replacement of the cluster if changed
      role_based_access_control_enabled = true                      # force replacement of the cluster if changed
      azure_active_directory_role_based_access_control = {
        tenant_id = data.azurerm_client_config.current.tenant_id
        admin_group_object_ids = try([data.azuread_group.ad_group.object_id], null)
        azure_rbac_enabled = false                         # (false uses Microsoft entra ID authentication with kubernetes RBAC)
      }
      default_node_pool = {
        name            = "systemnp"
        vm_size         = "standard_b2ms"
        os_disk_size_gb = 128
        os_disk_type    = "Managed"
        zones           = ["1", "2", "3"]
        min_count            = 3
        type                 = "VirtualMachineScaleSets"
        max_count            = 5
        auto_scaling_enabled = true
        max_pods             = 110
        vnet_subnet_id       = local.subnet_ids["vnet-primary.snet2"]
        node_labels = {
          "nodepool-type" = "system"
        }
        node_taints          = ["node=infysvc:NoSchedule"]
      }
      network_profile = {
        network_plugin      = "azure" 
        network_policy      = "cilium" 
        network_data_plane  = "cilium"
        network_plugin_mode = "overlay"
        dns_service_ip      = "10.3.0.10"
        service_cidr        = "10.3.0.0/24"
        outbound_type     = "loadBalancer"
        load_balancer_sku = "standard"
      }
      service_mesh_profile = {
        mode = "Istio"
        revisions = ["asm-1-27"]
        external_ingress_gateway_enabled = true
        internal_ingress_gateway_enabled = true
      }
      diagnostic_settings = {
        di_diag = {
          name                  = "diag-aks-dr-001cd"
          workspace_resource_id = try(module.law.resource_id, null)
        }
      }
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }

    }
  }
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

  # 2) Convert rules list -> map keyed by rule name
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


