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
mkdir -p ./gitlab/config ./gitlab/logs ./gitlab/data ./runner
# SECURITY FIX: 700 (owner-only) instead of 777.
# Only the top-level folders are locked down: that already blocks other VM
# users from reaching anything inside. GitLab manages the permissions of its
# own files, so they are deliberately not changed recursively.
sudo chown root:root ./gitlab ./gitlab/config ./gitlab/logs ./gitlab/data ./runner
sudo chmod 700 ./gitlab ./gitlab/config ./gitlab/logs ./gitlab/data ./runner

echo "=== [3/3] Launching GitLab Services via Docker Compose ==="
docker compose up -d

echo "✅ GitLab Deployment Triggered successfully!"
