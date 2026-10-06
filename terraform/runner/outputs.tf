output "runner_public_ip" {
  description = "Public IP of the runner VM."
  value       = azurerm_public_ip.runner.ip_address
}

output "runner_ssh_command" {
  description = "Admin SSH into the runner VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.runner.ip_address}"
}

output "staging_app_url" {
  description = "Sample app deployed by the CI/CD pipeline."
  value       = "http://${azurerm_public_ip.runner.ip_address}:5000"
}
