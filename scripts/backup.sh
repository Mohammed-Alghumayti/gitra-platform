#!/usr/bin/env bash
# Creates a GitLab backup and copies it (plus config/secrets) to the host.
# Usage: ./backup.sh [destination_dir]   (defaults to ~/gitlab-backups)
set -euo pipefail

BACKUP_DIR_HOST="${1:-$HOME/gitlab-backups}"
mkdir -p "$BACKUP_DIR_HOST"

echo "==> Creating GitLab backup (inside the container)"
docker exec -t gitlab gitlab-backup create

echo "==> Copying backup + config to host: $BACKUP_DIR_HOST"
docker cp gitlab:/var/opt/gitlab/backups/. "$BACKUP_DIR_HOST"
docker cp gitlab:/etc/gitlab/gitlab-secrets.json "$BACKUP_DIR_HOST/gitlab-secrets.json"
docker cp gitlab:/etc/gitlab/gitlab.rb "$BACKUP_DIR_HOST/gitlab.rb"

echo "==> Removing backups older than 7 days from the container"
docker exec gitlab find /var/opt/gitlab/backups -mtime +7 -delete || true

echo "Backup complete: $BACKUP_DIR_HOST"
echo "NOTE: gitlab-secrets.json and gitlab.rb are required to restore — keep them safe."