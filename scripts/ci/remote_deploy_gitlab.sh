#!/bin/bash
# Deploys/updates GitLab on the GitLab VM. Runs as root over SSH from GitHub
# Actions: ssh vm "sudo bash -s -- <repo_url> <branch> <external_url>" < this file
# Safe to re-run: existing GitLab data is kept and reused.
set -euo pipefail

REPO_URL="$1"
BRANCH="$2"
EXTERNAL_URL="$3"
APP_DIR="${APP_DIR:-/opt/gitra-platform}"

echo "=== [1/5] Packages: Docker, git, fail2ban ==="
export DEBIAN_FRONTEND=noninteractive
if ! command -v git >/dev/null || ! command -v fail2ban-client >/dev/null; then
    apt-get update -y -q
    apt-get install -y -q git curl fail2ban
fi
systemctl enable --now fail2ban
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi

echo "--- Server status ---"
free -m | awk 'NR<=2'
docker ps -a --format '  {{.Names}}: {{.Status}} ({{.Image}})' || true

echo "=== [2/5] Code: $BRANCH → $APP_DIR ==="
if [ ! -d "$APP_DIR/.git" ]; then
    mkdir -p "$APP_DIR"
    git -C "$APP_DIR" init -q
    git -C "$APP_DIR" remote add origin "$REPO_URL"
fi
git -C "$APP_DIR" remote set-url origin "$REPO_URL"
git -C "$APP_DIR" fetch -q --depth 1 origin "$BRANCH"
git -C "$APP_DIR" checkout -q -f -B "$BRANCH" FETCH_HEAD
echo "GITLAB_EXTERNAL_URL=$EXTERNAL_URL" > "$APP_DIR/.env"

echo "=== [3/5] Reusing existing GitLab data (if any) ==="
# A GitLab started earlier by hand may live in another folder. Move its data
# into $APP_DIR so nothing is lost (same-disk move = instant rename).
if docker inspect gitlab_server >/dev/null 2>&1; then
    OLD_CONFIG=$(docker inspect gitlab_server --format '{{range .Mounts}}{{if eq .Destination "/etc/gitlab"}}{{.Source}}{{end}}{{end}}')
    OLD_DATA_DIR=$(dirname "$(dirname "$OLD_CONFIG")")
    if [ -n "$OLD_CONFIG" ] && [ "$OLD_DATA_DIR" != "$APP_DIR" ]; then
        echo "Found GitLab data in $OLD_DATA_DIR/gitlab — moving it to $APP_DIR/gitlab"
        docker rm -f gitlab_server
        if [ -e "$APP_DIR/gitlab" ]; then
            mv "$APP_DIR/gitlab" "$APP_DIR/gitlab.replaced.$(date +%s)"
        fi
        mv "$OLD_DATA_DIR/gitlab" "$APP_DIR/gitlab"
    fi
fi

echo "=== [4/5] Starting GitLab ==="
bash "$APP_DIR/scripts/deploy.sh"
bash "$APP_DIR/scripts/health_check.sh" 900

echo "=== [5/5] Security settings ==="
bash "$APP_DIR/scripts/harden_gitlab.sh"

echo "✅ GitLab deployed at $EXTERNAL_URL"
