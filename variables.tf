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

variable "azure_openai_api_key" {
  description = "Azure OpenAI key (OpenClaw + realtime voice bridge)."
  type        = string
  sensitive   = true
  default     = "your-azure-openai-api-key"
}

variable "azure_openai_endpoint" {
  description = "Azure OpenAI OpenAI-compatible base (see docs/openclaw-azure.md)."
  type        = string
  default     = "your-azure-openai-endpoint"
}

variable "azure_openai_realtime_deployment_name" {
  description = "Realtime model deployment name for the Twilio bridge."
  type        = string
  default     = "your-realtime-deployment-name"
}

variable "openai_api_key" {
  description = "OpenAI API key (fallback / REALTIME_PROVIDER=openai)."
  type        = string
  sensitive   = true
  default     = "your-openai-api-key"
}

variable "twilio_auth_token" {
  description = "Twilio Console auth token for webhook validation."
  type        = string
  sensitive   = true
  default     = "your-twilio-auth-token"
}

variable "realtime_public_url" {
  description = "HTTPS origin for Twilio (no trailing slash). Tunnel URL ok."
  type        = string
  default     = "https://your-realtime-public-url"
}

variable "realtime_provider" {
  description = "Twilio bridge backend: azure | openai."
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "openai"], var.realtime_provider)
    error_message = "realtime_provider must be azure or openai."
  }
}

variable "realtime_voice_enabled" {
  description = "Provision realtime-phonecalls + systemd + /etc/realtime-voice.env."
  type        = bool
  default     = true
}

variable "realtime_voice_repo_url" {
  description = "Git URL for the Twilio voice bridge."
  type        = string
  default     = "https://github.com/RidSib/realtime-phonecalls.git"
}

variable "realtime_nsg_https" {
  description = "Allow inbound TCP 443 (TLS front door for Twilio)."
  type        = bool
  default     = true
}

variable "realtime_caddy_hostname" {
  description = "If set (e.g. voice.example.com), install Caddy reverse_proxy to :5050."
  type        = string
  default     = ""
}
