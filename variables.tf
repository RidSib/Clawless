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
