locals {
  # "gitra-runner-*": kept apart from the team's existing gitra-rg / gitra-gitlab-vm.
  name = "${var.project_name}-runner"
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = var.tags
}
