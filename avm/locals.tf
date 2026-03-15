#--------------------------------------------------------------------
# Virtual Network and Subnet configurations
#--------------------------------------------------------------------
locals {
  virtual_networks = {
    vnet1 = {
      create_vnet            = true
      name                   = "vent-name"
      location               = "centralindia"
      address_space          = ["10.0.0.0/16"]
      enable_ddos_protection = false
      dns_servers            = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
      }

      subnet_configs = {
        snet1 = {
          name              = "snet1-test"
          address_prefix    = ["10.0.1.0/24"]
          service_endpoints = ["Microsoft.KeyVault", "Microsoft.Storage", "Microsoft.AzureCosmosDB"]
          nsg_key           = "nsg1"
        }

        snet2 = {
          name           = "snet2-test"
          address_prefix = ["10.0.2.0/24"]
          nsg_key        = "nsg1"
        }

        snet3 = {
          name              = "snet3-test"
          address_prefix    = ["10.0.3.0/24"]
          service_endpoints = ["Microsoft.Web"]
          nsg_key           = "nsg1"

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
    nsg1 = {
      create_nsg = true
      nsg_name   = "nsg-infy-test"
      location   = data.azurerm_resource_group.rg.location
      rg_name    = data.azurerm_resource_group.rg.name

      security_rules = [
        {
          name                       = "Allow-InBound"
          priority                   = 500
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefix      = "*"
          destination_address_prefix = "VirtualNetwork"
          source_port_range          = "*"
          destination_port_range     = "443"
        }
      ]
      tags = {
        created_by = "terraform"
      }
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
      location            = "centralindia"
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
            vnet_key   = "vnet1"
            subnet_key = "snet1"
          }
        ]
      }
      private_endpoints = {
        kvpe = {
          name       = "pvt-endpoint-kv-test-infy-001"
          vnet_key   = "vnet1"
          subnet_key = "snet2"
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        kvdiag = {
          name                  = "diag-kv-test-infy-001"
          workspace_resource_id = try(module.law[0].resource_id, null) # if you have LA workspace
        }
      }
      tags = {
        created_by = "terraform"
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
      name                              = "avmtest00001"
      resource_group_name               = data.azurerm_resource_group.rg.name
      location                          = data.azurerm_resource_group.rg.location
      account_tier                      = "Standard"
      account_replication_type          = "LRS"
      access_tier                       = "Hot"
      account_kind                      = "StorageV2"
      allow_nested_items_to_be_public   = false
      default_to_oauth_authentication   = true
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
          vnet_key   = "vnet1"
          subnet_key = "snet1"
        }
      ]
      private_endpoints = {
        stpe = {
          name                          = "pe-st003testinfy-blob"
          vnet_key                      = "vnet1"
          subnet_key                    = "snet2"
          subresource_name              = "blob"
          tags                          = { env = "test" }
        }
      }
      diagnostic_settings_blob = {
        stdiag = {
          name                  = "diag-sttestinfytest001-blob"
          workspace_resource_id = try(module.law[0].resource_id, null)
          metric_categories     = ["Transaction", "Capacity"]
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
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
      os_type                                        = "Linux"
      https_only                                     = true
      service_plan_resource_id                       = try(module.avm-res-web-serverfarm["plan1"].resource_id, null)
      storage_account_name                           = try(module.avm-res-storage-storageaccount["st1"].name, null)
      public_network_access_enabled                  = false
      enable_application_insights                    = false
      virtual_network_subnet_id                      = try(local.subnet_ids["vnet1.snet3"], null)
      ftp_publish_basic_authentication_enabled       = false
      webdeploy_publish_basic_authentication_enabled = false
      user_assigned_identity_keys                    = ["function"]
      enable_telemetry                               = false
      site_config = {
        always_on        = false
        app_insights_key = "app_insights1"
        application_stack = {
          java = { java_version = "21" }
        }
      }
      app_settings = {
        FUNCTIONS_WORKER_RUNTIME = "java"
        JAVA_VERSION             = "21"
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
# App Service Plan configurations
#--------------------------------------------------------------------
locals {
  app_service_plan = {
    plan1 = {
      name                = "infy-claims-functions-plan"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      sku_name            = "P1v2"
      os_type             = "Linux"
      enable_telemetry    = false
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# AML Workspace Configurations
#--------------------------------------------------------------------
locals {
  aml_workspace = {
    aml1 = {
      name                          = "mlw-claims-test-001"
      location                      = data.azurerm_resource_group.rg.location
      resource_group_name           = data.azurerm_resource_group.rg.name
      enable_telemetry              = false
      public_network_access_enabled = false
      application_insights_key      = "app_insights1"
      key_vault_key                 = "kv"
      storage_account_key           = "st1"
      workspace_managed_network = {
        isolation_mode = "AllowOnlyApprovedOutbound"
        firewall_sku   = "Basic"
      }
      managed_identities = {
        system_assigned = true
      }
      private_endpoints = {
        amlpe = {
          name                          = "pe-mlw-claims-test-001"
          vnet_key                      = "vnet1"
          subnet_key                    = "snet2"
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        amldiag = {
          name                  = "diag-mlw-claims-test-001"
          workspace_resource_id = try(module.law[0].resource_id, null) # if you have LA workspace
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# User Assigned Identity configurations
#--------------------------------------------------------------------
locals {
  user_assigned_identities = {
    function = {
      name                = "infy-test-function-identity"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
    cosmosdb = {
      name                = "mannaged_identity_cosdb-cind-test"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
  }
}
#--------------------------------------------------------------------
# Application Insights configurations
#--------------------------------------------------------------------
locals {
  app_insights_configs = {
    app_insights1 = {
      name                = "infy-claims-appinsights"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      workspace_id        = try(module.law[0].resource_id, null)
      tags = {
        created_by = "terraform"
      }
    }
  }
}
#--------------------------------------------------------------------
# Cognitive Services Account configuration
#--------------------------------------------------------------------
locals {
  cognitiveservices = {
    #----------------------------------------------------------------
    # Document Intelligence
    #----------------------------------------------------------------
    di1 = {
      enable_account = true
      name      = "di-claims-test-002"
      parent_id = data.azurerm_resource_group.rg.id
      location  = data.azurerm_resource_group.rg.location
      sku_name  = "S0"
      kind      = "FormRecognizer"
      enable_telemetry = false
      local_auth_enabled = false
      public_network_access_enabled = false
      private_endpoints = {
        di_pe = {
          name       = "pvt-endpoint-di-claims-test-poc"
          vnet_key   = "vnet1"
          subnet_key = "snet2"
          # If you already have private DNS zone ids, place them here; otherwise keep empty.
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        di_diag = {
          name                  = "diag-di-claims-test-002"
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
    #----------------------------------------------------------------
    # Azure Open AI
    #----------------------------------------------------------------
    openai = {
      enable_account = true
      name      = "cind-oai-claims-test001"
      parent_id = data.azurerm_resource_group.rg.id
      location  = "South India"
      sku_name  = "S0"
      kind      = "OpenAI"
      enable_telemetry = false
      local_auth_enabled = false
      public_network_access_enabled = false
      private_endpoints = {
        openai_pe = {
          name       = "pvt-endpoint-cind-oai-claims-test001"
          vnet_key   = "vnet1"
          subnet_key = "snet2"
          location   = data.azurerm_resource_group.rg.location
          # If you already have private DNS zone ids, place them here; otherwise keep empty.
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        openai_diag = {
          name                  = "diag-cind-oai-claims-test001"
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# Cosmos DB Account configuration
#--------------------------------------------------------------------
locals {
  cosmosdb_account_configs = {
    cosmosdb1 = {
      name                = "cosdb005-cind-claims-test"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      enable_telemetry    = false
      public_network_access_enabled = false
      minimal_tls_version = "Tls12"
      user_assigned_identity_keys = ["cosmosdb"]
      backup = {
        type = "Continuous"
        tier = "Continuous30Days"
      }
      mongo_server_version = "4.0"
      mongo_databases = {  #With AVM, the module decides MongoDB mode using mongo_databases. So, you’d have to provide at least one database entry.
        claimsdb = {
          name       = "claimsdb"
          throughput = 400
        }
      }
      geo_locations = [   #geo replication: primary = RG location, failover = South India
        {
          location          = data.azurerm_resource_group.rg.location
          failover_priority = 0
          zone_redundant    = false
        },
        {
          location          = "South India"
          failover_priority = 1
          zone_redundant    = false
        }
      ]
      private_endpoints_manage_dns_zone_group = true
      private_endpoints = {
        cosmospe = {
          name                          = "pvt-endpoint-cosdb005-cind-claims-test"
          vnet_key                      = "vnet1"
          subnet_key                    = "snet2"
          subresource_name              = "MongoDB"
          #private_dns_zone_resource_ids = [local.private_dns_ids["cosmosdb"]]
        }
      }
      diagnostic_settings = {
        cosmos_diag = {
          name                  = "diag-cosdb005-cind-claims-test"
          workspace_resource_id = try(module.law[0].resource_id, null) # if you have LA workspace
          metric_categories     = ["SLI", "Requests"]
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

#--------------------------------------------------------------------
# Private DNS zone avm module to create and data block to use existing.
#--------------------------------------------------------------------
locals {
  private_dns_zones = {
    cosmosdb = {
      create_private_dns_zone = true
      private_dns_zone_name = "privatelink.mongo.cosmos.azure.com"
      vnet_id               = try(local.vnet_ids["vnet1"], null)
    }
    storage = {
      create_private_dns_zone = false
      private_dns_zone_name = "privatelink.blob.core.windows.net"
      resource_group_name = data.azurerm_resource_group.rg.name
    }
  }
  private_dns_ids = merge(
    { for k, m in module.avm-res-network-privatednszone : k => m.resource_id },
    { for k, d in data.azurerm_private_dns_zone.existing : k => d.id }
  )
}