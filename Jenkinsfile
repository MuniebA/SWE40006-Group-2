pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_DEBUG = 'true'
        DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration'
        TEST_DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration_test'
    }

    stages {
        stage('Clone Repo') {
            steps {
                echo 'Repository cloned automatically'
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''#!/bin/bash
                    # Create virtual environment
                    python3 -m venv $VENV_DIR
                    
                    # Activate using . instead of source (compatible with all shells)
                    . $VENV_DIR/bin/activate
                    
                    # Install dependencies
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    pip install pytest pytest-cov
                '''
            }
        }

        stage('Setup Test Database') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    . $VENV_DIR/bin/activate
                    
                    # Echo database-related environment variables for debugging
                    echo "DATABASE_URL: $DATABASE_URL"
                    echo "TEST_DATABASE_URL: $TEST_DATABASE_URL"
                    
                    # Test MySQL connectivity first
                    echo "Testing MySQL connection..."
                    if ! mysql -u jenkins -ppassword -e "SELECT 1"; then
                        echo "ERROR: Cannot connect to MySQL server!"
                        exit 1
                    fi
                    
                    # Create test database with verbose output
                    echo "Dropping database if it exists..."
                    mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;"
                    
                    echo "Creating test database..."
                    mysql -u jenkins -ppassword -e "CREATE DATABASE student_registration_test;"
                    
                    # Verify database was created
                    echo "Verifying database creation..."
                    if ! mysql -u jenkins -ppassword -e "SHOW DATABASES LIKE 'student_registration_test';" | grep student_registration_test; then
                        echo "ERROR: Failed to create database!"
                        exit 1
                    fi
                    
                    # Initialize schema with verbose output
                    echo "Initializing database schema..."
                    mysql -u jenkins -ppassword student_registration_test < init.sql
                    
                    # Verify tables were created
                    echo "Verifying schema initialization..."
                    TABLE_COUNT=$(mysql -u jenkins -ppassword -e "SHOW TABLES FROM student_registration_test;" | wc -l)
                    if [ "$TABLE_COUNT" -lt "2" ]; then
                        echo "ERROR: Failed to initialize database schema! Only $TABLE_COUNT tables found."
                        exit 1
                    fi
                    
                    echo "Database setup completed successfully!"
                '''
            }
        }

        stage('Run Basic Tests') {
            steps {
                echo 'Running basic Python unit tests...'
                sh '''#!/bin/bash
                    # Activate using . instead of source
                    . $VENV_DIR/bin/activate
                    
                    # Run pytest for non-database, non-docker tests
                    python -m pytest tests/ -v -k "not docker and not database"
                '''
            }
        }

        stage('Debug Database') {
            steps {
                sh '''#!/bin/bash
                    echo "MySQL Status:"
                    sudo service mysql status || true
                    
                    echo "Database List:"
                    mysql -u jenkins -ppassword -e "SHOW DATABASES;" || true
                    
                    echo "Jenkins User Permissions:"
                    mysql -u jenkins -ppassword -e "SHOW GRANTS;" || true
                '''
            }
        }
        
        stage('Setup Test Database') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    . $VENV_DIR/bin/activate
                    
                    # Run database setup script
                    ./setup_db.sh
                '''
            }
        }

        stage('Build Success') {
            steps {
                echo '✅ Student Registration System built and tested successfully!'
            }
        }
    }
    
    post {
        always {
            echo 'Cleaning up workspace...'
            sh '''
                # Clean up test database
                mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;" || true
            '''
            // cleanWs()
        }
        
        success {
            echo 'Build completed successfully!'
        }
        
        failure {
            echo 'Build failed! Check the logs for details.'
        }
    }
}