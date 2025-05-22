#!/bin/bash
set -euxo pipefail

# Log everything for debugging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting EC2 User Data Script ==="
echo "Docker image tag: ${docker_image_tag}"

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

# Verify application is running
sleep 10
if curl -f http://localhost/ > /dev/null 2>&1; then
    echo "✅ Application is running successfully!"
else
    echo "❌ Application health check failed"
    docker-compose logs
fi

echo "=== EC2 User Data Script Completed ==="