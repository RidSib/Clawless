provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "local_file" "ssh_key" {
  filename = pathexpand(var.public_key_path)
}

resource "google_compute_instance" "dev" {
  name                      = "cloud-automation-dev"
  machine_type              = var.machine_type
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      ssh_public_key = data.local_file.ssh_key.content
      telegram_user_id = var.telegram_user_id
      github_token = var.github_token
      vercel_token = var.vercel_token
      azure_openai_api_key = var.azure_openai_api_key
      azure_openai_endpoint = var.azure_openai_endpoint
      azure_openai_realtime_deployment_name = (
        var.azure_openai_realtime_deployment_name
      )
      openai_api_key = var.openai_api_key
      twilio_auth_token = var.twilio_auth_token
      realtime_public_url = var.realtime_public_url
      realtime_provider = var.realtime_provider
      realtime_voice_flag = var.realtime_voice_enabled ? "1" : "0"
      realtime_voice_repo_url = var.realtime_voice_repo_url
      realtime_caddy_flag = trimspace(var.realtime_caddy_hostname) != "" ? "1" : "0"
      realtime_caddy_hostname = var.realtime_caddy_hostname
      cloudflare_tunnel_flag = trimspace(var.cloudflare_tunnel_token) != "" ? "1" : "0"
      cloudflare_tunnel_token = var.cloudflare_tunnel_token
      openclaw_runtime_extras_dockerfile_b64 = base64encode(file(
        "${path.module}/docker/openclaw-runtime-extras.Dockerfile"
      ))
      workspace_identity_b64 = base64encode(file(
        "${path.module}/workspace-seed/IDENTITY.md"
      ))
      workspace_user_b64 = base64encode(file(
        "${path.module}/workspace-seed/USER.md"
      ))
      workspace_soul_b64 = base64encode(file(
        "${path.module}/workspace-seed/SOUL.md"
      ))
    })
  }

  tags = ["ssh", "openclaw"]
}

resource "google_compute_firewall" "openclaw" {
  name    = "allow-openclaw-gateway"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["18789"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openclaw"]
}

resource "google_compute_firewall" "realtime_https" {
  count   = var.realtime_nsg_https ? 1 : 0
  name    = "allow-realtime-https"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["openclaw"]
}
