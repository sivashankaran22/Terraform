
#############################################
# PROVIDER CONTEXT (not a Portal tab, but required)
#############################################
# subscription_id = "<sub-guid>"   # Azure Subscription GUID
# tenant_id       = "<tenant-guid>" # Entra Tenant GUID


#############################################
# TAGS (Portal: Tags)
# Tags are name/value pairs used for cost, ownership, filtering.
#############################################
tags = {
  env        = "test"        # Recommended: test/prod/preprod
  created_by = "terraform"
  workload   = "claims"

  # Optional examples:
  # costcenter = "CC1234"
  # owner      = "team-alias"
  # app        = "claims"
}


#############################################
# RESOURCE GROUP (Portal: Basics + Tags)
#############################################
resource_group = {
  create   = false              # true => create RG, false => use existing RG
  name     = "madan-test"
  location = "centralindia"    # only required when create=true

  # Optional:
  # tags = { purpose = "claims-iac" }
}


#############################################
# LOG ANALYTICS WORKSPACE (Portal: Basics + Pricing tier + Usage/Retention)
#############################################
log_analytics = {
  create            = true
  name              = "law-claims-test-cind"
  retention_in_days = 30       # Common values: 30/60/90/120/365 etc.

  # Optional:
  # location = "centralindia"
  sku = "PerGB2018"          # Common: PerGB2018
  tags = { monitoring = "enabled" }
}


#############################################
# APPLICATION INSIGHTS (Portal: Basics + Workspace-based + Sampling + Retention)
#############################################
application_insights = {
  create           = true
  name             = "appi-claims-test-cind"
  application_type = "web"     # Common: web, other

  # Optional portal-like knobs (commonly configured):
  retention_in_days     = 30
  sampling_percentage   = 100
  disable_ip_masking    = false
  internet_ingestion_on = true
  internet_query_on     = true
  tags = { appinsights = "enabled" }
}


#############################################
# VIRTUAL NETWORK (Portal: Basics + IP addresses + DNS + Subnets)
#############################################
virtual_networks = {
  vnet1 = {
    create        = true
    name          = "cind-claims"
    location      = "centralindia"

    # Portal: IP addresses
    address_space = ["100.122.96.0/24"]

    # Portal: DNS servers
    # Use Azure-provided DNS: 168.63.129.16 (common default in Azure) or custom DNS.
    dns_servers   = ["168.63.129.16"]

    # Portal: Subnets
    subnets = {
      subnet1 = {
        name              = "cind-pvt"
        address_prefixes  = ["100.122.96.0/27"]

        # Portal: Service endpoints (optional)
        # Common options you used: Microsoft.Storage, Microsoft.KeyVault, Microsoft.Web, Microsoft.AzureCosmosDB
        service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]

        # Portal: Delegation (optional)
        delegation        = null
      }

      subnet2 = {
        name              = "cind-cosmosdb"
        address_prefixes  = ["100.122.96.32/28"]
        service_endpoints = ["Microsoft.AzureCosmosDB"]
        delegation        = null
      }

      subnet3 = {
        name              = "cind-aiservice"
        address_prefixes  = ["100.122.96.48/28"]
        service_endpoints = null
        delegation        = null
      }

      subnet4 = {
        name              = "cind-funtionsapp"
        address_prefixes  = ["100.122.96.64/28"]
        service_endpoints = ["Microsoft.Storage", "Microsoft.Web"]

        # Portal: Subnet delegation (used by App Service / Functions VNet integration scenarios)
        delegation = {
          name = "functionapp"
          service_delegation = {
            name    = "Microsoft.Web/serverFarms"
            actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
          }
        }
      }

      # Dedicated subnet for Private Endpoints (common pattern)
      subnet_pe = {
        name              = "snet-private-endpoints"
        address_prefixes  = ["100.122.96.128/27"]
        service_endpoints = null
        delegation        = null
      }
    }
  }
}


