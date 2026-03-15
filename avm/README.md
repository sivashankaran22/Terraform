"# avm_terraform" 
# Working code up to vnet, snet, nsg, nsg security rules and its data sources
## Working code for law
# Working code for key vault, its pe, diag
# Working code for storage, its pe, diag. blob_properties and immutability_policy added.
# Working code for function app, app service plan, vnet integration, diag, user identity integation
# User assigned identity
# Application Insights
# Working code upto aml_worksapce with pe, diag and system managed identity
# working code for Document Intelligence with pe and diag settings
# working code for openai with pe and diag settings
# working code for request unit database cosmosdb with diag settings, with pe and user identity
# AVM for private endpoint added.
# AVM and data block for private dns zone
# AVM for roleassignment

#####################################################################################################

# Terraform AVM Azure Platform – Full Repository Documentation (with Complete Config Examples)

This repository provisions Azure resources using **Azure Verified Modules (AVM)**. AVM modules are Microsoft-validated, standardized building blocks designed to be composable and aligned to best practices. (https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/)

The repo is designed to be:
- **Toggle-driven** (`enable_*` flags)
- **Create-or-use-existing** for key resources (VNet, Subnets, NSG, Private DNS Zone)
- **Private-by-default** for PaaS components (private endpoints + public network disabled where configured)

---

## What this repository can deploy (feature set)

Based on your `locals.tf` + `main.tf` + `test.auto.tfvars`, this repo can deploy:

### Networking
- Virtual Network + Subnets (create new OR reference existing)
- NSGs (create new OR reference existing)
- NSG association to subnets (via `subnet_configs[*].nsg_key`)
- Subnet delegation (Function App / App Service delegation)

### Security & Data
- Key Vault(s) (private endpoints + network ACL subnet restrictions)
- Storage Account(s) (OAuth-only, private endpoints, immutability policy)
- Cosmos DB account with Mongo capability (geo-replication + private endpoint)

### Application Platform
- App Service Plan
- Function App (Linux) with VNet integration + UAMI

### AI / ML / Cognitive
- Azure ML Workspace (private, managed network, references KV/Storage/AppInsights)
- Cognitive Services: Document Intelligence + Azure OpenAI (private endpoints)

### Observability
- Log Analytics Workspace (optional)
- Diagnostic settings blocks for KV, Storage (blob), AML, Cognitive Services, Cosmos

### IAM / RBAC
- User Assigned Managed Identities (UAMI)
- Role Assignments (Storage Blob Data Contributor to UAMI)

### Private Connectivity
- Private DNS zones (create new OR reference existing)
- Private endpoints (resource modules + optional standalone private endpoint module)

---

## 1. Repository Structure

### `test.auto.tfvars`
Environment toggles that enable/disable modules. Terraform `*.auto.tfvars`.

# NETWORKING
enable_virtual_networks = true/false
enable_nsg              = true/false

# STORAGE
enable_storage_account = true/false

# MONITORING
enable_log_analytics_workspace = true/false
enable_application_insights    = true/false

# SECURITY
enable_kv                      = true/false
enable_user_assigned_identities = true/false

# APPLICATION PLATFORM
enable_function_app     = true/false
enable_app_service_plan = true/false
enable_aml_workspace    = true/false
enable_cognitiveservices = true/false
enable_cosmosdb_account  = true/false

# ACCESS CONTROL
enable_role_assignments = true/false

# PRIVATE NETWORKING
enable_private_dns_zone  = true/false
enable_private_endpoints = true/false


### `locals.tf`
All resource configurations are stored as maps:
- `virtual_networks`
- `nsg_configs`
- `keyvault_configs`
- `storage_account_configs`
- `function_app_configs`
- `app_service_plan`
- `aml_workspace`
- `user_assigned_identities`
- `app_insights_configs`
- `cognitiveservices`
- `cosmosdb_account_configs`
- `private_dns_zones` + `private_dns_ids`

# - `virtual_networks`
#  Full example: locals.virtual_networks
How module works (main.tf behavior)
change enable_virtual_networks = true 

For create_vnet=true → AVM VNet module runs.
For create_vnet=false → data sources fetch VNet + subnets.
local.subnet_ids merges created + existing subnet IDs so downstream resources can use:

"${vnet_key}.${subnet_key}" → e.g. "vnet1_manual.snet1"

