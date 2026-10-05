#!/bin/bash
# Prepares the team's existing GitLab VM on Azure (runs in GitHub Actions).
#   - Finds the VM from its public IP
#   - Makes the IP static and gives it a free DNS name (needed for HTTPS)
#   - Makes sure the VM's NSG allows 22, 80, 443 and 2224
#   - Adds the deploy user + SSH key to the VM (no password needed)
# Env: GITLAB_VM_IP, DEPLOY_USER, SSH_PUBLIC_KEY, DNS_LABEL (optional)
# Writes vm_name, vm_rg, location, fqdn to $GITHUB_OUTPUT.
set -euo pipefail

: "${GITLAB_VM_IP:?}" "${DEPLOY_USER:?}" "${SSH_PUBLIC_KEY:?}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"

echo "=== [1/5] Finding the VM that owns $GITLAB_VM_IP ==="
PIP_ID=$(az network public-ip list --query "[?ipAddress=='$GITLAB_VM_IP'].id | [0]" -o tsv)
if [ -z "$PIP_ID" ]; then
    echo "❌ No public IP $GITLAB_VM_IP in this subscription. Check the GITLAB_VM_IP variable."
    exit 1
fi
IPCONF_ID=$(az network public-ip show --ids "$PIP_ID" --query ipConfiguration.id -o tsv)
NIC_ID="${IPCONF_ID%/ipConfigurations/*}"
VM_ID=$(az network nic show --ids "$NIC_ID" --query virtualMachine.id -o tsv)
VM_NAME=$(az vm show --ids "$VM_ID" --query name -o tsv)
VM_RG=$(az vm show --ids "$VM_ID" --query resourceGroup -o tsv)
LOCATION=$(az vm show --ids "$VM_ID" --query location -o tsv)
VM_SIZE=$(az vm show --ids "$VM_ID" --query hardwareProfile.vmSize -o tsv)
echo "✅ VM: $VM_NAME (resource group $VM_RG, $LOCATION, size $VM_SIZE)"

echo "=== [2/5] Static IP + DNS name ==="
if [ "$(az network public-ip show --ids "$PIP_ID" --query publicIPAllocationMethod -o tsv)" != "Static" ]; then
    az network public-ip update --ids "$PIP_ID" --allocation-method Static -o none
    echo "IP switched to Static (it keeps the same address)."
fi
LABEL=$(az network public-ip show --ids "$PIP_ID" --query dnsSettings.domainNameLabel -o tsv)
if [ -z "$LABEL" ]; then
    SUB=$(az account show --query id -o tsv)
    LABEL="${DNS_LABEL:-gitra-$(printf '%s' "$SUB" | sha256sum | cut -c1-8)}"
    az network public-ip update --ids "$PIP_ID" --dns-name "$LABEL" -o none
fi
FQDN=$(az network public-ip show --ids "$PIP_ID" --query dnsSettings.fqdn -o tsv)
echo "✅ GitLab address: https://$FQDN"

echo "=== [3/5] NSG rules ==="
NSG_ID=$(az network nic show --ids "$NIC_ID" --query networkSecurityGroup.id -o tsv)
if [ -z "$NSG_ID" ]; then
    SUBNET_ID=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].subnet.id" -o tsv)
    NSG_ID=$(az network vnet subnet show --ids "$SUBNET_ID" --query networkSecurityGroup.id -o tsv)
fi
if [ -z "$NSG_ID" ]; then
    echo "No NSG found — creating one on the VM's network interface."
    NSG_ID=$(az network nsg create -g "$VM_RG" -n "${VM_NAME}-nsg" -l "$LOCATION" --query NewNSG.id -o tsv)
    az network nic update --ids "$NIC_ID" --network-security-group "$NSG_ID" -o none
fi
NSG_NAME=$(basename "$NSG_ID")
NSG_RG=$(echo "$NSG_ID" | awk -F/ '{print $5}')
RULES=$(az network nsg rule list -g "$NSG_RG" --nsg-name "$NSG_NAME" -o json)
for entry in "Allow-SSH-Admin:22" "Allow-HTTP:80" "Allow-HTTPS:443" "Allow-GitLab-SSH:2224"; do
    NAME="${entry%%:*}"
    PORT="${entry##*:}"
    # Skip if any inbound allow rule already opens this port.
    if echo "$RULES" | jq -e --arg p "$PORT" '.[] | select(.direction=="Inbound" and .access=="Allow")
        | select(.destinationPortRange==$p or ((.destinationPortRanges // []) | index($p)))' >/dev/null; then
        echo "  port $PORT already open"
        continue
    fi
    PRIO=300
    while echo "$RULES" | jq -e --argjson p "$PRIO" '.[] | select(.direction=="Inbound" and .priority==$p)' >/dev/null; do
        PRIO=$((PRIO + 10))
    done
    az network nsg rule create -g "$NSG_RG" --nsg-name "$NSG_NAME" -n "$NAME" --priority "$PRIO" \
        --direction Inbound --access Allow --protocol Tcp --destination-port-ranges "$PORT" -o none
    RULES=$(az network nsg rule list -g "$NSG_RG" --nsg-name "$NSG_NAME" -o json)
    echo "  port $PORT opened ($NAME, priority $PRIO)"
done
echo "✅ NSG $NSG_NAME ready."

echo "=== [4/5] Deploy user $DEPLOY_USER with SSH key ==="
# Uses the Azure VM agent, so no existing password or key is needed.
az vm user update -g "$VM_RG" -n "$VM_NAME" -u "$DEPLOY_USER" --ssh-key-value "$SSH_PUBLIC_KEY" -o none
echo "✅ Deploy user ready."

echo "=== [5/5] Done ==="
{
    echo "vm_name=$VM_NAME"
    echo "vm_rg=$VM_RG"
    echo "location=$LOCATION"
    echo "fqdn=$FQDN"
} >> "$OUT"
