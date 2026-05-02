output "ssh_command" {
  value = "ssh ${var.ssh_user}@${azurerm_public_ip.main.ip_address}"
}

output "openclaw_control_ui" {
  value       = "http://${azurerm_public_ip.main.ip_address}:18789"
  description = "OpenClaw Control UI URL. Prefer SSH tunnel for localhost."
}
