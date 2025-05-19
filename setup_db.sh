#!/bin/bash

# MySQL connection parameters
MYSQL_USER="jenkins"
MYSQL_PASS="password"
DB_NAME="student_registration_test"

# Exit on any error
set -e

echo "Testing MySQL connection..."
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "SELECT 1;" || {
    echo "ERROR: Cannot connect to MySQL server!"
    exit 1
}

echo "Dropping database if it exists..."
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "DROP DATABASE IF EXISTS $DB_NAME;"

echo "Creating database..."
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "CREATE DATABASE $DB_NAME;"

echo "Verifying database was created..."
mysql -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q $DB_NAME || {
    echo "ERROR: Failed to create database!"
    exit 1
}

echo "Initializing schema..."
mysql -u $MYSQL_USER -p$MYSQL_PASS $DB_NAME < init.sql

echo "Verifying schema was initialized..."
TABLE_COUNT=$(mysql -u $MYSQL_USER -p$MYSQL_PASS -e "SHOW TABLES FROM $DB_NAME;" | wc -l)
if [ "$TABLE_COUNT" -lt "2" ]; then
    echo "ERROR: Schema initialization failed! Only $TABLE_COUNT tables found."
    exit 1
fi

echo "Database setup completed successfully!"