#############################################
# NSG (Portal: Inbound rules / Outbound rules)
#############################################
nsgs = {
  nsg1 = {
    create = true
    name   = "nsg-claims-test-cind"

    # Portal: Inbound security rules
    security_rules = [
      {
        name                       = "Allow-InBound-443"
        priority                   = 500       # 100–4096, lower wins
        direction                  = "Inbound" # Inbound|Outbound
        access                     = "Allow"   # Allow|Deny
        protocol                   = "Tcp"     # Tcp|Udp|Icmp|Esp|Ah|*
        source_address_prefix      = "*"       # CIDR, *, ServiceTag, VirtualNetwork, Internet, etc.
        destination_address_prefix = "VirtualNetwork"
        source_port_range          = "*"
        destination_port_range     = "443"     # single "443" or range "1024-65535"
      }
    ]

    # Optional tags:
    # tags = { security = "baseline" }
  }
}

# Portal: Subnet -> NSG association
nsg_associations = {
  assoc1 = {
    vnet_key   = "vnet1"
    subnet_key = "subnet1"
    nsg_key    = "nsg1"
  }
}


#############################################
# PRIVATE DNS ZONES (Portal: Private DNS zones + Virtual network links)
#############################################
private_dns_zones = {
  # Storage Blob private link zone (for PE to blob)
  storage_blob = {
    name      = "privatelink.blob.core.windows.net"
    vnet_keys = ["vnet1"]
  }

  # Key Vault private link zone (for PE to vault)
  keyvault = {
    name      = "privatelink.vaultcore.azure.net"
    vnet_keys = ["vnet1"]
  }

  # Optional if you use Azure Files:
  # storage_file = {
  #   name      = "privatelink.file.core.windows.net"
  #   vnet_keys = ["vnet1"]
  # }
}


#############################################
# USER ASSIGNED MANAGED IDENTITY (Portal: Basics + Tags)
#############################################
user_assigned_identities = {
  id1 = { name = "uami-claims-test" }

  # Optional:
  # id2 = { name = "uami-claims-prod", location="centralindia", tags={env="prod"} }
}


