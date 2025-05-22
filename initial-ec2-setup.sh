#!/bin/bash
# initial-ec2-setup.sh
# Run this script ONCE on your EC2 instance after Terraform deployment
# This prepares the instance for CI/CD deployments

set -e

echo "🚀 Setting up EC2 instance for CI/CD deployments..."

# Stop and remove the containers started by Terraform user_data
echo "Stopping existing containers from initial deployment..."
docker-compose down -v 2>/dev/null || true

# Remove any existing containers that might conflict
docker stop student-registration-web 2>/dev/null || true
docker rm student-registration-web 2>/dev/null || true

# Pull the latest image from Docker Hub
echo "Pulling latest Docker image..."
docker pull munieb/student-registration:latest

# Start the application container with the correct configuration
echo "Starting application container..."
docker run -d \
    --name student-registration-web \
    --restart unless-stopped \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e FLASK_CONFIG=production \
    munieb/student-registration:latest

# Wait for container to start
echo "Waiting for container to start..."
sleep 10

# Health check
echo "Performing health check..."
for i in {1..12}; do
    if curl -f http://localhost/ >/dev/null 2>&1; then
        echo "✅ Application is running successfully!"
        break
    fi
    echo "Health check attempt $i failed, retrying in 10 seconds..."
    sleep 10
    
    if [ $i -eq 12 ]; then
        echo "❌ Health check failed! Check container logs:"
        docker logs student-registration-web
        exit 1
    fi
done

# Create a simple health check script for monitoring
cat > /home/ec2-user/health-check.sh << 'EOF'
#!/bin/bash
# Simple health check script

if curl -f -s http://localhost/ >/dev/null; then
    echo "✅ Application is healthy"
    exit 0
else
    echo "❌ Application is not responding"
    echo "Container status:"
    docker ps -f name=student-registration-web
    echo "Recent logs:"
    docker logs --tail 10 student-registration-web
    exit 1
fi
EOF

chmod +x /home/ec2-user/health-check.sh

# Create a manual rollback script
cat > /home/ec2-user/rollback.sh << 'EOF'
#!/bin/bash
# Manual rollback script
# Usage: ./rollback.sh [tag_number]

if [ $# -eq 0 ]; then
    echo "Usage: $0 <tag_number>"
    echo "Available tags:"
    docker images munieb/student-registration --format "table {{.Tag}}" | grep -E "^[0-9]+$" | sort -nr | head -5
    exit 1
fi

TAG=$1
IMAGE_NAME="munieb/student-registration"

echo "Rolling back to $IMAGE_NAME:$TAG..."

# Stop current container
docker stop student-registration-web || true
docker rm student-registration-web || true

# Start with specified tag
docker run -d \
    --name student-registration-web \
    --restart unless-stopped \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e FLASK_CONFIG=production \
    $IMAGE_NAME:$TAG

echo "Rollback completed. Checking health..."
sleep 10

if curl -f http://localhost/ >/dev/null 2>&1; then
    echo "✅ Rollback successful!"
else
    echo "❌ Rollback failed!"
    exit 1
fi
EOF

chmod +x /home/ec2-user/rollback.sh

# Set up log rotation for Docker
echo "Setting up log rotation..."
sudo tee /etc/logrotate.d/docker > /dev/null << 'EOF'
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
}
EOF

# Create a monitoring script for disk usage
cat > /home/ec2-user/cleanup.sh << 'EOF'
#!/bin/bash
# Cleanup script to manage disk space

echo "Docker system cleanup..."

# Remove stopped containers
docker container prune -f

# Remove unused images (keep last 5 versions of our app)
echo "Cleaning up old Docker images..."
docker images munieb/student-registration --format "table {{.Tag}}" | grep -E "^[0-9]+$" | sort -nr | tail -n +6 | xargs -I {} docker rmi munieb/student-registration:{} 2>/dev/null || true

# Remove unused volumes and networks
docker volume prune -f
docker network prune -f

# Remove dangling images
docker image prune -f

echo "Cleanup completed."
EOF

chmod +x /home/ec2-user/cleanup.sh

# Set up a cron job for weekly cleanup
echo "Setting up automated cleanup..."
(crontab -l 2>/dev/null; echo "0 2 * * 0 /home/ec2-user/cleanup.sh >> /var/log/docker-cleanup.log 2>&1") | crontab -

echo "🎉 EC2 instance setup completed successfully!"
echo ""
echo "Available scripts:"
echo "  📊 Health check: ./health-check.sh"
echo "  🔄 Manual rollback: ./rollback.sh [tag_number]"
echo "  🧹 Manual cleanup: ./cleanup.sh"
echo ""
echo "Your application should be accessible at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/"