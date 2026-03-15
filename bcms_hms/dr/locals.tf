locals {
  virtual_networks = {
    vnet_aks = {
      create_vnet            = true
      parent_id              = data.azurerm_resource_group.rg.id
      name                   = "vnet-sind-bcmsdr-mgmt"
      location               = data.azurerm_resource_group.rg.location
      resource_group_name    = data.azurerm_resource_group.rg.name
      address_space          = ["100.123.136.0/24"]
      dns_servers            = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
        INFY_BusinessUnit = "IS"
      }
      subnet_configs = {
        snet_aks = {
          name           = "snet-sind-node-mgmt"
          address_prefix = ["100.123.136.0/25"]
          route_table   = { id = module.avm-res-network-routetable["rt_dr"].resource_id }
        }
        snet1 = {
          name              = "snet1-test"
          address_prefix    = ["100.123.136.128/25"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.AzureCosmosDB"]
          nsg_key           = "nsg1"
        }
      }
    }
    vnet_sqlmi_dr = {
      create_vnet            = true
      parent_id             = data.azurerm_resource_group.rg.id
      name                   = "vnet-sind-db-dr-mgmt"
      location               = data.azurerm_resource_group.rg.location
      resource_group_name    = data.azurerm_resource_group.rg.name
      address_space          = ["100.123.137.0/24"]
      dns_servers            = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
      }
      subnet_configs = {
        snetmi_dr = {
          name           = "snet-sind-sqlmi-dr-mgmt"
          address_prefix = ["100.123.137.0/25"]
          nsg_key        = "nsg_dr"
          #route_table   = { id = module.avm-res-network-routetable["rt_sqlmi_dr"].resource_id }
 
          delegation = {
            name = "managedinstancedelegation"
            service_delegation = {
              name    = "Microsoft.Sql/managedInstances"
              actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action"]
            }
          }
        }
        snet_pe = {
          name           = "snet-sind-sqlmi-pvt-dr-mgmt"
          address_prefix = ["100.123.137.128/25"]
          nsg_key        = "nsg_dr"
          #route_table   = { id = module.avm-res-network-routetable["rt_sqlmi_pe_dr"].resource_id }
        }
      }
    }
    vnet_pass = {
      create_vnet            = true
      parent_id              = data.azurerm_resource_group.rg.id
      name                   = "vnet-sind-paas-dr-mgmt"
      location               = data.azurerm_resource_group.rg.location
      address_space          = ["100.123.136.128/25"]
      dns_servers            = ["10.177.99.132"]
      tags = {
        created_by = "terraform"
        INFY_BusinessUnit = "IS"
      }
      subnet_configs = {
        snet_pass = {
          name           = "snet-sind-paas-dr-mgmt"
          address_prefix = ["100.123.136.128/27"]
          service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
        }
        snet_func = {
          name              = "snet-sind-func-dr-mgmt"
          address_prefix    = ["100.123.136.160/27"]
          service_endpoints = ["Microsoft.Web", "Microsoft.Storage"]
          delegation = {
            name = "functionapp"
            service_delegation = {
              name    = "Microsoft.Web/serverFarms"
              actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
            }
          }
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
    nsg_dr = {
      create_nsg = true
      nsg_name   = "mi-security-group-primary"
      location   = data.azurerm_resource_group.rg.location
      rg_name    = data.azurerm_resource_group.rg.name

      security_rules = [
                # Management ports
        {
          direction                  = "Inbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-healthprobe-in-100-122-1-32-27-v11"
          source_address_prefix      = "AzureLoadBalancer"
          source_port_range          = "*"
          destination_address_prefix = "100.122.1.32/27"
          destination_port_range     = "*"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 100
        },
        {
          direction                  = "Inbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-internal-in-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "100.122.1.32/27"
          destination_port_range     = "*"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 101
        },
        {
          direction                  = "Inbound"
          name                       = "prepare-allow_tds_inbound"
          source_address_prefix      = "VirtualNetwork"
          source_port_range          = "*"
          destination_address_prefix = "100.122.1.32/27"
          destination_port_ranges    = ["1433","11000-11999"]
          protocol                   = "Tcp"
          access                     = "Allow"
          priority                   = 1000
        },
        {
          direction                  = "Inbound"
          name                       = "prepare-deny_all_inbound"
          source_address_prefix      = "*"
          source_port_range          = "*"
          destination_address_prefix = "*"
          destination_port_range     = "*"
          protocol                   = "*"
          access                     = "Deny"
          priority                   = 4096
        },
        # Outbound rules
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-optional-azure-out-100-122-1-32-27"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "AzureCloud"
          destination_port_range     = "443"
          protocol                   = "Tcp"
          access                     = "Allow"
          priority                   = 100
        },
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-aad-out-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "AzureActiveDirectory"
          destination_port_range     = "443"
          protocol                   = "Tcp"
          access                     = "Allow"
          priority                   = 101
        },
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-onedsc-out-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "OneDsCollector"
          destination_port_range    = "443"
          protocol                   = "Tcp"
          access                     = "Allow"
          priority                   = 102
        },
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-internal-out-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "100.122.1.32/27"
          destination_port_range    = "*"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 103
        },
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-strg-p-out-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "Storage.centralindia"
          destination_port_range    = "443"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 104
        },
        {
          direction                  = "Outbound"
          name                       = "Microsoft.Sql-managedInstances_UseOnly_mi-strg-s-out-100-122-1-32-27-v11"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "Storage.southindia"
          destination_port_range    = "443"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 105
        },
        {
          direction                  = "Outbound"
          name                       = "AllowSQLMIstorage"
          source_address_prefix      = "100.122.1.32/27"
          source_port_range          = "*"
          destination_address_prefix = "100.122.100.32/27"
          destination_port_range    = "443"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 106
        },
        {
          direction                  = "Outbound"
          name                       = "storage-access"
          source_address_prefix      = "*"
          source_port_range          = "*"
          destination_address_prefix = "100.122.93.139/32"
          destination_port_range     = "443"
          protocol                   = "*"
          access                     = "Allow"
          priority                   = 107
        },
        {
          direction                  = "Outbound"
          name                       = "prepare-deny_all_outbound"
          source_address_prefix      = "*"
          source_port_range          = "*"
          destination_address_prefix = "*"
          destination_port_range     = "*"
          protocol                   = "*"
          access                     = "Deny"
          priority                   = 4096
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
    rt_dr = {
      name = "sqlmi-route-table-primary"
      location = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      bgp_route_propagation_enabled = false
      # subnet_resource_ids = {
      #   subnet1 = local.subnet_ids["."]
      # }
      routes = {
        route1 = {
          name           = "route-to-internet"
          address_prefix = "10.2.0.0/32"
          next_hop_type  = "VnetLocal"
          #next_hop_in_ip_address = "10.2.0.0/32"
        }
      }
    }
  }
}