################################################################################
# STORAGE ACCOUNT (Portal tabs: Basics / Advanced / Networking / Data protection / Encryption / Tags)
#
# Portal experience & common choices described here: tabs & fields are consistent across guides:
# - Tabs order shown in [[CUSTOMER] - ROOMS - Blob Storage Setup Guide.docx](https://microsoft.sharepoint.com/teams/IPForumTeams/_layouts/15/Doc.aspx?sourcedoc=%7B6C8D5AE9-2088-4082-B805-BD68D673FD89%7D&file=[CUSTOMER]%20-%20ROOMS%20-%20Blob%20Storage%20Setup%20Guide.docx&action=default&mobileredirect=true&DefaultItemOpen=1&EntityRepresentationId=7df2409c-0fd6-4f1c-b34e-6986fec3d428) [1](https://microsoft.sharepoint.com/teams/IPForumTeams/_layouts/15/Doc.aspx?sourcedoc=%7B6C8D5AE9-2088-4082-B805-BD68D673FD89%7D&file=[CUSTOMER]%20-%20ROOMS%20-%20Blob%20Storage%20Setup%20Guide.docx&action=default&mobileredirect=true&DefaultItemOpen=1)
# - Advanced & Networking fields explained in Learn: [2](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)[3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)
################################################################################
storage_accounts = {
  sa1 = {
    #################################
    # Basics tab
    #################################
    name                     = "stcindclaims0011"
    account_replication_type = "LRS"   # Common: LRS | ZRS | GRS | RAGRS | GZRS | RAGZRS (depends on region)

    # Optional basics you can add if your code supports them:
    # location     = "centralindia"
    account_kind = "StorageV2"       # Common: StorageV2, BlockBlobStorage, FileStorage
    account_tier = "Standard"        # Standard / Premium
    access_tier  = "Hot"             # Hot / Cool (standard GPv2)

    #################################
    # Advanced tab (Security + access)
    #################################
    advanced = {
      # Security (common)
      min_tls_version                   = "TLS1_2"  # TLS1_0, TLS1_1, TLS1_2 (TLS1_2 recommended)
      enable_https_traffic_only         = true      # “Secure transfer required” (HTTPS only) [2](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)[3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)
      shared_access_key_enabled         = false     # “Enable storage account key access” (Shared Key) [2](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)[3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)
      allow_blob_public_access          = false     # “Allow enabling anonymous access on individual containers” [2](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create)[3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)
      allow_nested_items_to_be_public   = false     # blocks nested public access
      infrastructure_encryption_enabled = true      # “Enable infrastructure encryption” (double encryption) [6](https://microsoft.sharepoint.com/teams/infoprotect-cc/_layouts/15/Doc.aspx?sourcedoc=%7B36FA84D2-14D4-4D81-93F3-03CE8387B24D%7D&file=Evidence%20Collection%20in%20DLP.docx&action=default&mobileredirect=true&DefaultItemOpen=1)[8](https://microsoft.sharepoint.com/teams/Azure_IaaS_Technical_Support/_layouts/15/Doc.aspx?sourcedoc=%7B81FE843A-4549-41A7-8837-9FFE09AC24DD%7D&file=Azure%20Storage.pptx&action=edit&mobileredirect=true&DefaultItemOpen=1)

      # Optional (enable only if you need them; may require extra wiring in code):
      is_hns_enabled                    = false     # Data Lake Storage Gen2 (hierarchical namespace)
      nfsv3_enabled                     = false     # NFS 3.0 (Azure Files / Blob NFS scenarios)
      sftp_enabled                      = false     # SFTP support for Blob (if needed)
      local_user_enabled                = false     # local users for SFTP (if enabled)
    }

    #################################
    # Networking tab
    #################################
    networking = {
      # Portal Network access options: enable all / selected / disable public & use private access [1](https://microsoft.sharepoint.com/teams/IPForumTeams/_layouts/15/Doc.aspx?sourcedoc=%7B6C8D5AE9-2088-4082-B805-BD68D673FD89%7D&file=[CUSTOMER]%20-%20ROOMS%20-%20Blob%20Storage%20Setup%20Guide.docx&action=default&mobileredirect=true&DefaultItemOpen=1)[3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)
      public_network_access_enabled = false  # false ≈ "Disable public access and use private access"

      # Firewall & virtual networks (when public endpoint is enabled or selected networks)
      default_action = "Deny"                # Allow | Deny  (Note: Overview blade may differ from actual publicNetworkAccess) [9](https://Supportability.visualstudio.com/3c8a2634-09bc-48d9-b703-6a6720e61bf9/_wiki/wikis/5ca46334-40ed-41fb-a549-178ed2cc30ae/2185778)
      bypass         = ["AzureServices"]     # Common: ["AzureServices"]
      ip_rules       = []                   # list of allowed public IP CIDRs
      subnet_ids     = []                   # list of allowed subnet IDs (optional if using firewall rules)
    }

    #################################
    # Data protection tab
    #################################
    data_protection = {
      versioning_enabled       = true        # Blob versioning (cost impact)
      change_feed_enabled      = false

      # Soft delete (blob & container) — protects from accidental deletion [8](https://microsoft.sharepoint.com/teams/Azure_IaaS_Technical_Support/_layouts/15/Doc.aspx?sourcedoc=%7B81FE843A-4549-41A7-8837-9FFE09AC24DD%7D&file=Azure%20Storage.pptx&action=edit&mobileredirect=true&DefaultItemOpen=1)[7](https://microsoft.sharepoint.com/teams/Azure_IaaS_Technical_Support/_layouts/15/Doc.aspx?sourcedoc=%7BD1F3E8A7-2E12-4A79-94B7-B08E3BF2A5C7%7D&file=Module%2006%20-%20Azure%20Storage.pptx&action=edit&mobileredirect=true&DefaultItemOpen=1)
      blob_soft_delete         = { enabled = true, days = 7 }
      container_soft_delete    = { enabled = true, days = 7 }
    }

    #################################
    # Encryption tab
    #################################
    # You are using infrastructure encryption (above). If you later add CMK,
    # you typically set “Customer-managed keys (CMK)” here (requires Key Vault + identity).
    # Portal screenshot shows encryption choices MMK/CMK and infra encryption toggle. [6](https://microsoft.sharepoint.com/teams/infoprotect-cc/_layouts/15/Doc.aspx?sourcedoc=%7B36FA84D2-14D4-4D81-93F3-03CE8387B24D%7D&file=Evidence%20Collection%20in%20DLP.docx&action=default&mobileredirect=true&DefaultItemOpen=1)[8](https://microsoft.sharepoint.com/teams/Azure_IaaS_Technical_Support/_layouts/15/Doc.aspx?sourcedoc=%7B81FE843A-4549-41A7-8837-9FFE09AC24DD%7D&file=Azure%20Storage.pptx&action=edit&mobileredirect=true&DefaultItemOpen=1)
    # encryption = {
    #   customer_managed_key = {
    #     enabled                   = false
    #     key_vault_key_id          = "/subscriptions/.../keys/<keyname>/<version>"
    #     user_assigned_identity_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/<uami>"
    #   }
    # }

    #################################
    # Tags tab
    #################################
    # tags = { purpose = "claims-storage" }
  }
}


