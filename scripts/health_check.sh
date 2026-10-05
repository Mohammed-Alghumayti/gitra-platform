#!/bin/bash
# Waits for GitLab to become reachable instead of checking only once.
# Usage: ./scripts/health_check.sh [max_wait_seconds]   (default: 300 = 5 minutes)

MAX_WAIT="${1:-300}"
INTERVAL=10
ELAPSED=0

echo "=== Checking GitLab Container Status ==="

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 || echo "000")
    # 301 = redirect to HTTPS, 302 = redirect to the sign-in page.
    if [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 301 ] || [ "$STATUS_CODE" -eq 302 ]; then
        echo "✅ GitLab is UP and healthy! (HTTP Status: $STATUS_CODE)"
        exit 0
    fi
    printf "⏳ Not ready yet (HTTP %s) — waited %ss / %ss\n" "$STATUS_CODE" "$ELAPSED" "$MAX_WAIT"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "❌ GitLab did not become healthy within ${MAX_WAIT}s. Check logs with:"
echo "   docker logs gitlab_server --tail 100"
exit 1
