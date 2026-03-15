variable "enable_virtual_networks" {
  type    = bool
  default = false

  validation {
    condition     = var.enable_virtual_networks == true || var.enable_virtual_networks == false
    error_message = "enable_virtual_networks must be either true or false."
  }
}
variable "enable_nsg" {
  description = "Enable creation of Network Security Groups"
  type        = bool
  default     = false
  validation {
    condition     = var.enable_nsg == true || var.enable_nsg == false
    error_message = "enable_nsg must be either true or false."
  }
}
variable "enable_kv" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_kv == true || var.enable_kv == false
    error_message = "enable_kv must be either true or false."
  }
}
variable "enable_log_analytics_workspace" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_log_analytics_workspace == true || var.enable_log_analytics_workspace == false
    error_message = "enable_log_analytics_workspace must be either true or false."
  }
}
variable "enable_storage_account" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_storage_account == true || var.enable_storage_account == false
    error_message = "enable_storage_account must be either true or false."
  }
}
variable "enable_function_app" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_function_app == true || var.enable_function_app == false
    error_message = "enable_function_app must be either true or false."
  }
}

variable "enable_app_service_plan" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_app_service_plan == true || var.enable_app_service_plan == false
    error_message = "enable_app_service_plan must be either true or false."
  }
}
variable "enable_user_assigned_identities" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_user_assigned_identities == true || var.enable_user_assigned_identities == false
    error_message = "enable_user_assigned_identities must be either true or false."
  }
}
variable "enable_application_insights" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_application_insights == true || var.enable_application_insights == false
    error_message = "enable_application_insights must be either true or false."
  }
}
variable "enable_aml_workspace" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_aml_workspace == true || var.enable_aml_workspace == false
    error_message = "enable_aml_workspace must be either true or false."
  }
}
variable "enable_cognitiveservices" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_cognitiveservices == true || var.enable_cognitiveservices == false
    error_message = "enable_cognitiveservices must be either true or false."
  }
}
variable "enable_cosmosdb_account" {
  type    = bool
  default = false
  validation {
    condition     = var.enable_cosmosdb_account == true || var.enable_cosmosdb_account == false
    error_message = "enable_cosmosdb_account must be either true or false."
  }
}
variable "enable_role_assignments" {
  type = bool
  default = false
  validation {
    condition     = var.enable_role_assignments == true || var.enable_role_assignments == false
    error_message = "enable_role_assignments must be either true or false."
  }
}
variable "enable_private_dns_zone" {
  type = bool
  default = false
  validation {
    condition     = var.enable_private_dns_zone == true || var.enable_private_dns_zone == false
    error_message = "enable_private_dns_zone must be either true or false."
  }
}
variable "enable_private_endpoints" {
  type = bool
  default = false
  validation {
    condition     = var.enable_private_endpoints == true || var.enable_private_endpoints == false
    error_message = "enable_private_endpoints must be either true or false."
  }
}