#!/usr/bin/env bash
# Checks that GitLab's container, internal services, and HTTP endpoint are healthy.
# Usage: ./health-check.sh [VM_PUBLIC_IP]   (defaults to localhost)
set -euo pipefail

echo "==> Container status"
docker ps --filter "name=gitlab" --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "==> GitLab internal service check"
docker exec gitlab gitlab-ctl status || echo "WARNING: gitlab-ctl reported an issue above"

echo ""
echo "==> HTTP check"
VM_IP="${1:-localhost}"
if curl -fsS -o /dev/null -w "HTTP status: %{http_code}\n" "http://$VM_IP/-/health"; then
  echo "GitLab is responding on http://$VM_IP"
else
  echo "WARNING: GitLab did not respond on http://$VM_IP"
fi

echo ""
echo "==> Disk usage"
df -h / | tail -n 1