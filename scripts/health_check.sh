cat << 'EOF' > scripts/health_check.sh
#!/bin/bash

echo "=== Checking GitLab Container Status ==="

STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 || echo "000000")

if [ "$STATUS_CODE" -eq 200 ] || [ "$STATUS_CODE" -eq 302 ]; then
    echo "✅ GitLab is UP and healthy! (HTTP Status: $STATUS_CODE)"
else
    echo "⏳ GitLab is still starting up or unavailable. (HTTP Status: $STATUS_CODE)"
    echo "Note: GitLab usually takes 2 to 4 minutes on initial startup."
fi
EOF
