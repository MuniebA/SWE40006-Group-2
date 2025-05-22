# migrate_production.sh - Script for production migrations
#!/bin/bash

echo "=== Production Database Migration ==="

# This script should be run on the production server
# It includes backup and rollback capabilities

# Backup database before migration
echo "Creating database backup..."
mysqldump -u root -p$MYSQL_ROOT_PASSWORD $MYSQL_DATABASE > backup_$(date +%Y%m%d_%H%M%S).sql

# Show current migration status
flask db current

# Run migrations
echo "Running database migrations..."
if flask db upgrade; then
    echo "✅ Migrations completed successfully!"
else
    echo "❌ Migration failed!"
    echo "To rollback, use: flask db downgrade [revision]"
    exit 1
fi

echo "New migration status:"
flask db current