#--------------------------------------------------------------------
# User Assigned Identity
#--------------------------------------------------------------------
locals {
  user_assigned_identities = {
    # sqlmi = {
    #   name                = "mi-sqlmi-identity"
    #   location            = data.azurerm_resource_group.rg.location
    #   resource_group_name = data.azurerm_resource_group.rg.name
    # }
    # secondary = {
    #   name                = "mi-sqlmi-identity-dr"
    #   location            = data.azurerm_resource_group.rg_dr.location
    #   resource_group_name = data.azurerm_resource_group.rg_dr.name
    # }
    function = {
      name                = "infy-test-function-identity"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
    aks = {
      name                = "mi-aks-identity"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
  }
}


#--------------------------------------------------------------------
#Key Vault configurations
#--------------------------------------------------------------------
locals {
  keyvault_configs = {
    kv = {
      name                = "kv-test-infy-110"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      sku_name           = "standard"
      soft_delete_retention_days      = 90
      purge_protection_enabled        = true
      legacy_access_policies_enabled  = false
      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true
      public_network_access_enabled   = false
      enable_telemetry                = false
      network_acls = {
        bypass         = "AzureServices"
        default_action = "Deny"
        virtual_network_subnet_refs = [
          {
            vnet_key   = "vnet_aks"
            subnet_key = "snet1"
          }
        ]
      }
      # private_endpoints = {
      #   kvpe = {
      #     name       = "pvt-endpoint-kv-test-infy-001"
      #     vnet_key   = "vnet_aks"
      #     subnet_key = "snet1"
      #     private_dns_zone_resource_ids = []
      #   }
      # }
      # diagnostic_settings = {
      #   kvdiag = {
      #     name                  = "diag-kv-test-infy-001"
      #     workspace_resource_id = try(module.law[0].resource_id, null) # if you have LA workspace
      #   }
      # }
      tags = {
        created_by = "terraform"
      }
    }
  }
}


# variable "sqlmi_adminpass" {
#   description = "Admin password for the primary SQL Managed Instance"
#   type        = string
#   sensitive   = true
#   validation {
#     condition  = length(var.sqlmi_adminpass) >= 16 && can(regex("[A-Z]", var.sqlmi_adminpass)) && can(regex("[a-z]", var.sqlmi_adminpass)) && can(regex("[0-9]", var.sqlmi_adminpass)) && can(regex("[^A-Za-z0-9]", var.sqlmi_adminpass))
#     error_message = "admin password must be at least 16 characters long and include at least one uppercase letter, one lowercase letter, one number, and one special character."
#   }
# }
locals {
  sqlmi-configs = {
    # sqlmi_primary = {
    #   name                = "sql-mk-primary-02"
    #   location            = data.azurerm_resource_group.rg.location
    #   resource_group_name = data.azurerm_resource_group.rg.name
    #   subnet_id = local.subnet_ids["vnet-primary.snetmi"]  #subnet should be delegated to Microsoft.Sql/managedInstances and nsg rules applied as per sql mi requirements
    #   administrator_login          = "sqladminuser"
    #   administrator_login_password = "Cricket@#12345678"  #var.sqlmi_adminpass
    #   sku_name                     = "GP_Gen5"
    #   vcores                       = 4
    #   storage_size_in_gb           = 128
    #   license_type                 = "LicenseIncluded"
    #   timezone_id                  = "India Standard Time"
    #   proxy_override               = "Proxy"
    #   public_data_endpoint_enabled = false
    #   minimum_tls_version          = "1.2"
    #   zone_redundant_enabled       = false
    #   user_assigned_identity_keys  = ["sqlmi"]
    #   private_endpoints_manage_dns_zone_group = true
    #   active_directory_administrator = {
    #     azuread_authentication_only = true
    #     object_id                   = data.azuread_group.ad_group.object_id
    #     tenant_id                   = data.azurerm_client_config.current.tenant_id
    #     login_username              = "infy-test"
    #   }
    #   private_endpoints = {
    #     sqlmipe = {
    #       name                          = "pvt-endpoint-sqlmi001"
    #       vnet_key                      = "vnet-primary"
    #       subnet_key                    = "snet1"
    #       subresource_name              = "managedInstance"
    #     }
    #   }
    #   # diagnostic_settings = {
    #   #   di_diag = {
    #   #     name                  = "diag-di-sqlmi-01"
    #   #     workspace_resource_id = try(module.law.resource_id, null)
    #   #   }
    #   # }
    # }
  }
  sqlmi-configs-secondary = {
    # sqlmi_dr = {
    #   name                = "sql-mk-infy-01-dr"
    #   location            = data.azurerm_resource_group.rg_dr.location
    #   resource_group_name = data.azurerm_resource_group.rg_dr.name
    #   subnet_id = local.subnet_ids["vnet-dr.snetmi"]  #subnet should be delegated to Microsoft.Sql/managedInstances and nsg rules applied as per sql mi requirements
    #   administrator_login          = "sqladminuser"
    #   administrator_login_password = var.sqlmi_adminpass
    #   sku_name                     = "GP_Gen5"
    #   vcores                       = 4
    #   storage_size_in_gb           = 128
    #   license_type                 = "LicenseIncluded"
    #   timezone_id                  = "India Standard Time"
    #   proxy_override               = "Proxy"
    #   public_data_endpoint_enabled = false
    #   minimum_tls_version          = "1.2"
    #   zone_redundant_enabled       = false
    #   user_assigned_identity_keys  = ["secondary"]
    #   private_endpoints_manage_dns_zone_group = true
    #   dns_zone_partner_id = module.sqlmi_primary["sqlmi_primary"].resource_id
    #   private_endpoints = {
    #     sqlmipe = {
    #       name                          = "pvt-endpoint-sql-mk-infy-01-dr"
    #       vnet_key                      = "vnet-dr"
    #       subnet_key                    = "snet1"
    #       subresource_name              = "managedInstance"
    #     }
    #   }
    #   diagnostic_settings = {
    #     di_diag = {
    #       name                  = "diag-di-sql-mk-infy-01-dr"
    #       workspace_resource_id = try(module.law.resource_id, null)
    #     }
    #   }
    # }
  }
}


#--------------------------------------------------------------------
# #AKS configurations
#--------------------------------------------------------------------
locals {
  aks_configs = {
    aks = {
      name = "aks-dr-014"
      resource_group_name = data.azurerm_resource_group.rg.name
      location = data.azurerm_resource_group.rg.location
      kubernetes_version         = "1.34.1"
      sku_tier                   = "Free"
      oidc_issuer_enabled        = true
      workload_identity_enabled  = true
      azure_policy_enabled       = true
      dns_prefix = "aks-dr-014"
      local_account_disabled = false
      user_assigned_identity_keys                    = ["aks"]
      private_cluster_enabled    = true                    # force replacement of the cluster if changed
      role_based_access_control_enabled = false                      # force replacement of the cluster if changed
      # azure_active_directory_role_based_access_control = {
      #   tenant_id = data.azurerm_client_config.current.tenant_id
      #   admin_group_object_ids = try([data.azuread_group.ad_group.object_id], null)
      #   azure_rbac_enabled = false                        # (false uses Microsoft entra ID authentication with kubernetes RBAC)
      # }
      default_node_pool = {
        name            = "systemnp"
        vm_size         = "standard_b2ms"
        os_disk_size_gb = 128
        os_disk_type    = "Managed"
        zones           = ["1", "2", "3"]
        min_count            = 1
        type                 = "VirtualMachineScaleSets"
        max_count            = 3
        auto_scaling_enabled = true
        max_pods             = 110
        vnet_subnet_id       = local.subnet_ids["vnet_aks.snet_aks"]
        # node_labels = {
        #   "nodepool-type" = "system"
        # }
        node_taints          = ["node=infysvc:NoSchedule"]
      }
      # node_pools = {
      #   np1 = {
      #     name    = "usernp1"
      #     vm_size = "Standard_D4s_v5"
      #     mode    = "User"
      #     min_count            = 2
      #     max_count            = 10
      #     auto_scaling_enabled = true
      #     vnet_subnet_id       = local.subnet_ids["vnet-primary.snet2"]
      #     os_sku               = "Ubuntu"
      #     os_type              = "Linux"
      #     os_disk_size_gb      = 128
      #     os_disk_type         = "Managed"
      #     max_pods             = 110
      #     # node_labels = {
      #     #   "workload" = "apps"
      #     # }
      #     node_taints          = ["node=infysvc:NoSchedule"]
      #     zones                = ["1"]    #["1", "2", "3"]
      #   }
      # }
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
      # diagnostic_settings = {
      #   di_diag = {
      #     name                  = "diag-aks-dr-001cd"
      #     workspace_resource_id = try(module.law.resource_id, null)
      #   }
      # }
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }

    }
    aks1 = {
      name = "aks-dr-owndns"
      resource_group_name = data.azurerm_resource_group.rg.name
      location = data.azurerm_resource_group.rg.location
      kubernetes_version         = "1.34.1"
      sku_tier                   = "Free"
      oidc_issuer_enabled        = true
      workload_identity_enabled  = true
      azure_policy_enabled       = true
      dns_prefix = "aks-dr-owndns"
      local_account_disabled = false
      user_assigned_identity_keys                    = ["aks"]
      private_cluster_enabled    = false                    # force replacement of the cluster if changed
      role_based_access_control_enabled = false                      # force replacement of the cluster if changed
      # azure_active_directory_role_based_access_control = {
      #   tenant_id = data.azurerm_client_config.current.tenant_id
      #   admin_group_object_ids = try([data.azuread_group.ad_group.object_id], null)
      #   azure_rbac_enabled = false                        # (false uses Microsoft entra ID authentication with kubernetes RBAC)
      # }
      default_node_pool = {
        name            = "systemnp"
        vm_size         = "standard_b2ms"
        os_disk_size_gb = 128
        os_disk_type    = "Managed"
        zones           = ["1", "2", "3"]
        min_count            = 1
        type                 = "VirtualMachineScaleSets"
        max_count            = 3
        auto_scaling_enabled = true
        max_pods             = 110
        vnet_subnet_id       = local.subnet_ids["vnet_aks.snet_aks"]
        # node_labels = {
        #   "nodepool-type" = "system"
        # }
        node_taints          = ["node=infysvc:NoSchedule"]
      }
      # node_pools = {
      #   np1 = {
      #     name    = "usernp1"
      #     vm_size = "Standard_D4s_v5"
      #     mode    = "User"
      #     min_count            = 2
      #     max_count            = 10
      #     auto_scaling_enabled = true
      #     vnet_subnet_id       = local.subnet_ids["vnet-primary.snet2"]
      #     os_sku               = "Ubuntu"
      #     os_type              = "Linux"
      #     os_disk_size_gb      = 128
      #     os_disk_type         = "Managed"
      #     max_pods             = 110
      #     # node_labels = {
      #     #   "workload" = "apps"
      #     # }
      #     node_taints          = ["node=infysvc:NoSchedule"]
      #     zones                = ["1"]    #["1", "2", "3"]
      #   }
      # }
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
      # diagnostic_settings = {
      #   di_diag = {
      #     name                  = "diag-aks-dr-001cd"
      #     workspace_resource_id = try(module.law.resource_id, null)
      #   }
      # }
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
        rg_name     = vnet.resource_group_name
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

