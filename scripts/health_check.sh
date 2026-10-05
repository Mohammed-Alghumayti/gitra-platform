#!/bin/bash
# Waits for GitLab to become ready instead of checking only once.
# Usage: ./scripts/health_check.sh [max_wait_seconds]   (default: 300 = 5 minutes)
#
# Ready means both:
#   1. The gitlab_server container reports "healthy" (GitLab's own health check,
#      which only passes once Rails and the database are up).
#   2. The web server answers on port 80. 301 = redirect to HTTPS,
#      302 = redirect to the sign-in page.
# The HTTP answer alone isn't enough: nginx redirects before Rails has started.

MAX_WAIT="${1:-300}"
INTERVAL=10
ELAPSED=0

echo "=== Checking GitLab Container Status ==="

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' gitlab_server 2>/dev/null || echo "missing")
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 || echo "000")
    if { [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "none" ]; } &&
       { [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 301 ] || [ "$STATUS_CODE" -eq 302 ]; }; then
        echo "✅ GitLab is UP and healthy! (container: $HEALTH, HTTP Status: $STATUS_CODE)"
        exit 0
    fi
    printf "⏳ Not ready yet (container: %s, HTTP %s) — waited %ss / %ss\n" "$HEALTH" "$STATUS_CODE" "$ELAPSED" "$MAX_WAIT"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "❌ GitLab did not become healthy within ${MAX_WAIT}s. Check logs with:"
echo "   docker logs gitlab_server --tail 100"
exit 1
