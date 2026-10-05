#!/bin/bash
# Runs gitlab_bootstrap.rb inside the GitLab container over SSH (from GitHub
# Actions) and prints its KEY=VALUE output.
# Usage: run_gitlab_bootstrap.sh <need_runner 0|1> <skip_pat 0|1>
# Env: GITLAB_ROOT_PASSWORD, DEPLOY_USER, GITLAB_VM_IP, SSH_OPTS
set -euo pipefail

NEED_RUNNER="$1"
SKIP_PAT="$2"
: "${GITLAB_ROOT_PASSWORD:?}" "${DEPLOY_USER:?}" "${GITLAB_VM_IP:?}" "${SSH_OPTS:?}"
VM="$DEPLOY_USER@$GITLAB_VM_IP"
DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC2086
scp $SSH_OPTS "$DIR/gitlab_bootstrap.rb" "$VM:/tmp/gitlab_bootstrap.rb"
# Secrets go through stdin into a root-only env file, never on a command line.
# shellcheck disable=SC2086
printf 'ROOT_PASSWORD=%s\nNEED_RUNNER=%s\nSKIP_PAT=%s\n' "$GITLAB_ROOT_PASSWORD" "$NEED_RUNNER" "$SKIP_PAT" | \
    ssh $SSH_OPTS "$VM" "sudo sh -c 'umask 077; cat > /root/gitra-bootstrap.env'"
# shellcheck disable=SC2086
ssh $SSH_OPTS "$VM" "sudo sh -c 'docker cp /tmp/gitlab_bootstrap.rb gitlab_server:/tmp/gitlab_bootstrap.rb \
    && docker exec --env-file /root/gitra-bootstrap.env gitlab_server gitlab-rails runner /tmp/gitlab_bootstrap.rb; \
    rc=\$?; rm -f /root/gitra-bootstrap.env /tmp/gitlab_bootstrap.rb; exit \$rc'"