################################################################################
# KEY VAULT (Portal tabs: Basics / Access configuration / Networking / Tags)
#
# Portal networking guidance: Selected networks, add VNets/subnets, allow trusted services, etc. [4](https://learn.microsoft.com/en-us/azure/key-vault/general/how-to-azure-key-vault-network-security)[5](https://learn.microsoft.com/en-us/azure/key-vault/secrets/secrets-best-practices)
################################################################################
key_vaults = {
  kv1 = {
    #################################
    # Basics tab
    #################################
    name                       = "kv-claims-test-cind"
    sku_name                   = "standard" # standard | premium

    #################################
    # Data protection (delete protection)
    #################################
    soft_delete_retention_days = 7
    purge_protection_enabled   = true

    #################################
    # Access configuration tab
    #################################
    enable_rbac_authorization  = true  # true => RBAC model; false => Access Policies model

    #################################
    # Networking tab
    #################################
    networking = {
      # In portal: “Allow access from: Selected networks” or disable public + use private link. [4](https://learn.microsoft.com/en-us/azure/key-vault/general/how-to-azure-key-vault-network-security)[5](https://learn.microsoft.com/en-us/azure/key-vault/secrets/secrets-best-practices)
      public_network_access_enabled = false

      # Firewall rules (only relevant if public access is enabled with Selected networks)
      default_action = "Deny"         # Allow | Deny
      bypass         = "AzureServices" # “Allow trusted services” equivalent patterns vary
      ip_rules       = []              # allowed IP CIDRs
      subnet_ids     = []              # allowed subnet IDs (service endpoints may be auto-enabled)
    }

    #################################
    # Tags tab
    #################################
    # tags = { purpose = "claims-secrets" }
  }
}


################################################################################
# PRIVATE ENDPOINTS (Portal: Networking -> Private endpoint connections)
#
# Storage: subresource_names can be ["blob"], ["file"], ["queue"], ["table"]
# Key Vault: subresource_names is ["vault"]
# Private endpoints recommended to eliminate public exposure. [3](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-overview)[10](https://microsoft.sharepoint.com/teams/FY23AzureCoreSolutionPlay-MigrateModernize/_layouts/15/Doc.aspx?sourcedoc=%7BD3B40D1E-D1F6-477E-8E12-5BA7389E587C%7D&file=Using%20Azure%20Private%20Link%20and%20Private%20Endpoints%20to%20Connect%20and%20Protect%20IaaS%20and%20PaaS%20resources.pptx&action=edit&mobileredirect=true&DefaultItemOpen=1)
################################################################################
private_endpoints = {
  pe_storage_blob = {
    name                 = "pe-stcindclaims0011-blob"
    vnet_key             = "vnet1"
    subnet_key           = "subnet_pe"

    target_kind          = "storage"
    target_key           = "sa1"

    subresource_names    = ["blob"]  # other options: "file","queue","table"
    private_dns_zone_key = "storage_blob"
  }

  pe_kv_vault = {
    name                 = "pe-kv-claims-test-vault"
    vnet_key             = "vnet1"
    subnet_key           = "subnet_pe"

    target_kind          = "keyvault"
    target_key           = "kv1"

    subresource_names    = ["vault"]
    private_dns_zone_key = "keyvault"
  }
}


# #############################################
# # DIAGNOSTIC SETTINGS (Portal: Diagnostic settings)
# # Typical pattern: send Logs + Metrics to Log Analytics workspace.
# #############################################
# diagnostic_settings = {
#   # Example template (fill in IDs):
#   diag_sa1 = {
#     name                       = "diag-stcindclaims0011"
#     target_resource_id         = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/stcindclaims0011"
#     log_analytics_workspace_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/law-claims-test-cind"
  
#     logs = [
#       { category_group = "audit", enabled = true },
#       { category_group = "allLogs", enabled = true }
#     ]
#     metrics = [
#       { category = "AllMetrics", enabled = true }
#     ]
#   }
# }
