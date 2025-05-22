# create_migration.sh - Script to create new migrations
#!/bin/bash

echo "Creating new database migration..."

# Activate virtual environment
source venv/bin/activate

# Create migration with a descriptive message
read -p "Enter migration description: " migration_desc

if [ -z "$migration_desc" ]; then
    echo "Error: Migration description is required"
    exit 1
fi

# Generate migration
flask db migrate -m "$migration_desc"

echo "Migration created successfully!"
echo "Don't forget to:"
echo "1. Review the generated migration file in migrations/versions/"
echo "2. Test the migration with: flask db upgrade"
echo "3. Commit the migration file to git"
