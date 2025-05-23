#!/bin/bash
# setup-cicd.sh
# Automated setup script for CI/CD pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running on EC2 instance
check_environment() {
    print_header "Checking Environment"
    
    # Check if we're on EC2
    if curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        print_status "Running on EC2 instance"
        INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
        print_status "Instance ID: $INSTANCE_ID"
        print_status "Public IP: $PUBLIC_IP"
        return 0
    else
        print_warning "Not running on EC2 instance"
        return 1
    fi
}

# Setup EC2 instance for CI/CD
setup_ec2_cicd() {
    print_header "Setting up EC2 for CI/CD"
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running!"
        exit 1
    fi
    
    print_status "Docker is available"
    
    # Stop any existing containers from Terraform deployment
    print_status "Cleaning up existing containers..."
    docker-compose down -v 2>/dev/null || true
    docker stop student-registration-web 2>/dev/null || true
    docker rm student-registration-web 2>/dev/null || true
    
    # Pull latest image
    print_status "Pulling latest Docker image..."
    if ! docker pull munieb/student-registration:latest; then
        print_error "Failed to pull Docker image. Make sure you have pushed the image to Docker Hub."
        exit 1
    fi
    
    # Start the application
    print_status "Starting application container..."
    docker run -d \
        --name student-registration-web \
        --restart unless-stopped \
        -p 80:5000 \
        -e FLASK_ENV=production \
        -e FLASK_CONFIG=production \
        munieb/student-registration:latest
    
    # Wait for startup
    print_status "Waiting for application to start..."
    sleep 15
    
    # Health check
    print_status "Performing health check..."
    for i in {1..12}; do
        if curl -f -s http://localhost/ >/dev/null; then
            print_status "✅ Application is running successfully!"
            break
        fi
        echo "Health check attempt $i/12..."
        sleep 10
        
        if [ $i -eq 12 ]; then
            print_error "Health check failed!"
            print_error "Container logs:"
            docker logs --tail 20 student-registration-web
            exit 1
        fi
    done
    
    # Create utility scripts
    create_utility_scripts
    
    # Setup log rotation
    setup_log_rotation
    
    # Setup automated cleanup
    setup_cleanup_cron
    
    print_status "EC2 setup completed successfully!"
}

# Create utility scripts
create_utility_scripts() {
    print_status "Creating utility scripts..."
    
    # Health check script
    cat > ~/health-check.sh << 'EOF'
#!/bin/bash
echo "Checking application health..."

if curl -f -s http://localhost/ >/dev/null; then
    echo "✅ Application is healthy"
    echo "Container status:"
    docker ps -f name=student-registration-web --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 0
else
    echo "❌ Application is not responding"
    echo "Container status:"
    docker ps -a -f name=student-registration-web --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo "Recent logs:"
    docker logs --tail 10 student-registration-web
    exit 1
fi
EOF
    chmod +x ~/health-check.sh
    
    # Rollback script
    cat > ~/rollback.sh << 'EOF'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: $0 <tag_number>"
    echo "Available tags:"
    docker images munieb/student-registration --format "table {{.Tag}}\t{{.CreatedAt}}" | grep -E "^[0-9]+\s" | head -10
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

echo "Waiting for container to start..."
sleep 15

if curl -f -s http://localhost/ >/dev/null; then
    echo "✅ Rollback to version $TAG successful!"
else
    echo "❌ Rollback failed!"
    docker logs --tail 20 student-registration-web
    exit 1
fi
EOF
    chmod +x ~/rollback.sh
    
    # Cleanup script
    cat > ~/cleanup.sh << 'EOF'
#!/bin/bash
echo "Starting Docker cleanup..."

# Remove stopped containers
docker container prune -f

# Keep only last 5 versions of our application image
echo "Cleaning up old application images (keeping last 5)..."
docker images munieb/student-registration --format "{{.Tag}}" | grep -E "^[0-9]+$" | sort -nr | tail -n +6 | xargs -I {} docker rmi munieb/student-registration:{} 2>/dev/null || true

# Remove unused volumes and networks
docker volume prune -f
docker network prune -f

# Remove dangling images
docker image prune -f

echo "Docker cleanup completed."

# Show current disk usage
echo "Current disk usage:"
df -h /
echo "Docker space usage:"
docker system df
EOF
    chmod +x ~/cleanup.sh
    
    # Deploy script (for manual deployments)
    cat > ~/deploy.sh << 'EOF'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: $0 <tag_number>"
    exit 1
fi

TAG=$1
IMAGE_NAME="munieb/student-registration"

echo "Deploying $IMAGE_NAME:$TAG..."

# Pull new image
docker pull $IMAGE_NAME:$TAG

# Stop current container
docker stop student-registration-web || true
docker rm student-registration-web || true

# Start new container
docker run -d \
    --name student-registration-web \
    --restart unless-stopped \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e FLASK_CONFIG=production \
    $IMAGE_NAME:$TAG

echo "Waiting for container to start..."
sleep 15

if curl -f -s http://localhost/ >/dev/null; then
    echo "✅ Deployment of version $TAG successful!"
else
    echo "❌ Deployment failed!"
    docker logs --tail 20 student-registration-web
    exit 1
fi
EOF
    chmod +x ~/deploy.sh
    
    print_status "Utility scripts created successfully!"
}

