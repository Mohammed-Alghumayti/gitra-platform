#!/bin/bash
# Admin SSH (port 22): keys only. Turns off password logins on the VM so
# password-guessing bots on the internet have nothing to try.
# Run as root on the VM (the deploy workflow does this). Safe to re-run.
#
# Not done in Terraform: changing disable_password_authentication there
# would rebuild the VM. Git SSH on port 2224 is GitLab's own and unaffected.
set -euo pipefail

CONF=/etc/ssh/sshd_config.d/00-gitra-hardening.conf

# Never lock everyone out: at least one user must have an SSH key.
if ! compgen -G "/home/*/.ssh/authorized_keys" >/dev/null &&
   [ ! -s /root/.ssh/authorized_keys ]; then
    echo "❌ No SSH keys found on this VM — keeping password login on."
    exit 1
fi

echo "=== Admin SSH: keys only ==="
# sshd keeps the first value it reads, and files here are read in name
# order, so 00- wins over Azure's/Ubuntu's own settings (e.g. 50-cloudimg).
cat > "$CONF" <<'EOF'
# Managed by gitra-platform (scripts/harden_ssh.sh)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
chmod 644 "$CONF"

# Check the config before applying it; a broken sshd config must not be loaded.
if ! sshd -t; then
    rm -f "$CONF"
    echo "❌ sshd rejected the config — change removed."
    exit 1
fi
# Reload keeps current sessions (including this one) open.
systemctl reload ssh 2>/dev/null || systemctl reload sshd

sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin) '
echo "✅ Password login over SSH is off — SSH keys only."
