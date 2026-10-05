output "gitlab_url" {
  description = "GitLab web URL over HTTPS (ready ~5-10 minutes after apply)."
  value       = "https://${azurerm_public_ip.gitlab.fqdn}"
}

output "gitlab_public_ip" {
  description = "Public IP of the GitLab VM."
  value       = azurerm_public_ip.gitlab.ip_address
}

output "gitlab_ssh_command" {
  description = "Admin SSH into the GitLab VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.gitlab.ip_address}"
}

output "git_ssh_clone_prefix" {
  description = "Prefix for Git-over-SSH clone URLs."
  value       = "ssh://git@${azurerm_public_ip.gitlab.fqdn}:2224"
}

output "runner_public_ip" {
  description = "Public IP of the runner VM."
  value       = azurerm_public_ip.runner.ip_address
}

output "runner_ssh_command" {
  description = "Admin SSH into the runner VM (to register the runner)."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.runner.ip_address}"
}

output "staging_app_url" {
  description = "Sample app deployed by the CI/CD pipeline (runs on the runner VM)."
  value       = "http://${azurerm_public_ip.runner.ip_address}:5000"
}
