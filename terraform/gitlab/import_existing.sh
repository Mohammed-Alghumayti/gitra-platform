#!/bin/bash
# Adopts the GitLab platform resources that already exist in Azure into
# Terraform's state. Importing changes nothing in Azure. Resources already in
# the state are skipped, so this is safe to run on every deployment.
# Run from terraform/gitlab after `terraform init`. Env: TF_VAR_subscription_id
set -euo pipefail

: "${TF_VAR_subscription_id:?}"
RG="/subscriptions/$TF_VAR_subscription_id/resourceGroups/gitra-rg"
NET="$RG/providers/Microsoft.Network"

RESOURCES=(
  "azurerm_resource_group.gitlab|$RG"
  "azurerm_virtual_network.gitlab|$NET/virtualNetworks/vnet-eastus-1"
  "azurerm_subnet.gitlab|$NET/virtualNetworks/vnet-eastus-1/subnets/snet-eastus-1"
  "azurerm_public_ip.gitlab|$NET/publicIPAddresses/gitra-gitlab-vm-ip"
  "azurerm_network_interface.gitlab|$NET/networkInterfaces/gitra-gitlab-vm703"
  "azurerm_network_security_group.gitlab|$NET/networkSecurityGroups/gitra-gitlab-vm-nsg"
  "azurerm_network_interface_security_group_association.gitlab|$NET/networkInterfaces/gitra-gitlab-vm703|$NET/networkSecurityGroups/gitra-gitlab-vm-nsg"
  "azurerm_linux_virtual_machine.gitlab|$RG/providers/Microsoft.Compute/virtualMachines/gitra-gitlab-vm"
)

STATE=$(terraform state list 2>/dev/null || true)
for entry in "${RESOURCES[@]}"; do
    ADDR="${entry%%|*}"
    ID="${entry#*|}"
    if grep -qx "$ADDR" <<< "$STATE"; then
        echo "  already managed: $ADDR"
    else
        echo "  importing: $ADDR"
        terraform import -input=false "$ADDR" "$ID" >/dev/null
    fi
done
