#!/bin/bash
# Creates a GitLab backup and copies it, plus the required config/secrets, to the host.
# Usage: ./scripts/backup.sh [destination_dir]   (default: ~/gitlab-backups)
set -e

BACKUP_DIR_HOST="${1:-$HOME/gitlab-backups}"
mkdir -p "$BACKUP_DIR_HOST"

echo "=== [1/3] Creating GitLab backup (inside the container) ==="
docker exec -t gitlab_server gitlab-backup create

echo "=== [2/3] Copying backup + config to host: $BACKUP_DIR_HOST ==="
docker cp gitlab_server:/var/opt/gitlab/backups/. "$BACKUP_DIR_HOST"
docker cp gitlab_server:/etc/gitlab/gitlab-secrets.json "$BACKUP_DIR_HOST/gitlab-secrets.json"
docker cp gitlab_server:/etc/gitlab/gitlab.rb "$BACKUP_DIR_HOST/gitlab.rb"

echo "=== [3/3] Removing backups older than 7 days from the container ==="
docker exec gitlab_server find /var/opt/gitlab/backups -mtime +7 -delete || true

echo "✅ Backup complete: $BACKUP_DIR_HOST"
echo "⚠️  gitlab-secrets.json and gitlab.rb are required to restore — keep them safe and out of Git."
