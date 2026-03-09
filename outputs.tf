output "ssh_command" {
  value = "ssh dev@${google_compute_instance.dev.network_interface[0].access_config[0].nat_ip}"
}

output "openclaw_control_ui" {
  value       = "http://${google_compute_instance.dev.network_interface[0].access_config[0].nat_ip}:18789"
  description = "OpenClaw Control UI (run onboarding after first boot)"
}
