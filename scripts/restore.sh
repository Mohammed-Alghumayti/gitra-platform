#!/bin/bash
# Restores GitLab from a backup made by backup.sh.
# Usage: sudo ./scripts/restore.sh <backup_dir> [backup_id]
#   backup_dir  folder made by backup.sh (*_gitlab_backup.tar + gitlab-secrets.json + gitlab.rb)
#   backup_id   e.g. 1727000000_2024_09_22_17.4.0 (default: the newest backup in the folder)
#
# ⚠️ Replaces ALL current GitLab data (projects, users, CI history) with the backup.
# The running GitLab must be the same version as the one that made the backup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${1:?Usage: $0 <backup_dir> [backup_id]}"
BACKUP_ID="${2:-}"

if [ -z "$BACKUP_ID" ]; then
    LATEST=$(find "$BACKUP_DIR" -maxdepth 1 -name '*_gitlab_backup.tar' | sort | tail -1)
    [ -n "$LATEST" ] || { echo "❌ No *_gitlab_backup.tar in $BACKUP_DIR"; exit 1; }
    BACKUP_ID=$(basename "$LATEST" _gitlab_backup.tar)
fi
BACKUP_FILE="$BACKUP_DIR/${BACKUP_ID}_gitlab_backup.tar"
for f in "$BACKUP_FILE" "$BACKUP_DIR/gitlab-secrets.json" "$BACKUP_DIR/gitlab.rb"; do
    [ -f "$f" ] || { echo "❌ Missing: $f"; exit 1; }
done

echo "=== [1/6] Checking versions ==="
# The backup ID ends with the GitLab version that made it.
BACKUP_VERSION="${BACKUP_ID##*_}"
RUNNING_VERSION=$(docker exec gitlab_server awk 'NR==1 {print $2}' /opt/gitlab/version-manifest.txt)
echo "Backup: $BACKUP_VERSION   Running GitLab: $RUNNING_VERSION"
if [ "${BACKUP_VERSION%-ee}" != "${RUNNING_VERSION%-ee}" ]; then
    echo "❌ Versions differ. Start gitlab/gitlab-ce:${BACKUP_VERSION}-ce.0 in docker-compose.yaml first."
    exit 1
fi

if [ "${FORCE:-}" != "yes" ]; then
    read -r -p "This replaces ALL current GitLab data with backup $BACKUP_ID. Type 'yes' to continue: " ANSWER
    [ "$ANSWER" = "yes" ] || { echo "Cancelled."; exit 1; }
fi

echo "=== [2/6] Restoring secrets and configuration ==="
# Without the matching gitlab-secrets.json, CI variables, runner tokens and
# 2FA can't be decrypted. Current files are kept next to them, just in case.
STAMP=$(date +%s)
docker exec gitlab_server cp /etc/gitlab/gitlab-secrets.json "/etc/gitlab/gitlab-secrets.json.before-restore.$STAMP"
docker exec gitlab_server cp /etc/gitlab/gitlab.rb "/etc/gitlab/gitlab.rb.before-restore.$STAMP"
docker cp "$BACKUP_DIR/gitlab-secrets.json" gitlab_server:/etc/gitlab/gitlab-secrets.json
docker cp "$BACKUP_DIR/gitlab.rb" gitlab_server:/etc/gitlab/gitlab.rb
docker exec gitlab_server chown root:root /etc/gitlab/gitlab-secrets.json /etc/gitlab/gitlab.rb
docker exec gitlab_server chmod 600 /etc/gitlab/gitlab-secrets.json /etc/gitlab/gitlab.rb
# A restart re-runs GitLab's configuration with the restored secrets.
docker restart gitlab_server >/dev/null
bash "$SCRIPT_DIR/health_check.sh" 900

echo "=== [3/6] Copying the backup into GitLab ==="
docker cp "$BACKUP_FILE" gitlab_server:/var/opt/gitlab/backups/
docker exec gitlab_server chown git:git "/var/opt/gitlab/backups/${BACKUP_ID}_gitlab_backup.tar"

echo "=== [4/6] Stopping the services that write to the database ==="
docker exec gitlab_server gitlab-ctl stop puma
docker exec gitlab_server gitlab-ctl stop sidekiq

echo "=== [5/6] Restoring (may take several minutes) ==="
docker exec -e GITLAB_ASSUME_YES=1 gitlab_server gitlab-backup restore BACKUP="$BACKUP_ID" force=yes

echo "=== [6/6] Restarting and checking ==="
docker restart gitlab_server >/dev/null
bash "$SCRIPT_DIR/health_check.sh" 900
docker exec gitlab_server gitlab-rake gitlab:check SANITIZE=true || true
docker exec gitlab_server gitlab-rake gitlab:doctor:secrets

echo "✅ GitLab restored from backup $BACKUP_ID"
