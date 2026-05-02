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
