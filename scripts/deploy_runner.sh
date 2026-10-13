#!/bin/bash
# Starts the GitLab Runner. Run this on the runner VM, not the GitLab VM.
set -e

cd "$(dirname "$0")/.."

echo "=== [1/2] Creating runner config directory ==="
mkdir -p ./runner
# The runner config holds its authentication token — owner-only access.
sudo chown root:root ./runner
sudo chmod 700 ./runner

echo "=== [2/2] Launching GitLab Runner via Docker Compose ==="
docker compose -f docker-compose.runner.yaml up -d

echo "✅ Runner started. Register it with: ./scripts/register_runner.sh <token>"
