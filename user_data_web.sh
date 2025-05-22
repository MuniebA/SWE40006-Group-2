#!/bin/bash
set -euxo pipefail

# Log everything for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting Web Instance User Data Script ==="
echo "Docker image tag: ${docker_image_tag}"
echo "Monitor IP: ${monitor_ip}"

# Update system
yum update -y
dnf install -y docker git mysql

# Start Docker
systemctl enable --now docker

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Clone repository
cd /home/ec2-user
if [ -d "app" ]; then
    cd app
    git pull origin main
    cd ..
else
    git clone https://github.com/MuniebA/SWE40006-Group-2.git app
fi

cd app
chown -R ec2-user:ec2-user /home/ec2-user/app

# Create environment file
cat > .env << EOF
FLASK_APP=run.py
FLASK_ENV=production
SECRET_KEY=production-secret-key-change-this
DATABASE_URL=mysql+pymysql://root:rootpassword@db:3306/testdb
MONITOR_IP=${monitor_ip}
EOF

# Update docker-compose.yml to use specific image tag if not latest
if [ "${docker_image_tag}" != "latest" ]; then
    sed -i "s|munieb/student-registration:latest|munieb/student-registration:${docker_image_tag}|g" docker-compose.yml
fi

# Pull the latest images
docker-compose pull

# Start containers
docker-compose up -d

# Wait for database to be ready
echo "Waiting for database to be ready..."
sleep 30

# Initialize database and run migrations
echo "Initializing database..."
docker-compose exec -T web python -c "
from app import create_app, db
app = create_app('production')
with app.app_context():
    db.create_all()
    print('Database initialized successfully')
" || echo "Database initialization failed"

# Run database migrations if they exist
echo "Running database migrations..."
docker-compose exec -T web flask db upgrade || echo "No migrations to run"

# Start Node Exporter for Prometheus monitoring
echo "Starting Node Exporter for monitoring..."
docker run -d \
  --name=node-exporter \
  --restart=always \
  --net=host \
  --pid=host \
  -v /:/host:ro,rslave \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host

# Install and configure application metrics exporter (optional)
echo "Setting up application metrics..."
docker-compose exec -T web python -c "
import requests
try:
    # Test if metrics endpoint exists
    response = requests.get('http://localhost:5000/metrics', timeout=5)
    if response.status_code == 200:
        print('✅ Application metrics endpoint is working')
    else:
        print('⚠️ Application metrics endpoint not found')
except Exception as e:
    print(f'⚠️ Could not test metrics endpoint: {e}')
" || echo "Metrics endpoint test skipped"

# Create health check script
cat > /home/ec2-user/health_check.sh << 'HEALTH_EOF'
#!/bin/bash
# Health check script for the web application

echo "=== Application Health Check ==="
echo "Timestamp: $(date)"

# Check if containers are running
echo "Docker containers status:"
docker-compose ps

# Check application response
echo "Testing application response:"
if curl -f -s http://localhost/ > /dev/null; then
    echo "✅ Web application is responding"
else
    echo "❌ Web application is not responding"
    echo "Container logs:"
    docker-compose logs --tail=20
fi

# Check database connectivity
echo "Testing database connectivity:"
docker-compose exec -T web python -c "
from app import create_app, db
from sqlalchemy import text
app = create_app('production')
with app.app_context():
    try:
        db.session.execute(text('SELECT 1'))
        print('✅ Database connection successful')
    except Exception as e:
        print(f'❌ Database connection failed: {e}')
" || echo "Database test failed"

echo "=== Health Check Complete ==="
HEALTH_EOF

chmod +x /home/ec2-user/health_check.sh
chown ec2-user:ec2-user /home/ec2-user/health_check.sh

# Run initial health check
sleep 10
/home/ec2-user/health_check.sh

# Verify application is running
if curl -f http://localhost/ > /dev/null 2>&1; then
    echo "✅ Web application is running successfully!"
    echo "✅ Node Exporter is running for monitoring"
else
    echo "❌ Application health check failed"
    docker-compose logs
fi

echo "=== Web Instance User Data Script Completed ==="