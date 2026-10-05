#!/bin/bash
set -e

# Always run from the repository root, wherever the script is called from.
cd "$(dirname "$0")/.."

COMPOSE_FILE="docker-compose.yaml"

echo "=== [1/3] Checking Docker Compose file ==="
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Error: $COMPOSE_FILE not found in $(pwd)!"
    exit 1
fi
echo "✅ Found Docker Compose file."

echo "=== [2/3] Creating Persistent Storage Directories ==="
mkdir -p ./gitlab/config ./gitlab/logs ./gitlab/data
# SECURITY FIX: 700 (owner-only) instead of 777 — on the parent folder only.
# That already blocks other VM users from reaching anything inside.
# The three subfolders are mounted into the container, where GitLab's own
# users (git, gitlab-www, ...) need their own permissions on them, so GitLab
# manages those itself. Locking them to root:700 stops Puma from starting.
sudo chown root:root ./gitlab
sudo chmod 700 ./gitlab

echo "=== [3/3] Launching GitLab via Docker Compose ==="
docker compose -f "$COMPOSE_FILE" up -d

echo "✅ GitLab Deployment Triggered successfully!"
