pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_DEBUG = 'true'
        DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration'
        TEST_DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration_test'
        DOCKER_IMAGE_NAME = 'munieb/student-registration'
        DOCKER_IMAGE_TAG = "${BUILD_NUMBER}"
        DOCKER_HUB_CREDENTIALS = credentials('docker-hub-credentials')
        AWS_CREDENTIALS = credentials('aws-credentials')
        TERRAFORM_VERSION = "1.12.0"
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
                    
                    # Use Python to download and extract Terraform
                    python3 -c '
import urllib.request
import zipfile
import os
import sys

version = os.environ.get("TERRAFORM_VERSION", "1.12.0")
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
        
        stage('Deploy Infrastructure with Terraform') {
            steps {
                sh '''
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
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
                    if terraform output -json | grep -q "ec2_public_ip"; then
                        EC2_IP=$(terraform output -raw ec2_public_ip || terraform output -json | grep -o '"ec2_public_ip":[^,}]*' | cut -d ':' -f2 | tr -d '\\"' || echo "Not found")
                        echo "===================================================="
                        echo "🌐 WEBSITE URL: http://$EC2_IP/"
                        echo "===================================================="
                        
                        # Save the IP address to a file for later use
                        echo "$EC2_IP" > ec2_ip.txt
                    else
                        echo "Warning: Could not find ec2_public_ip in Terraform outputs"
                        echo "Available outputs:"
                        terraform output
                    fi
                '''
            }
        }

        stage('Setup SSH Access') {
            steps {
                sh '''#!/bin/bash
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    echo "🔐 Setting up SSH access to EC2..."
                    
                    # Create SSH directory for jenkins user if it doesn't exist
                    sudo mkdir -p /var/lib/jenkins/.ssh
                    sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
                    sudo chmod 700 /var/lib/jenkins/.ssh
                    
                    # Extract the private key from Terraform output
                    terraform output -raw private_key_content > ec2-private-key.pem
                    chmod 600 ec2-private-key.pem
                    
                    # Copy key to Jenkins SSH directory
                    sudo cp ec2-private-key.pem /var/lib/jenkins/.ssh/ec2-key.pem
                    sudo chown jenkins:jenkins /var/lib/jenkins/.ssh/ec2-key.pem
                    sudo chmod 600 /var/lib/jenkins/.ssh/ec2-key.pem
                    
                    # Get EC2 IP for verification
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    echo "✅ SSH key setup complete!"
                    echo "🌐 EC2 Instance IP: $EC2_IP"
                    echo "🔐 SSH Key location: /var/lib/jenkins/.ssh/ec2-key.pem"
                    
                    # Wait for EC2 to be fully ready
                    echo "⏳ Waiting for EC2 instance to be fully ready..."
                    sleep 60
                    
                    # Test SSH connection
                    echo "🧪 Testing SSH connection..."
                    for i in {1..5}; do
                        if sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/ec2-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$EC2_IP "echo 'SSH connection successful!'"; then
                            echo "✅ SSH connection established!"
                            break
                        else
                            echo "⚠️ SSH attempt $i failed, retrying..."
                            sleep 30
                        fi
                    done
                '''
            }
        }
        
        stage('Install AWS CLI') {
            steps {
                sh '''#!/bin/bash
                    # Install AWS CLI using apt instead of pip to avoid externally-managed-environment error
                    echo "📦 Installing AWS CLI using system package manager..."
                    
                    # Update package list
                    sudo apt update
                    
                    # Install AWS CLI v2 using apt
                    if ! command -v aws &> /dev/null; then
                        echo "Installing AWS CLI v2..."
                        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                        
                        # Use Python to extract instead of unzip
                        python3 -c '
import zipfile
import os
with zipfile.ZipFile("awscliv2.zip", "r") as zip_ref:
    zip_ref.extractall(".")
'
                        
                        # Install AWS CLI
                        sudo ./aws/install
                        
                        # Clean up
                        rm -rf awscliv2.zip aws/
                    fi
                    
                    # Verify AWS CLI installation
                    aws --version
                    
                    # Test AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
                    aws sts get-caller-identity
                '''
            }
        }
        
        stage('Deploy Application to EC2') {
            steps {
                sh '''#!/bin/bash
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    if [ -z "$EC2_IP" ]; then
                        echo "❌ No EC2 instance IP found!"
                        exit 1
                    fi
                    
                    echo "🎯 Deploying to EC2 instance: $EC2_IP"
                    
                    # Create deployment script
                    cat > deploy.sh << 'EOF'
#!/bin/bash
set -e

DOCKER_IMAGE="$1"
CONTAINER_NAME="student-registration-app"

echo "🚀 Starting deployment of $DOCKER_IMAGE"

# Ensure Docker is running
sudo systemctl start docker || true

# Create network if it doesn't exist
docker network create app-network || true

# Check if MySQL container exists, if not create it
if ! docker ps -a --format 'table {{.Names}}' | grep -q mysql-prod; then
    echo "🗄️ Creating MySQL production container..."
    docker run -d \
        --name mysql-prod \
        --network app-network \
        --restart always \
        -e MYSQL_ROOT_PASSWORD=rootpassword \
        -e MYSQL_DATABASE=testdb \
        -e MYSQL_USER=testuser \
        -e MYSQL_PASSWORD=testpass \
        -v mysql-data:/var/lib/mysql \
        mysql:8.0
    
    # Wait for MySQL to be ready
    echo "⏳ Waiting for MySQL to be ready..."
    sleep 30
else
    # Start MySQL if it's stopped
    docker start mysql-prod || true
fi

# Get current running image for rollback
CURRENT_IMAGE=$(docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Image}}" | tail -n +2 | head -1)
echo "📋 Current image: $CURRENT_IMAGE"

# Pull new image
echo "⬇️ Pulling new image..."
docker pull $DOCKER_IMAGE

# Stop and remove old container
echo "🛑 Stopping old container..."
docker stop $CONTAINER_NAME || true
docker rm $CONTAINER_NAME || true

# Start new container
echo "🔄 Starting new container..."
docker run -d \
    --name $CONTAINER_NAME \
    --network app-network \
    --restart always \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e DATABASE_URL=mysql+pymysql://testuser:testpass@mysql-prod:3306/testdb \
    $DOCKER_IMAGE

# Wait for container to start
echo "⏳ Waiting for application to start..."
sleep 20

# Health check
echo "🏥 Performing health check..."
for i in {1..10}; do
    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
    if [ "$HEALTH_CHECK" = "200" ]; then
        echo "✅ Health check passed! Deployment successful."
        echo "🗑️ Cleaning up old images..."
        docker image prune -f
        exit 0
    else
        echo "⚠️ Health check attempt $i/10 failed - Status: $HEALTH_CHECK"
        sleep 10
    fi
done

echo "❌ Health check failed! Rolling back..."

# Stop failed container
docker stop $CONTAINER_NAME || true
docker rm $CONTAINER_NAME || true

# Rollback to previous image
if [ -n "$CURRENT_IMAGE" ] && [ "$CURRENT_IMAGE" != "REPOSITORY" ] && [ "$CURRENT_IMAGE" != "$DOCKER_IMAGE" ]; then
    echo "🔄 Rolling back to: $CURRENT_IMAGE"
    docker run -d \
        --name $CONTAINER_NAME \
        --network app-network \
        --restart always \
        -p 80:5000 \
        -e FLASK_ENV=production \
        -e DATABASE_URL=mysql+pymysql://testuser:testpass@mysql-prod:3306/testdb \
        $CURRENT_IMAGE
    echo "🔙 Rollback completed!"
else
    echo "⚠️ No previous image available for rollback!"
fi
exit 1
EOF

                    # Copy deployment script to EC2
                    echo "📤 Copying deployment script to EC2..."
                    scp -i /var/lib/jenkins/.ssh/ec2-key.pem -o StrictHostKeyChecking=no deploy.sh ec2-user@$EC2_IP:/tmp/
                    
                    # Execute deployment
                    echo "🚀 Executing deployment on EC2..."
                    ssh -i /var/lib/jenkins/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP \
                        "chmod +x /tmp/deploy.sh && /tmp/deploy.sh $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
                    echo "🎉 Deployment completed successfully!"
                    echo "🌐 Application URL: http://$EC2_IP/"
                '''
            }
        }

        stage('Post-Deployment Verification') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    # Perform comprehensive health check
                    echo "🔍 Performing post-deployment verification..."
                    
                    # Check if application is responding
                    for i in {1..5}; do
                        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP/ || echo "000")
                        if [ "$RESPONSE" = "200" ]; then
                            echo "✅ Application is responding correctly (attempt $i)"
                            break
                        else
                            echo "⚠️ Health check failed (attempt $i/5) - Status: $RESPONSE"
                            if [ $i -eq 5 ]; then
                                echo "❌ Final health check failed! Consider rollback."
                                exit 1
                            fi
                            sleep 10
                        fi
                    done
                    
                    echo "🎯 Final deployment verification complete!"
                    echo "📊 Application Status: HEALTHY"
                    echo "🌐 Access your application at: http://$EC2_IP/"
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
            echo '🎉 Build, test, and deployment completed successfully!'
            sh '''
                # Use local Terraform installation
                export PATH=${WORKSPACE}/terraform:$PATH
                
                # Get instance IP for final message
                EC2_IP=$(terraform output -raw ec2_public_ip || echo "Unknown")
                
                echo "════════════════════════════════════════════════════════"
                echo "🎉 DEPLOYMENT SUCCESSFUL!"
                echo "📦 Docker Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                echo "🌐 Application URL: http://$EC2_IP/"
                echo "⏰ Deployment completed at: $(date)"
                echo "════════════════════════════════════════════════════════"
            '''
        }
        
        failure {
            echo '❌ Pipeline failed! Check the logs for details.'
            sh '''
                echo "════════════════════════════════════════════════════════"
                echo "❌ DEPLOYMENT FAILED!"
                echo "📦 Failed Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                echo "⏰ Failure occurred at: $(date)"
                echo "🔍 Check the logs above for detailed error information"
                echo "════════════════════════════════════════════════════════"
            '''
        }
    }
}