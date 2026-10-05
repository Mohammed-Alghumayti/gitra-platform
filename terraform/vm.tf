locals {
  gitlab_fqdn = azurerm_public_ip.gitlab.fqdn
}

# --- GitLab VM: GitLab only, no CI jobs run here ---
resource "azurerm_linux_virtual_machine" "gitlab" {
  name                  = "${local.name}-gitlab-vm"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.gitlab.id]
  tags                  = var.tags

  # SSH keys only — password login is disabled.
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.admin_ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # First boot: Docker + fail2ban → clone repo → GitLab over HTTPS → hardening.
  custom_data = base64encode(templatefile("${path.module}/cloud-init-gitlab.yaml.tftpl", {
    admin_username = var.admin_username
    repo_url       = var.repo_url
    repo_branch    = var.repo_branch
    external_url   = "https://${local.gitlab_fqdn}"
  }))

  # The NSG must be in place before GitLab is exposed.
  depends_on = [azurerm_network_interface_security_group_association.gitlab]
}

# --- Runner VM: CI jobs + staging app, isolated from GitLab's data ---
resource "azurerm_linux_virtual_machine" "runner" {
  name                  = "${local.name}-runner-vm"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.runner_vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.runner.id]
  tags                  = var.tags

  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.admin_ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 32
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # First boot: Docker + fail2ban → clone repo → start the runner.
  custom_data = base64encode(templatefile("${path.module}/cloud-init-runner.yaml.tftpl", {
    admin_username = var.admin_username
    repo_url       = var.repo_url
    repo_branch    = var.repo_branch
    external_url   = "https://${local.gitlab_fqdn}"
  }))

  depends_on = [azurerm_network_interface_security_group_association.runner]
}
