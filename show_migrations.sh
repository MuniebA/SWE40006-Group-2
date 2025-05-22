# show_migrations.sh - Script to show migration status
#!/bin/bash

echo "=== Database Migration Status ==="

# Activate virtual environment
source venv/bin/activate

echo "Current migration status:"
flask db current

echo ""
echo "Migration history:"
flask db history

echo ""
echo "Available migrations:"
ls -la migrations/versions/