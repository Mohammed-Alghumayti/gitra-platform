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

# Repair file permissions if GitLab can't read its own files. An earlier
# `chmod -R 700` on the data folders locks GitLab's internal users (git,
# gitlab-www, ...) out of their own files: Puma won't start and GitLab's
# configuration run fails. Waits for that first run before checking.
PUMA_RB=/var/opt/gitlab/gitlab-rails/etc/puma.rb
for _ in $(seq 1 60); do
    docker exec gitlab_server test -f "$PUMA_RB" 2>/dev/null && break
    sleep 10
done
# GitLab's "git" user must be able to read its config and enter its folders.
git_can_access() {
    docker exec -u git gitlab_server sh -c "test -r $PUMA_RB \
        && test -x /var/opt/gitlab/gitlab-ci && test -x /var/opt/gitlab/gitlab-rails \
        && test -x /var/opt/gitlab/git-data" 2>/dev/null
}
if ! git_can_access; then
    echo "GitLab can't read its own files — repairing permissions..."
    # 1. Make folders passable again (from the host, so it works even if the
    #    container keeps restarting). PostgreSQL's data must stay private.
    find "$APP_DIR/gitlab/data" -type d ! -path "*/postgresql*" -exec chmod u+rwx,go+rx {} +
    find "$APP_DIR/gitlab/logs" -type d -exec chmod u+rwx,go+rx {} +
    docker restart gitlab_server >/dev/null
    for _ in $(seq 1 60); do
        docker exec gitlab_server true 2>/dev/null && break
        sleep 5
    done
    # 2. Correct owners, then 3. restart: GitLab's startup configuration run
    #    resets the exact permissions of everything it manages.
    docker exec gitlab_server update-permissions >/dev/null 2>&1
    docker restart gitlab_server >/dev/null
    echo "✅ Permissions repaired — GitLab is restarting."
fi

bash "$APP_DIR/scripts/health_check.sh" 900

echo "=== [5/5] Security settings ==="
bash "$APP_DIR/scripts/harden_gitlab.sh"

echo "✅ GitLab deployed at $EXTERNAL_URL"
