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
