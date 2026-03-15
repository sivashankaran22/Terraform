
output "resource_group_name"     { value = local.rg_name }
output "resource_group_location" { value = local.rg_location }

output "law_id"  { value = local.law_id }
output "appi_id" { value = local.appi_id }

output "subnet_ids" { value = local.subnet_id_by_key }
output "nsg_ids"    { value = local.nsg_id_by_key }

output "storage_ids" { value = { for k, v in azurerm_storage_account.sa : k => v.id } }
