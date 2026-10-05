#!/bin/bash
# Registers the gitlab-runner container with GitLab (run once, on the runner VM).
# Usage: ./scripts/register_runner.sh <runner_token> [gitlab_url]
#   Token: GitLab → Admin → CI/CD → Runners → New instance runner
#          (tick "Run untagged jobs"). It starts with "glrt-".
#   URL:   defaults to GITLAB_EXTERNAL_URL from .env (written by cloud-init).
set -e

cd "$(dirname "$0")/.."

TOKEN="$1"
GITLAB_URL="$2"
if [ -z "$GITLAB_URL" ] && [ -f .env ]; then
    GITLAB_URL=$(grep '^GITLAB_EXTERNAL_URL=' .env | cut -d= -f2-)
fi
if [ -z "$TOKEN" ] || [ -z "$GITLAB_URL" ]; then
    echo "❌ Usage: $0 <runner_token> [gitlab_url]"
    exit 1
fi

echo "=== Registering GitLab Runner with $GITLAB_URL (docker executor) ==="
# The Docker socket is shared so jobs can build/run images on this VM.
docker exec gitlab-runner gitlab-runner register \
    --non-interactive \
    --url "$GITLAB_URL" \
    --token "$TOKEN" \
    --executor "docker" \
    --docker-image "docker:cli" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"

echo "✅ Runner registered. Check it in GitLab under Admin → CI/CD → Runners."
