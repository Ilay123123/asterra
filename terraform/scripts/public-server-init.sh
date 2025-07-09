#!/bin/bash

# ASTERRA DevOps Assignment - Simple Web Service Setup
# This script creates a minimal web service that passes ALB health checks

set -e  # Exit on any error
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== ASTERRA Web Service Setup Started ==="
echo "Timestamp: $(date)"

# Update system
echo "Updating system packages..."
apt-get update -y
apt-get install -y curl

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

# Wait for Docker service to be ready
echo "Waiting for Docker service..."
sleep 15

# Create nginx configuration file
echo "Creating nginx configuration..."
mkdir -p /opt/asterra-web
cat > /opt/asterra-web/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;

        location /health {
            return 200 'healthy\n';
            add_header Content-Type text/plain;
        }

        location / {
            return 200 'ASTERRA DevOps Assignment - Web Service Running!\nTimestamp: $time_iso8601\n';
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Start nginx container
echo "Starting nginx container..."
docker run -d \
    --name asterra-web \
    --restart unless-stopped \
    -p 80:80 \
    -v /opt/asterra-web/nginx.conf:/etc/nginx/nginx.conf:ro \
    nginx:latest

# Wait for container to start
echo "Waiting for container to start..."
sleep 10

# Test the service locally
echo "Testing web service..."
for i in {1..30}; do
    if curl -f http://localhost/health > /dev/null 2>&1; then
        echo "✓ Health check passed!"
        break
    else
        echo "Waiting for service... attempt $i/30"
        sleep 2
    fi
done

# Final status check
echo "=== Final Status Check ==="
docker ps
curl -s http://localhost/health || echo "Health check failed"
curl -s http://localhost/ || echo "Main page failed"

echo "=== ASTERRA Web Service Setup Completed ==="
echo "Service should be available at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/health"