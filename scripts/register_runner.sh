#!/bin/bash
# Registers the gitlab-runner container with GitLab (run once after deploy).
# Usage: ./scripts/register_runner.sh <runner_token>
#   Get the token in GitLab: Admin → CI/CD → Runners → New instance runner
#   (tick "Run untagged jobs"). It starts with "glrt-".
set -e

TOKEN="$1"
if [ -z "$TOKEN" ]; then
    echo "❌ Usage: $0 <runner_token>"
    exit 1
fi

echo "=== Registering GitLab Runner (docker executor) ==="
# Jobs reach GitLab over the internal gitlab-network, so they don't depend on
# the public IP. The Docker socket is shared so jobs can build/run images.
docker exec gitlab-runner gitlab-runner register \
    --non-interactive \
    --url "http://gitlab_server" \
    --clone-url "http://gitlab_server" \
    --token "$TOKEN" \
    --executor "docker" \
    --docker-image "docker:cli" \
    --docker-network-mode "gitlab-network" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"

echo "✅ Runner registered. Check it in GitLab under Admin → CI/CD → Runners."
