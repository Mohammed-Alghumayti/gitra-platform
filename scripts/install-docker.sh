#!/usr/bin/env bash
# Installs Docker Engine + Docker Compose plugin on Ubuntu 22.04 (Azure VM).
# Usage: ./install-docker.sh
set -euo pipefail

echo "==> Updating apt and installing prerequisites"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

echo "==> Adding Docker's official GPG key"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "==> Adding the Docker apt repository"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> Installing Docker Engine, CLI, and the Compose plugin"
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Allowing the current user to run docker without sudo"
sudo usermod -aG docker "$USER"

echo "==> Enabling Docker to start on boot"
sudo systemctl enable docker
sudo systemctl start docker

echo "==> Verifying installation"
docker --version
docker compose version

echo ""
echo "Done. Log out and back in (or run 'newgrp docker') for the group change to take effect."