locals {
  virtual_networks = {
    # -------------------------------
    # CREATE NEW VNET
    # -------------------------------
    vnet1 = {
      create_vnet            = true
      name                   = "vent-name"
      location               = "centralindia"
      address_space          = ["101.122.96.0/24"]
      enable_ddos_protection = false
      # Optional (module input requires special shaping in main.tf)
      dns_servers = ["168.63.129.16"]
      tags = {
        created_by = "terraform"
      }
      subnet_configs = {
        snet1 = {
          name              = "snet1-test"
          address_prefix    = ["101.122.96.0/28"]
          service_endpoints = ["Microsoft.KeyVault"]
          nsg_key           = "nsg1"
        }
        snet2 = {
          name           = "snet2-test"
          address_prefix = ["101.122.96.64/28"]
          nsg_key        = "nsg2"
        }
        snet3 = {
          name              = "snet3-test"
          address_prefix    = ["101.122.96.32/28"]
          service_endpoints = ["Microsoft.Web"]
          nsg_key           = "nsg2"

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
    # -------------------------------
    # B. USE EXISTING VNET + SUBNETS
    # -------------------------------
    vnet1_manual = {
      create_vnet         = false
      name                = "vnet1-manual"
      resource_group_name = data.azurerm_resource_group.rg.name

      existing_subnets = {
        snet1 = { name = "snet1-manual" }
        snet2 = { name = "snet2-manual" }
      }
    }
  }
}

# - `nsg_configs`
# Full example: locals.nsg_configs
How module works (main.tf behavior)
change enable_nsg = true 

For create_nsg=true → AVM nsg module runs.
For create_nsg=false → data sources fetch nsg configuration.

locals {
  nsg_configs = {
    # -------------------------------
    # CREATE NEW NSG
    # -------------------------------
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
    # -------------------------------
    # B. USE EXISTING NSG
    # -------------------------------
    nsg2 = {
      create_nsg = false
      nsg_name   = "nsg-infy-manual"
      rg_name    = data.azurerm_resource_group.rg.name
    }
  }
}

# - `keyvault_configs`
# Full example: locals.keyvault_configs
How module works (main.tf behavior)
1.set the value of enable_kv = true to create kv using below configuration.
2.keep private_endpoints block if private end point required. or remove the block if private_endpoints not required for kv.
3.keep diagnostic_settings block if private end point required. or remove the block if diagnostic_settings not required for kv.


locals {
  keyvault_configs = {

    kv = {
      name                = "kv-name"
      location            = "centralindia"
      resource_group_name = data.azurerm_resource_group.rg.name
      sku_name           = "standard"
      soft_delete_retention_days      = 7
      purge_protection_enabled        = false
      legacy_access_policies_enabled  = false

      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true

      public_network_access_enabled   = false
      enable_telemetry                = false

      network_acls = {
        bypass         = "AzureServices"
        default_action = "Deny"

        # converted to subnet IDs in main.tf
        virtual_network_subnet_refs = [
          { vnet_key = "vnet1", subnet_key = "snet1" }
        ]
      }
      private_endpoints = {
        kvpe = {
          name       = "private-endpoint-name"
          vnet_key   = "vnet1"
          subnet_key = "snet1"
          private_dns_zone_resource_ids = []
          tags = null
        }
      }
      diagnostic_settings = {
        kvdiag = {
          name                  = "diag-name."
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

# - `storage_account_configs`
# Full example: locals.storage_account_configs
1.set the value of enable_storage_account = true to create the storage account resource
2.keep private_endpoints block if private end point required. or remove the block if private_endpoints not required for storage account.
3.keep diagnostic_settings block if private end point required. or remove the block if diagnostic_settings not required for storage account.
4.keep blob_properties block if required, or remove if not required
5.keep immutability_policy block if required, or remove if not required

locals {
  storage_account_configs = {
    st = {
      name                              = "storage-name"
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
      shared_access_key_enabled         = false
      enable_telemetry                  = false
      blob_properties = {
        versioning_enabled = true
        container_delete_retention_policy = {
          enabled = true
          days    = 7
        }
        delete_retention_policy = {
          days                    = 7
          permanent_delete_enabled = true
        }
      }
      immutability_policy = {
        allow_protected_append_writes = false
        period_since_creation_in_days = 30
        state                        = "Unlocked"
      }
      # converted to subnet IDs in main.tf
      network_rules_subnet_refs = [
        { vnet_key = "vnet1_manual", subnet_key = "snet1" }
      ]
      private_endpoints = {
        stpe = {
          name                          = "private-endpoint-name"
          vnet_key                      = "vnet1_manual"
          subnet_key                    = "snet1"
          subresource_name              = "blob"
          private_dns_zone_resource_ids = [local.private_dns_ids["storage"]]
          tags                          = { env = "test" }
        }
      }
      diagnostic_settings_blob = {
        stdiag = {
          name                  = "diag-name"
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

# - `function_app_configs`
# Full example: locals.function_app_configs
1.set the value of enable_function_app = true to create the function app resource using avm
2.service_plan_resource_id required. So, make sure to provision app service plan.
3.keep app_settings block if required.

locals {
  function_app_configs = {
    function = {
      name                                           = "name-of-function-app"
      location                                       = data.azurerm_resource_group.rg.location
      resource_group_name                            = data.azurerm_resource_group.rg.name
      kind                                           = "functionapp"
      os_type                                        = "Linux"
      https_only                                     = true
      service_plan_resource_id                       = try(module.avm-res-web-serverfarm["plan1"].resource_id, null)
      storage_account_name                           = try(module.avm-res-storage-storageaccount["st1"].name, null)
      public_network_access_enabled                  = false
      enable_application_insights                    = false
      virtual_network_subnet_id                      = try(local.subnet_ids["vnet1_manual.snet2"], null)
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
      }
      tags = {
        environment = "testing"
        created_by  = "terraform"
      }
    }
  }
}

# - `app_service_plan`
# Full example: locals.app_service_plan
1.set the value of enable_app_service_plan = true to create the app service plan resource using avm
locals {
  app_service_plan = {
    plan1 = {
      name                = "app-service-plan-name"
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

# - `aml_workspace`
# Full example: locals.aml_workspace
1.set the value of enable_aml_workspace = true to create the aml workspace resource using avm
2.AML required storage account, keyvault and applisights. provide application_insights_key, storage_account_key and key_vault_key ket names.
3.keep private_endpoints block if private end point required or remove if not required
4.keep diagnostic_settings block if private end point required or remove if not required


locals {
  aml_workspace = {
    aml1 = {
      name                          = "aml-name"
      location                      = data.azurerm_resource_group.rg.location
      resource_group_name           = data.azurerm_resource_group.rg.name
      enable_telemetry              = false
      public_network_access_enabled = false
      application_insights_key      = "app_insights1"
      key_vault_key                 = "kv2"
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
          name                          = "pe-name"
          vnet_key                      = "vnet1_manual"
          subnet_key                    = "snet1"
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        amldiag = {
          name                  = "diag-name"
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

# - `cognitiveservices`
# Full example: locals.cognitiveservices
1.set the value of enable_cognitiveservices = true to Creates Azure Cognitive Services account (Document Inteligent and Azure OpenAI) resource using avm.
2.Set the enable_account = true to create Document Inteligent using below cofiguration
3.keep private_endpoints block if private end point required or remove if not required
4.keep diagnostic_settings block if private end point required or remove if not required

locals {
  cognitiveservices = {

    di = {
      enable_account = true
      name      = "di-name"
      parent_id = data.azurerm_resource_group.rg.id
      location  = data.azurerm_resource_group.rg.location
      sku_name  = "S0"
      kind      = "FormRecognizer"
      enable_telemetry                = false
      local_auth_enabled              = false
      public_network_access_enabled   = false
      private_endpoints = {
        di_pe = {
          name       = "pvt-endpoint-di-claims-test-poc"
          vnet_key   = "vnet1_manual"
          subnet_key = "snet1"
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        di_diag = {
          name                  = "diag-di-claims-test-001"
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }

2.Set the enable_account = true to create Azure OpenAI using below cofiguration
3.keep private_endpoints block if private end point required or remove if not required
4.keep diagnostic_settings block if private end point required or remove if not required

    openai = {
      enable_account = true
      name      = "open-ai-name"
      parent_id = data.azurerm_resource_group.rg.id
      location  = "South India"
      sku_name  = "S0"
      kind      = "OpenAI"
      enable_telemetry                = false
      local_auth_enabled              = false
      public_network_access_enabled   = false
      private_endpoints = {
        openai_pe = {
          name       = "pvt-endpoint-name
          vnet_key   = "vnet1_manual"
          subnet_key = "snet1"
          location   = data.azurerm_resource_group.rg.location
          private_dns_zone_resource_ids = []
        }
      }
      diagnostic_settings = {
        openai_diag = {
          name                  = "diag-name"
          workspace_resource_id = try(module.law[0].resource_id, null)
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

# - `cosmosdb_account_configs`
# Full example: locals.cosmosdb_account_configs
1.set the value of enable_cosmosdb_account = true to create the cosmosdb resource using avm
2.keep private_endpoints block if private end point required or remove if not required
3.keep diagnostic_settings block if private end point required or remove if not required

locals {
  cosmosdb_account_configs = {
    cosmosdb = {
      name                         = "cosmosdb-name"
      location                     = data.azurerm_resource_group.rg.location
      resource_group_name          = data.azurerm_resource_group.rg.name
      enable_telemetry             = false
      public_network_access_enabled = false
      minimal_tls_version          = "Tls12"

      backup = {
        type = "Continuous"
        tier = "Continuous30Days"
      }
      mongo_server_version = "4.0"
      mongo_databases = {
        claimsdb = {
          name       = "claimsdb"
          throughput = 400
        }
      }
      geo_locations = [
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
          name                          = "pvt-endpoint-name"
          vnet_key                      = "vnet1_manual"
          subnet_key                    = "snet1"
          subresource_name              = "MongoDB"
          private_dns_zone_resource_ids = [local.private_dns_ids["cosmosdb"]]
        }
      }
      diagnostic_settings = {
        cosmos_diag = {
          name                  = "diag-name"
          workspace_resource_id = try(module.law[0].resource_id, null)
          metric_categories     = ["SLI", "Requests"]
        }
      }
      tags = {
        created_by = "terraform"
      }
    }
  }
}

# - `user_assigned_identities`
# Full example: locals.user_assigned_identities
1.set the value of enable_user_assigned_identities = true to Creates User Assigned Managed Identity (UAMI) using avm

locals {
  user_assigned_identities = {
    function = {
      name                = "identity-name"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
    }
  }
}

# - `app_insights_configs`
# Full example: locals.app_insights_configs
1.set the value of enable_application_insights = trueto Creates an Application Insights instance usinf avm
2.Log analytics worspace id required to provision appinsights

locals {
  app_insights_configs = {
    app_insights1 = {
      name                = "appinsights-name"
      location            = data.azurerm_resource_group.rg.location
      resource_group_name = data.azurerm_resource_group.rg.name
      workspace_id        = try(module.law[0].resource_id, null)
      tags = {
        created_by = "terraform"
      }
    }
  }
}

# - `private_dns_zones`
# Full example: locals.private_dns_zones
1.set the value of enable_private_dns_zone = true to Enable private dns zone to create or use existing.
2.set the value of create_private_dns_zone =  true to create new dns zone.
3.set the value of create_private_dns_zone =  false to import existing dns zone.
4.provide vnet details for virtual network integration.

locals {
  private_dns_zones = {
    cosmosdb = {
      create_private_dns_zone = true
      private_dns_zone_name   = "privatelink.mongo.cosmos.azure.com"
      vnet_id                 = local.vnet_ids["vnet1_manual"]
    }
    storage = {
      create_private_dns_zone = false
      private_dns_zone_name   = "privatelink.blob.core.windows.net"
      resource_group_name     = data.azurerm_resource_group.rg.name
    }
  }
  private_dns_ids = merge(
    { for k, m in module.avm-res-network-privatednszone : k => m.resource_id },
    { for k, d in data.azurerm_private_dns_zone.existing : k => d.id }
  )
}

# - `Log_analytics_worspace`
1.set the value of enable_log_analytics_workspace = true to Creates a Log Analytics workspace using avm

module "law" {
  source                                    = "Azure/avm-res-operationalinsights-workspace/azurerm"
  count                                     = var.enable_log_analytics_workspace ? 1 : 0
  version                                   = "0.4.2"
  name                                      = "worspace-name"
  location                                  = data.azurerm_resource_group.rg.location
  resource_group_name                       = data.azurerm_resource_group.rg.name
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_retention_in_days = 30
  enable_telemetry                          = false
  tags = {
    created_by = "terraform"
  }
}



### `main.tf`
Contains:
- AVM module calls
- Data sources for existing resources
- Transformations of locals → module input shapes
- Merge logic for IDs (created + existing)
- RBAC role assignment module

### `providers.tf`
Terraform and provider version constraints + AzureRM provider configuration.
1.tenant_id and subscription_id will fetech from github enavironment secrest.
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
  features {}
  storage_use_azuread = true
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
data "azurerm_client_config" "current" {}
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
}
variable "tenant_id" {
  type        = string
  description = "Azure tenant ID."
}


---

## 2. How to Run

```bash
terraform fmt -recursive
terraform validate
terraform init
terraform plan
terraform apply
