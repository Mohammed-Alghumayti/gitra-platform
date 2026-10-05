output "public_ip" {
  description = "Public IP of the GitLab VM."
  value       = azurerm_public_ip.main.ip_address
}

output "gitlab_url" {
  description = "GitLab web URL (ready ~5 minutes after apply)."
  value       = "http://${azurerm_public_ip.main.ip_address}"
}

output "ssh_command" {
  description = "Admin SSH into the VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "git_ssh_clone_prefix" {
  description = "Prefix for Git-over-SSH clone URLs."
  value       = "ssh://git@${azurerm_public_ip.main.ip_address}:2224"
}

output "staging_app_url" {
  description = "Sample app deployed by the CI/CD pipeline."
  value       = "http://${azurerm_public_ip.main.ip_address}:5000"
}