# Setup log rotation
setup_log_rotation() {
    print_status "Setting up log rotation..."
    
    # Check if we can write to /etc/logrotate.d
    if [ -w /etc/logrotate.d ]; then
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
        print_status "Log rotation configured"
    else
        print_warning "Cannot write to /etc/logrotate.d - skipping log rotation setup"
    fi
}

# Setup automated cleanup cron job
setup_cleanup_cron() {
    print_status "Setting up automated cleanup..."
    
    # Add cleanup job to crontab (runs every Sunday at 2 AM)
    (crontab -l 2>/dev/null | grep -v "/home/ec2-user/cleanup.sh"; echo "0 2 * * 0 /home/ec2-user/cleanup.sh >> /var/log/docker-cleanup.log 2>&1") | crontab -
    
    print_status "Automated cleanup scheduled for Sundays at 2 AM"
}

# Generate Jenkins credential information
generate_jenkins_info() {
    print_header "Jenkins Credential Information"
    
    if [ -n "$PUBLIC_IP" ]; then
        echo -e "${GREEN}EC2 Public IP:${NC} $PUBLIC_IP"
        echo -e "${GREEN}SSH Command:${NC} ssh -i tf-ec2.pem ec2-user@$PUBLIC_IP"
        echo -e "${GREEN}Application URL:${NC} http://$PUBLIC_IP/"
        echo ""
        echo -e "${YELLOW}For Jenkins setup, you'll need:${NC}"
        echo "1. Create 'ec2-public-ip' secret with value: $PUBLIC_IP"
        echo "2. Create 'ec2-ssh-private-key' with the content of tf-ec2.pem"
        echo "3. Ensure docker-hub-credentials are configured"
        echo "4. Ensure aws-credentials are configured"
    fi
}

# Show available scripts
show_available_scripts() {
    print_header "Available Management Scripts"
    
    echo -e "${GREEN}Health Check:${NC} ~/health-check.sh"
    echo -e "${GREEN}Manual Rollback:${NC} ~/rollback.sh [tag_number]"
    echo -e "${GREEN}Manual Deploy:${NC} ~/deploy.sh [tag_number]"
    echo -e "${GREEN}Manual Cleanup:${NC} ~/cleanup.sh"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ~/health-check.sh"
    echo "  ~/rollback.sh 45"
    echo "  ~/deploy.sh 47"
    echo "  ~/cleanup.sh"
}

# Main execution
main() {
    print_header "CI/CD Setup Script"
    
    # Check if we're on EC2
    if check_environment; then
        # We're on EC2, set up for CI/CD
        setup_ec2_cicd
        generate_jenkins_info
        show_available_scripts
        
        print_header "Setup Complete!"
        print_status "Your EC2 instance is now ready for CI/CD deployments"
        print_status "Application is running at: http://$PUBLIC_IP/"
        
    else
        # We're not on EC2, show setup instructions
        print_header "Local Setup Instructions"
        print_warning "This script should be run on your EC2 instance"
        echo ""
        echo "To set up CI/CD:"
        echo "1. SSH to your EC2 instance:"
        echo "   ssh -i tf-ec2.pem ec2-user@YOUR_EC2_IP"
        echo ""
        echo "2. Run this script on the EC2 instance:"
        echo "   curl -sSL https://raw.githubusercontent.com/YOUR_REPO/main/setup-cicd.sh | bash"
        echo ""
        echo "3. Configure Jenkins credentials as shown in the Jenkins Setup Guide"
    fi
}

# Run main function
main "$@"