#!/usr/bin/env bash
# Stops and recreates the GitLab container without losing data (named volumes persist).
# Usage: ./redeploy.sh
set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../docker" && pwd)"
cd "$COMPOSE_DIR"

echo "==> Stopping and removing the current container (volumes are kept)"
docker compose down

echo "==> Pulling the latest image"
docker compose pull

echo "==> Starting a fresh container"
docker compose up -d

echo "Redeploy complete. Data in the named volumes was preserved."
echo "Run health-check.sh in a few minutes to confirm GitLab is back up."