# GitLab platform (Member 1). These resources already existed when Terraform
# took them over: import_existing.sh adopts them into the state without
# recreating anything, and prevent_destroy guards the ones holding data or the address.
resource "azurerm_resource_group" "gitlab" {
  name     = "gitra-rg"
  location = var.location

  lifecycle {
    prevent_destroy = true
  }
}
