locals {
  name = var.project_name
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = var.tags
}
