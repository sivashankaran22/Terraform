## Storage Account – security controls in the code
1. public_network_access_enabled = false
Disables the Storage Account public endpoint so clients can’t access it over the public internet; access must come via Private Endpoint (or other explicitly allowed mechanisms, depending on service behavior). This reduces exposure to internet scanning and public attack surface.

2. shared_access_key_enabled = false
Prevents Shared Key (account keys) and “key-based” auth usage. This blocks a very high-privilege credential type that is easy to leak and hard to govern. Microsoft explicitly recommends disabling Shared Key when possible in favor of Entra ID. 

3. default_to_oauth_authentication = true
Makes Entra ID/OAuth the default auth method in tooling/portal experiences, reducing accidental key-based access patterns and aligning with AAD-first governance. 

4. allow_nested_items_to_be_public = false
Prevents containers/blobs from being configured for anonymous public access (e.g., “public blob”). This is a common data leakage vector. The platform defaults can be permissive unless explicitly turned off.

5. min_tls_version = "TLS1_2"
Forces TLS 1.2+ for in-transit encryption, preventing weak protocol negotiation (TLS 1.0/1.1). Microsoft documents that minimum TLS is an explicit security control for storage.

6. infrastructure_encryption_enabled = true
Adds an extra encryption layer for data-at-rest in the storage infrastructure (defense in depth beyond standard Storage encryption). This reduces risk if underlying storage encryption controls are bypassed or misconfigured. 

7. “Retention policies + versioning enabled”
From your blob settings: "blob_properties"

Versioning: Creates versions on overwrite; helps recovery from accidental overwrite/ransomware.
Delete retention / container delete retention: Soft-deletes within retention window, enabling recovery from accidental deletion. recommends soft delete + versioning for layered protection. 

8. immutability_policy (Unlocked, 30 days)
Enforces WORM-style protection for the retention period so blobs/versions can’t be altered/deleted in violation of policy. In your case it’s Unlocked for testing/adjustment.
Important nuance: Microsoft states Locked is needed for full compliance-grade immutability; Unlocked still protects data but can be modified/removed. So “Unlocked 30 days” is strong, but not maximum strictness.

9. https_traffic_only_enabled = true
Prevents any plaintext HTTP usage; forces HTTPS for all requests. This helps ensure confidentiality/integrity in transit. (Storage security baseline patterns include HTTPS-only.) 

10. local_user_enabled = false and sftp_enabled = false
Reduces alternate authentication and file-transfer surfaces (local users/SFTP). This prevents “shadow” access paths that bypass Entra-based governance.

11. Storage network rules scoped to subnets
Your network_rules_subnet_refs restricts access to specific VNets/subnets (after being resolved to subnet IDs). This ensures even inside Azure, only approved network locations can access the storage account.

12. Storage private endpoint uses subresource_name = "blob"
Limits Private Link to only the blob service endpoint surface; keeps traffic on Microsoft backbone and requires correct DNS routing to private IP.


## Key Vault – security controls
1. public_network_access_enabled = false
Eliminates public entry point; vault data-plane becomes accessible through private endpoints (and trusted bypass rules if configured). This is listed as the most restrictive network posture for Key Vault. 

2. network_acls.default_action = "Deny"
Deny-by-default firewall posture. Only explicitly allowed VNets/subnets (or trusted services if bypass is enabled) can access Key Vault data plane.

3. Private endpoints configured
Brings Key Vault into your VNet via private IP; prevents traversal over public internet and pairs with Private DNS for correct name resolution.

4. legacy_access_policies_enabled = false
Disables legacy access policy model and prefers RBAC authorization model alignment (management is RBAC-authorized). This is consistent with modern governance direction. 

5. soft_delete_retention_days = 7
Protects against accidental deletion by enabling recoverability window. (Soft delete is a security and recovery control.)

6. network_acls.bypass = "AzureServices" (if set in your config)
Allows a limited set of “trusted Azure services” to bypass firewall rules. This can be necessary for some integrations, but it’s a trade-off (less restrictive than “None”).

7. purge_protection_enabled = true
prevents the permanent deletion (purging) of your key vaults and their contents (keys, secrets, certificates) for a mandatory retention period (7-90 days) after they've been soft-deleted

## Cognitive Services (Document Intelligence + Azure OpenAI) – security controls
1. public_network_access_enabled = false
Blocks public inbound access; forces Private Endpoint access model to reduce internet exposure. This aligns with security recommendations for Cognitive Services network access. 

2. local_auth_enabled = false
Disables local/API key auth (“subscription keys”), pushing you toward Entra ID / managed identity based auth. Microsoft has explicit guidance around disabling local auth as part of “safe secrets” initiatives.

3. Private endpoints configured
Ensures cognitive endpoints resolve to private IPs inside your VNet and traffic stays on Azure backbone; reduces risk of data exfiltration via public network exposure

## Cosmos DB – security controls
1. public_network_access_enabled = false
Disables public access route and reduces attack surface; expected to be used with private endpoints. 

2. Private endpoint configured with subresource_name = "MongoDB"
Private Link is specifically targeting the Mongo API surface so clients connect privately. Private Link + restrictive NSGs reduces data exfiltration risk. 

3. minimal_tls_version = "Tls12"
Forces TLS 1.2+ for Cosmos endpoints. Cosmos DB requires/enforces strong TLS baselines and provides self-serve minimum TLS configuration.

4. Continuous backup (type = "Continuous", tier = "Continuous30Days")
Strong data protection and ransomware recovery posture (point-in-time restore window). This is a resilience & security control against destructive events.

5. private_endpoints_manage_dns_zone_group = true
Delegates DNS zone group management to the module (reduces risk of misconfigured DNS zone group and broken private resolution). Correct DNS is mandatory for private endpoint connectivity.

## Function App / App Service hardening (when enabled)
1) https_only = true
Forces HTTPS-only access to the app endpoint, preventing plaintext HTTP. (Standard App Service security control.)

2) Disable publishing basic auth:
ftp_publish_basic_authentication_enabled = false
webdeploy_publish_basic_authentication_enabled = false
Disables Basic Auth for FTP and SCM/WebDeploy publishing credentials. This prevents leaked publish profiles / basic creds from being used to deploy or access Kudu endpoints. Microsoft explicitly documents disabling basic auth as a security improvement.

3) public_network_access_enabled = false 
Reduces public exposure; combined with VNet integration for internal access patterns.

4) VNet integration: virtual_network_subnet_id = local.subnet_ids[""]
Keeps outbound traffic within VNet patterns (for reaching private endpoints) and helps enforce private access dependencies.


## Azure Machine Learning (AML) network isolation
1) public_network_access_enabled = false
What it does: Blocks public access to AML workspace, forcing private endpoint access. This is aligned with Azure security controls for AML workspaces.

2) Managed network isolation mode: isolation_mode = "AllowOnlyApprovedOutbound"
Strong egress control to minimize data exfiltration risk by allowing only approved outbound destinations (and required service tags). This is explicitly recommended as the most restrictive AML managed network mode. 
