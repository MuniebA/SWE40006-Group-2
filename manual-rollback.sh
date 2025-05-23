#!/bin/bash
# Manual rollback script for emergency situations
# Run this on the EC2 instance directly

echo "🚨 Starting manual rollback procedure..."

CONTAINER_NAME="student-registration-app"

# Get list of available images
echo "📋 Available Docker images:"
docker images munieb/student-registration --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}"

# Prompt for version to rollback to
echo "Enter the build number or 'latest' to rollback to:"
read -r ROLLBACK_VERSION

if [ -z "$ROLLBACK_VERSION" ]; then
    echo "❌ No version specified. Aborting rollback."
    exit 1
fi

ROLLBACK_IMAGE="munieb/student-registration:$ROLLBACK_VERSION"

echo "🔄 Rolling back to: $ROLLBACK_IMAGE"

# Stop current container
echo "🛑 Stopping current container..."
docker stop $CONTAINER_NAME || true
docker rm $CONTAINER_NAME || true

# Start rollback container
echo "🚀 Starting rollback container..."
docker run -d \
    --name $CONTAINER_NAME \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e DATABASE_URL=mysql+pymysql://testuser:testpass@mysql-prod:3306/testdb \
    --network app-network \
    --restart always \
    $ROLLBACK_IMAGE

# Wait and test
sleep 10

# Health check
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")

if [ "$HEALTH_CHECK" = "200" ]; then
    echo "✅ Rollback successful! Application is healthy."
    echo "🌐 Application is running on: $ROLLBACK_IMAGE"
else
    echo "❌ Rollback failed! Health check returned: $HEALTH_CHECK"
    echo "🆘 Manual intervention required!"
fi