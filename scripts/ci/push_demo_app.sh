#!/bin/bash
# Creates the demo project in GitLab (if missing), pushes sample-app/ to it,
# and waits for its pipeline. Runs in GitHub Actions.
# Env: GITLAB_URL, GITLAB_PAT
set -euo pipefail

: "${GITLAB_URL:?}" "${GITLAB_PAT:?}"
PROJECT="internal-demo-app"
API="$GITLAB_URL/api/v4"
AUTH=(-H "PRIVATE-TOKEN: $GITLAB_PAT")
SRC="$(cd "$(dirname "$0")/../../sample-app" && pwd)"
HOST="${GITLAB_URL#*://}"
SCHEME="${GITLAB_URL%%://*}"
REMOTE="$SCHEME://root:$GITLAB_PAT@$HOST/root/$PROJECT.git"

echo "=== [1/3] Project root/$PROJECT ==="
if ! curl -sf "${AUTH[@]}" "$API/projects/root%2F$PROJECT" >/dev/null; then
    curl -sf "${AUTH[@]}" -X POST "$API/projects" \
        --data-urlencode "name=$PROJECT" --data "visibility=internal" >/dev/null
    echo "Created."
fi

echo "=== [2/3] Pushing sample-app/ ==="
WORK=$(mktemp -d)
if ! git clone -q "$REMOTE" "$WORK" 2>/dev/null; then
    git -C "$WORK" init -q
fi
find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -a "$SRC/." "$WORK/"
git -C "$WORK" add -A
if git -C "$WORK" rev-parse -q --verify HEAD >/dev/null && git -C "$WORK" diff --cached --quiet; then
    echo "No changes in sample-app/ — nothing to push."
    exit 0
fi
git -C "$WORK" -c user.name="Gitra Deploy" -c user.email="deploy@gitra.local" \
    commit -q -m "Sync sample-app from GitHub ${GITHUB_SHA:-}"
git -C "$WORK" push -q "$REMOTE" HEAD:main
SHA=$(git -C "$WORK" rev-parse HEAD)

echo "=== [3/3] Waiting for the pipeline ==="
STATUS="pending"
for _ in $(seq 1 90); do
    STATUS=$(curl -sf "${AUTH[@]}" "$API/projects/root%2F$PROJECT/pipelines?sha=$SHA" | jq -r '.[0].status // "pending"')
    case "$STATUS" in
        success) echo "✅ Pipeline passed."; exit 0 ;;
        failed|canceled) echo "❌ Pipeline $STATUS — see $GITLAB_URL/root/$PROJECT/-/pipelines"; exit 1 ;;
    esac
    sleep 10
done
echo "❌ Pipeline still '$STATUS' after 15 minutes."
exit 1
