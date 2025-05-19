#!/bin/bash

# MySQL connection parameters
MYSQL_USER="jenkins"
MYSQL_PASS="password"

# Create/recreate test database
echo "Creating test database..."
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "DROP DATABASE IF EXISTS student_registration_test;"
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "CREATE DATABASE student_registration_test;"

# Import schema
echo "Importing schema to test database..."
mysql -u $MYSQL_USER -p$MYSQL_PASS student_registration_test < init.sql

echo "Database setup complete!"