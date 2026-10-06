output "gitlab_url" {
  description = "GitLab over HTTPS."
  value       = "https://${azurerm_public_ip.gitlab.fqdn}"
}

output "gitlab_public_ip" {
  description = "Public IP of the GitLab VM."
  value       = azurerm_public_ip.gitlab.ip_address
}
