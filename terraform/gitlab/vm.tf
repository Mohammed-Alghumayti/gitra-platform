# The VM was created with password login. Changing that through Terraform
# would rebuild the VM (and lose GitLab's data), so the password is ignored
# here: the value below is only a placeholder Terraform requires and is never
# sent to Azure (see ignore_changes).
resource "random_password" "placeholder" {
  length  = 32
  special = true
}

resource "azurerm_linux_virtual_machine" "gitlab" {
  name                  = "gitra-gitlab-vm"
  location              = azurerm_resource_group.gitlab.location
  resource_group_name   = azurerm_resource_group.gitlab.name
  size                  = var.vm_size
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.gitlab.id]

  admin_username                  = var.admin_username
  admin_password                  = random_password.placeholder.result
  disable_password_authentication = false

  # Trusted Launch, as created.
  secure_boot_enabled = true
  vtpm_enabled        = true

  disk_controller_type = "SCSI"

  os_disk {
    name                 = "gitra-gitlab-vm_OsDisk_1_790b35debd4a4c7f852806bcaa406c01"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-22_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Boot diagnostics with a managed storage account.
  # As on the existing VM; without this block Terraform plans to clear them.
  additional_capabilities {
    hibernation_enabled = false
    ultra_ssd_enabled   = false
  }

  boot_diagnostics {}

  lifecycle {
    # The VM holds all of GitLab's data.
    prevent_destroy = true
    # Set at creation; changing them would force a rebuild.
    ignore_changes = [admin_password, admin_ssh_key, custom_data, source_image_reference]
  }
}
