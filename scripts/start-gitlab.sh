#!/usr/bin/env bash
# Starts GitLab via Docker Compose and waits until it's actually healthy.
# Usage: ./start-gitlab.sh
set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../docker" && pwd)"

echo "==> Starting GitLab with Docker Compose"
cd "$COMPOSE_DIR"
docker compose up -d

echo "==> Waiting for GitLab to become healthy (this usually takes 3-5 minutes)..."
until [ "$(docker inspect --format='{{.State.Health.Status}}' gitlab 2>/dev/null)" = "healthy" ]; do
  printf '.'
  sleep 10
done
echo ""
echo "==> GitLab is up."

echo "==> Initial root password (only valid for the first 24 hours):"
docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null || \
  echo "    (Not found — GitLab may already be initialized, or the 24h window passed. Reset via 'docker exec -it gitlab gitlab-rake \"gitlab:password:reset[root]\"')"

echo ""
echo "==> Open http://<VM_PUBLIC_IP> in your browser and log in as 'root'."