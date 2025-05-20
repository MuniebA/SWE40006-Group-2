pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_DEBUG = 'true'
        DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration'
        TEST_DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration_test'
        DOCKER_IMAGE_NAME = 'korosensei001/student-registration'
        DOCKER_IMAGE_TAG = "${BUILD_NUMBER}"
        DOCKER_HUB_CREDENTIALS = credentials('docker-hub-credentials')
        AWS_CREDENTIALS = credentials('aws-credentials')
        TERRAFORM_VERSION = "1.12.0"  // Specify the version you want to use
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
                    
                    # Activate virtual environment
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
                    
                    # Test MySQL connectivity
                    echo "Testing MySQL connection..."
                    if ! mysql -u jenkins -ppassword -e "SELECT 1"; then
                        echo "ERROR: Cannot connect to MySQL server!"
                        exit 1
                    fi
                    
                    # Create test database
                    echo "Preparing test database..."
                    mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;"
                    mysql -u jenkins -ppassword -e "CREATE DATABASE student_registration_test;"
                    
                    # Initialize schema
                    mysql -u jenkins -ppassword student_registration_test < init.sql
                    
                    echo "Database setup completed successfully!"
                '''
            }
        }

        stage('Run Basic Tests') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    . $VENV_DIR/bin/activate
                    
                    # Run non-Docker tests
                    python -m pytest tests/ -v -k "not docker and not database"
                '''
            }
        }
        
        stage('Run Database Tests') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    . $VENV_DIR/bin/activate
                    
                    # Run database tests
                    python -m pytest tests/ -v -k "database"
                '''
            }
        }

        stage('Verify Docker') {
            steps {
                sh '''
                    # Check Docker installation
                    docker --version
                    docker-compose --version
                    docker run hello-world
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
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
                    
                    # Bring down any existing containers
                    docker-compose down -v
                    
                    # Start Docker Compose with database and web app
                    docker-compose up -d
                    
                    echo "Waiting for containers to start..."
                    sleep 20
                    
                    # Show running containers
                    docker-compose ps
                    
                    # Test database connection in container
                    echo "Testing database connection in container:"
                    docker-compose exec -T web python -c "
from app import create_app, db
from sqlalchemy import text
app = create_app('testing')
with app.app_context():
    try:
        db.session.execute(text('SELECT 1'))
        print('✅ Database connection successful')
    except Exception as e:
        print('❌ Database connection failed:', e)
" || true
                    
                    # Run the Docker tests
                    . venv/bin/activate && python -m pytest tests/ -v -k docker
                '''
            }
            post {
                always {
                    sh 'docker-compose down -v'
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                sh '''
                    # Login to Docker Hub
                    echo $DOCKER_HUB_CREDENTIALS_PSW | docker login -u $DOCKER_HUB_CREDENTIALS_USR --password-stdin
                    
                    # Push the Docker image
                    docker push $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG
                    docker push $DOCKER_IMAGE_NAME:latest
                    
                    # Logout to clean up credentials
                    docker logout
                '''
            }
        }
        
        stage('Install Terraform') {
            steps {
                sh '''
                    # Install Terraform without requiring sudo or unzip
                    echo "Installing Terraform ${TERRAFORM_VERSION}..."
                    mkdir -p ${WORKSPACE}/terraform
                    cd ${WORKSPACE}/terraform
                    
                    # Use Python to download and extract Terraform (Python should be available since you're using it for your app)
                    python3 -c '
import urllib.request
import zipfile
import os
import sys

version = os.environ.get("TERRAFORM_VERSION", "1.7.4")
url = f"https://releases.hashicorp.com/terraform/{version}/terraform_{version}_linux_amd64.zip"
zip_path = "terraform.zip"

print(f"Downloading Terraform {version}...")
urllib.request.urlretrieve(url, zip_path)

print("Extracting Terraform binary...")
with zipfile.ZipFile(zip_path, "r") as zip_ref:
    zip_ref.extractall(".")

os.chmod("terraform", 0o755)
print("Terraform installed successfully!")
'
                    
                    # Add to PATH for this session
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Verify installation
                    ./terraform version
                '''
            }
        }
        
        stage('Deploy to AWS with Terraform') {
            steps {
                sh '''
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1  # Adjust if needed
                    
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Initialize Terraform
                    terraform init
                    
                    # Plan the changes
                    terraform plan -out=tfplan
                    
                    # Apply the changes
                    terraform apply -auto-approve tfplan
                    
                    # Extract and display the EC2 IP address
                    echo "===================================================="
                    echo "                DEPLOYMENT DETAILS                   "
                    echo "===================================================="
                    
                    # Output all Terraform outputs
                    echo "All Terraform outputs:"
                    terraform output
                    
                    # Extract and highlight the EC2 IP address specifically
                    echo "Extracting website URL information..."
                    if terraform output -json | grep -q "instance_ip"; then
                        EC2_IP=$(terraform output -raw instance_ip || terraform output -json | grep -o '"instance_ip":[^,}]*' | cut -d ':' -f2 | tr -d '\\"' || echo "Not found")
                        echo "===================================================="
                        echo "🌐 WEBSITE URL: http://$EC2_IP/"
                        echo "===================================================="
                        
                        # Save the IP address to a file for later use
                        echo "$EC2_IP" > ec2_ip.txt
                    else
                        echo "Warning: Could not find instance_ip in Terraform outputs"
                        echo "Available outputs:"
                        terraform output
                    fi
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
                
                # Clean up Terraform files
                rm -rf ${WORKSPACE}/terraform || true
            '''
            // cleanWs()
        }
        
        success {
            echo 'Build, test, and deployment completed successfully!'
        }
        
        failure {
            echo 'Pipeline failed! Check the logs for details.'
            
            // Optional: Roll back Terraform changes if deployment failed
            sh '''
                if [ -d .terraform ]; then
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    echo "Attempting to roll back Terraform changes..."
                    terraform destroy -auto-approve || true
                fi
            '''
        }
    }
}