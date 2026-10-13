#!/bin/bash
# Waits for GitLab to become ready instead of checking only once.
# Usage: ./scripts/health_check.sh [max_wait_seconds]   (default: 300 = 5 minutes)
#
# Ready means both:
#   1. GitLab's application (Puma) answers its readiness check inside the
#      container. This works the same with HTTP or HTTPS.
#   2. The web server answers on port 80. 301 = redirect to HTTPS,
#      302 = redirect to the sign-in page.
# The HTTP answer alone isn't enough: nginx redirects before Rails has started.

MAX_WAIT="${1:-300}"
INTERVAL=10
ELAPSED=0

echo "=== Checking GitLab Container Status ==="

app_ready() {
    # No container (e.g. GitLab installed without Docker): rely on HTTP only.
    docker inspect gitlab_server >/dev/null 2>&1 || { echo "n/a"; return; }
    # curl already prints 000 when it can't connect.
    docker exec gitlab_server curl -s -o /dev/null -w "%{http_code}" \
        http://127.0.0.1:8080/-/readiness 2>/dev/null || true
}

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    APP=$(app_ready)
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 || true)
    APP="${APP:-000}"
    STATUS_CODE="${STATUS_CODE:-000}"
    if { [ "$APP" = "200" ] || [ "$APP" = "n/a" ]; } &&
       { [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 301 ] || [ "$STATUS_CODE" -eq 302 ]; }; then
        echo "✅ GitLab is UP and healthy! (app readiness: $APP, HTTP Status: $STATUS_CODE)"
        exit 0
    fi
    printf "⏳ Not ready yet (app readiness: %s, HTTP %s) — waited %ss / %ss\n" "$APP" "$STATUS_CODE" "$ELAPSED" "$MAX_WAIT"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "❌ GitLab did not become healthy within ${MAX_WAIT}s."
if docker inspect gitlab_server >/dev/null 2>&1; then
    echo "--- gitlab-ctl status ---"
    docker exec gitlab_server gitlab-ctl status 2>&1 | tail -20
    echo "--- last container logs ---"
    docker logs gitlab_server --tail 60 2>&1
fi
exit 1
