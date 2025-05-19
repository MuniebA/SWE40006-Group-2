pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_DEBUG = 'true'
        DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration'
        TEST_DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration_test'
        DOCKER_IMAGE_NAME = 'student-registration-system'
        DOCKER_IMAGE_TAG = "${BUILD_NUMBER}"
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
                    service mysql status || true
                    
                    echo "Database List:"
                    mysql -u jenkins -ppassword -e "SHOW DATABASES;" || true
                    
                    echo "Jenkins User Permissions:"
                    mysql -u jenkins -ppassword -e "SHOW GRANTS;" || true
                '''
            }
        }
        
        stage('Run Database Tests') {
            steps {
                sh '''#!/bin/bash
                    # Activate using . instead of source
                    . $VENV_DIR/bin/activate
                    
                    # Run pytest for database tests
                    python -m pytest tests/ -v -k "database"
                '''
            }
        }

        stage('Verify Docker') {
            steps {
                echo 'Verifying Docker installation...'
                sh '''
                    # Check Docker is installed
                    docker --version
                    
                    # Check Docker Compose is installed
                    docker-compose --version
                    
                    # Verify Docker can run containers
                    docker run hello-world
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                echo 'Building Docker image...'
                sh '''
                    # Build the Docker image with a unique tag
                    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .
                    
                    # Also tag as latest
                    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG $DOCKER_IMAGE_NAME:latest
                    
                    # List images to verify
                    docker images | grep $DOCKER_IMAGE_NAME
                '''
            }
        }
        
        stage('Docker Tests') {
            steps {
                sh '''
                    # Check if port 3306 is in use
                    if netstat -tuln | grep -q ":3306"; then
                        echo "Port 3306 is already in use. Modifying docker-compose.yml to use port 3307 instead..."
                        sed -i 's/"3306:3306"/"3307:3306"/g' docker-compose.yml
                    fi
                    
                    # Ensure Flask debug is enabled in docker-compose.yml
                    grep -q "FLASK_DEBUG" docker-compose.yml || echo "Warning: FLASK_DEBUG not set in docker-compose.yml"
                    
                    # Bring down any existing containers
                    docker-compose down -v
                    
                    # Start Docker Compose with database and web app
                    docker-compose up -d
                    
                    echo "Waiting for containers to start..."
                    sleep 20
                    
                    # Show running containers
                    docker-compose ps
                    
                    # Inspect the logs to debug any issues
                    echo "Checking web container logs for errors:"
                    docker-compose logs web
                    
                    # Direct database connectivity test
                    echo "Testing database connection directly from web container:"
                    docker-compose exec -T web python -c "
from app import create_app, db
app = create_app('testing')  # or whatever config you use in Docker
with app.app_context():
    try:
        db.session.execute('SELECT 1')
        print('✅ Database connection successful')
    except Exception as e:
        print('❌ Database connection failed:', e)
" || true
                    
                    # Run the tests
                    . venv/bin/activate && python -m pytest tests/ -v -k docker
                    
                    # Detailed error logs after test runs (especially if they fail)
                    echo "Checking detailed web container logs after tests:"
                    docker-compose logs --tail=50 web
                    
                    # Try to get Gunicorn error logs
                    echo "Checking Gunicorn error logs (if available):"
                    docker-compose exec -T web bash -c "cat /var/log/gunicorn/* 2>/dev/null || echo 'No Gunicorn logs found'" || true
                    
                    # Check application error logs
                    echo "Checking application error logs (if available):"
                    docker-compose exec -T web bash -c "cat /app/logs/app.log 2>/dev/null || echo 'No application logs found'" || true

                    echo "Checking Flask application error details:"
                    docker-compose exec -T web python -c "
from app import create_app
app = create_app('testing')
with app.test_client() as client:
    response = client.post('/register', data={
        'username': 'test_user',
        'email': 'test@example.com',
        'password': 'Password123!',
        'confirm_password': 'Password123!'
    })
    print(f'Status code: {response.status_code}')
    print(f'Response data: {response.data.decode()}')
" || true
                    
                    # Additional detailed error information
                    echo "Getting detailed error information from Flask app:"
                    docker-compose exec -T web bash -c "
# Check Flask configuration
echo 'Flask Config:'
python -c 'import os; print(\"FLASK_DEBUG=\", os.environ.get(\"FLASK_DEBUG\")); print(\"FLASK_ENV=\", os.environ.get(\"FLASK_ENV\"))'

# Check database configuration 
echo 'Database Config:'
python -c 'import os; print(\"DATABASE_URL=\", os.environ.get(\"DATABASE_URL\"))'

# Test database connection directly
echo 'Testing database connection:'
python -c 'from app import db;
app = create_app(\"testing\");
try:
    db.session.execute(\"SELECT 1\");
    print(\"Database connection OK\")
except Exception as e:
    print(\"Database error:\", e)'
" || true
                '''
            }
            post {
                always {
                    sh '''
                        echo "Shutting down Docker Compose environment..."
                        docker-compose down -v
                    '''
                }
                failure {
                    sh '''
                        echo "Test failed! Capturing final container logs:"
                        docker-compose logs || true
                    '''
                }
            }
        }

        stage('Build Success') {
            steps {
                echo '✅ Student Registration System built and tested successfully!'
            }
        }
        
        stage('Push Docker Image') {
            when {
                branch 'main'  // Only run on main branch
            }
            steps {
                echo 'Pushing Docker image to registry...'
                sh '''
                    # Example - replace with your actual registry
                    # docker tag $DOCKER_IMAGE_NAME:latest your-registry/student-registration:latest
                    # docker push your-registry/student-registration:latest
                    
                    echo "Docker image would be pushed to registry here."
                    echo "Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                '''
            }
        }
    }
    
    post {
        always {
            echo 'Cleaning up workspace...'
            sh '''
                # Clean up test database
                mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;" || true
                
                # Clean up Docker resources
                docker-compose down -v || true
                docker system prune -f || true
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