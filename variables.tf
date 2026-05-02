variable "project_id" {
  description = "GCP project ID"
}

variable "region" {
  default = "europe-west3"
}

variable "zone" {
  default = "europe-west3-a"
}

variable "machine_type" {
  default = "e2-standard-2"
}

variable "ssh_user" {
  default = "dev"
}

variable "public_key_path" {
  default = "~/.ssh/id_ed25519.pub"
}

variable "telegram_user_id" {
  description = "Numeric Telegram user ID for DM/group allowlists and commands.ownerAllowFrom (see cloud-init / BotFather setup)."
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

variable "vercel_token" {
  description = "Vercel token for deployments/API (terraform.tfvars only)."
  type        = string
  sensitive   = true
  default     = "your-vercel-token"
}
