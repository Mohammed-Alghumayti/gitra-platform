cat << 'EOF' > scripts/deploy.sh
#!/bin/bash
set -e

COMPOSE_FILE="docker-compose.yaml"

echo "=== [1/3] Checking Docker Compose file ==="
if [ ! -f "$COMPOSE_FILE" ] && [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yaml not found in current directory!"
    exit 1
fi
echo "✅ Found Docker Compose file."

echo "=== [2/3] Creating Persistent Storage Directories ==="
mkdir -p ./gitlab/config ./gitlab/logs ./gitlab/data
sudo chmod -R 777 ./gitlab

echo "=== [3/3] Launching GitLab Services via Docker Compose ==="
docker compose up -d

echo "✅ GitLab Deployment Triggered successfully!"
EOF
