#!/bin/bash
set -e

COMPOSE_FILE="docker-compose.yaml"

echo "=== [1/3] Checking Docker Compose file ==="
if [ ! -f "$COMPOSE_FILE" ] && [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yaml not found in current directory!"
    exit 1
fi
echo "✅ Found Docker Compose file."

echo "=== [2/3] Creating Persistent Storage Directories ==="
mkdir -p ./gitlab/config ./gitlab/logs ./gitlab/data
# SECURITY FIX: 700 (owner-only) instead of 777.
# GitLab's entrypoint runs as root inside the container and manages its own
# internal file ownership, so the host side only needs to be readable/
# writable by root — 777 let every user on the VM read GitLab's secrets.
sudo chown -R root:root ./gitlab
sudo chmod -R 700 ./gitlab

echo "=== [3/3] Launching GitLab Services via Docker Compose ==="
docker compose up -d

echo "✅ GitLab Deployment Triggered successfully!"
