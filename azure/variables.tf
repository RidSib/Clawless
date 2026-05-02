variable "location" {
  description = "Azure region"
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Azure resource group name"
  default     = "cloud-automation-rg"
}

variable "vm_name" {
  description = "Azure VM name"
  default     = "cloud-automation-dev"
}

variable "vm_size" {
  description = "Azure VM size"
  default     = "Standard_D2s_v5"
}

variable "ssh_user" {
  description = "Linux admin username"
  default     = "dev"
}

variable "public_key_path" {
  description = "Path to SSH public key"
  default     = "~/.ssh/id_ed25519.pub"
}

variable "environment" {
  description = "Environment tag value"
  default     = "dev"
}

variable "project" {
  description = "Project tag value"
  default     = "clawless"
}

variable "owner" {
  description = "Owner tag value"
  default     = "your-name"
}

variable "telegram_user_id" {
  description = "Numeric Telegram user ID for DM/group allowlists and commands.ownerAllowFrom (pair with TELEGRAM_BOT_TOKEN in cloud-init)."
  type        = string
  default     = "your-telegram-user-id"

  validation {
    condition = (
      var.telegram_user_id == "your-telegram-user-id"
      || can(regex("^[0-9]{5,}$", var.telegram_user_id))
    )
    error_message = "telegram_user_id must be your numeric Telegram ID (digits only), or the placeholder your-telegram-user-id if you are not using Telegram yet."
  }
}

variable "github_token" {
  description = "GitHub PAT for OpenClaw / gh (set in terraform.tfvars; never commit)."
  type        = string
  sensitive   = true
  default     = "your-github-pat"
}
