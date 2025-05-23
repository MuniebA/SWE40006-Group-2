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
                sh '''#!/bin/bash
                    echo "🧹 Cleaning up any existing containers..."
                    docker-compose down -v
                    docker container prune -f
                    
                    echo "🚀 Starting Docker Compose services (internal networking only)..."
                    docker-compose up -d
                    
                    echo "⏳ Waiting for services to be ready..."
                    
                    # Wait for MySQL to be healthy
                    echo "📊 Checking MySQL health..."
                    for i in {1..20}; do
                        if docker-compose exec -T db mysqladmin ping -h localhost -u testuser -ptestpass --silent; then
                            echo "✅ MySQL is healthy (attempt $i)"
                            break
                        else
                            echo "⏳ MySQL not ready yet (attempt $i/20), waiting 10 seconds..."
                            sleep 10
                        fi
                        
                        if [ $i -eq 20 ]; then
                            echo "❌ MySQL failed to become healthy"
                            docker-compose logs db
                            exit 1
                        fi
                    done
                    
                    # Wait for web application using Python one-liner
                    echo "🌐 Checking web application health..."
                    for i in {1..15}; do
                        # Simple Python health check - single line to avoid indentation issues
                        if docker-compose exec -T web python -c "import urllib.request; response = urllib.request.urlopen('http://localhost:5000/', timeout=5); exit(0 if response.getcode() == 200 else 1)" 2>/dev/null; then
                            echo "✅ Web application is healthy (attempt $i)"
                            break
                        else
                            echo "⏳ Web application not ready yet (attempt $i/15), waiting 10 seconds..."
                            sleep 10
                        fi
                        
                        if [ $i -eq 15 ]; then
                            echo "❌ Web application failed to become healthy"
                            echo "📋 Container status:"
                            docker-compose ps
                            echo "📋 Web container logs:"
                            docker-compose logs web
                            exit 1
                        fi
                    done
                    
                    # Show running containers
                    echo "📋 Container status:"
                    docker-compose ps
                    
                    # Run pytest Docker tests
                    echo "🔬 Running Docker-specific tests..."
                    if [ -f "venv/bin/activate" ]; then
                        . venv/bin/activate && python -m pytest tests/ -v -k docker --tb=short
                    else
                        echo "⚠️ Virtual environment not found, running tests directly"
                        python -m pytest tests/ -v -k docker --tb=short
                    fi
                    
                    echo "✅ All Docker tests passed successfully!"
                '''
            }
            post {
                always {
                    sh '''
                        echo "🧹 Cleaning up Docker containers..."
                        docker-compose down -v
                        docker container prune -f
                    '''
                }
                failure {
                    sh '''
                        echo "❌ Docker tests failed! Capturing logs for debugging..."
                        echo "=== Docker Compose Logs ==="
                        docker-compose logs || true
                        echo "=== Container Status ==="
                        docker-compose ps || true
                        echo "=== Web Container Environment ==="
                        docker-compose exec -T web env | grep -E "(DATABASE|FLASK)" || true
                    '''
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
                    
                    # Create SSH directory for jenkins user (no sudo needed)
                    mkdir -p ~/.ssh
                    chmod 700 ~/.ssh
                    
                    # Extract the private key from Terraform output
                    terraform output -raw private_key_content > ec2-private-key.pem
                    chmod 600 ec2-private-key.pem
                    
                    # Copy key to Jenkins SSH directory (no sudo needed)
                    cp ec2-private-key.pem ~/.ssh/ec2-key.pem
                    chmod 600 ~/.ssh/ec2-key.pem
                    
                    # Get EC2 IP for verification
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    echo "✅ SSH key setup complete!"
                    echo "🌐 EC2 Instance IP: $EC2_IP"
                    echo "🔐 SSH Key location: ~/.ssh/ec2-key.pem"
                    
                    # Wait for EC2 to be fully ready (increased wait time for proper initialization)
                    echo "⏳ Waiting for EC2 instance to be fully ready..."
                    sleep 120
                    
                    # Test SSH connection (no sudo needed)
                    echo "🧪 Testing SSH connection..."
                    for i in {1..10}; do
                        if ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=15 ec2-user@$EC2_IP "echo 'SSH connection successful!'"; then
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
        
        stage('Wait for Infrastructure Initialization') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    echo "🔍 Waiting for infrastructure initialization to complete..."
                    echo "📍 Monitoring EC2 instance: $EC2_IP"
                    
                    # Wait for user_data script to complete
                    echo "⏳ Waiting for user_data initialization..."
                    for i in {1..20}; do
                        if ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=15 ec2-user@$EC2_IP "test -f /var/log/user-data-complete"; then
                            echo "✅ Infrastructure initialization completed!"
                            break
                        else
                            echo "⏳ Waiting for initialization... attempt $i/20 (waiting 30 seconds)"
                            sleep 30
                        fi
                        
                        if [ $i -eq 20 ]; then
                            echo "⚠️ Initialization timeout - proceeding anyway"
                            # Show initialization status
                            ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                                echo '=== Infrastructure Status ==='
                                sudo systemctl is-active docker || echo 'Docker service not active'
                                docker ps -a || echo 'Cannot run docker ps'
                                ls -la /var/log/user-data* || echo 'No user-data logs'
                                tail -20 /var/log/user-data.log || echo 'Cannot read user-data log'
                            "
                        fi
                    done
                    
                    # Verify Docker is running
                    echo "🐳 Verifying Docker installation..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                        echo 'Checking Docker status...'
                        sudo systemctl status docker --no-pager -l || echo 'Docker status check failed'
                        docker --version || echo 'Docker version check failed'
                        docker info || echo 'Docker info failed'
                    "
                '''
            }
        }
        
        stage('Deploy Application to EC2') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    if [ -z "$EC2_IP" ]; then
                        echo "❌ No EC2 instance IP found!"
                        exit 1
                    fi
                    
                    echo "🎯 Deploying to EC2 instance: $EC2_IP"
                    echo "📦 New Docker image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
                    # Create simplified deployment script (no Docker installation)
                    cat > simple_deploy.sh << 'EOF'
#!/bin/bash
set -e

DOCKER_IMAGE="$1"
CONTAINER_NAME="student-registration-app"

echo "🚀 Starting deployment of $DOCKER_IMAGE"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed! This should have been handled by Terraform."
    exit 1
fi

# Check if Docker service is running
if ! sudo systemctl is-active --quiet docker; then
    echo "🔄 Starting Docker service..."
    sudo systemctl start docker
    sleep 10
fi

# Verify Docker is working
if ! sudo docker info >/dev/null 2>&1; then
    echo "❌ Docker is not working properly!"
    sudo systemctl status docker --no-pager
    exit 1
fi

echo "✅ Docker is available and running"

# Determine if we need sudo for Docker commands
if docker ps >/dev/null 2>&1; then
    USE_SUDO=""
    echo "ℹ️ Using Docker without sudo"
else
    USE_SUDO="sudo"
    echo "ℹ️ Using Docker with sudo"
fi

# Create network if it doesn't exist
echo "🌐 Ensuring Docker network exists..."
$USE_SUDO docker network create app-network 2>/dev/null || echo "Network already exists"

# Check if MySQL container exists and is running
echo "🗄️ Checking MySQL container..."
if ! $USE_SUDO docker ps --format 'table {{.Names}}' | grep -q mysql-prod; then
    if $USE_SUDO docker ps -a --format 'table {{.Names}}' | grep -q mysql-prod; then
        echo "🔄 Starting existing MySQL container..."
        $USE_SUDO docker start mysql-prod
    else
        echo "🗄️ Creating MySQL production container..."
        $USE_SUDO docker run -d \
            --name mysql-prod \
            --network app-network \
            --restart always \
            -e MYSQL_ROOT_PASSWORD=rootpassword \
            -e MYSQL_DATABASE=testdb \
            -e MYSQL_USER=testuser \
            -e MYSQL_PASSWORD=testpass \
            -v mysql-data:/var/lib/mysql \
            mysql:8.0
    fi
    
    # Wait for MySQL to be ready
    echo "⏳ Waiting for MySQL to be ready..."
    sleep 45
    
    # Test MySQL connection
    for i in {1..10}; do
        if $USE_SUDO docker exec mysql-prod mysqladmin ping -u testuser -ptestpass --silent 2>/dev/null; then
            echo "✅ MySQL is ready!"
            break
        fi
        echo "⏳ MySQL not ready yet, waiting... ($i/10)"
        sleep 10
    done
fi

# Get current running image for rollback
CURRENT_IMAGE=$($USE_SUDO docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Image}}" | tail -n +2 | head -1)
echo "📋 Current image: $CURRENT_IMAGE"

# Pull new image
echo "⬇️ Pulling new image..."
$USE_SUDO docker pull $DOCKER_IMAGE

# Stop and remove old container
echo "🛑 Stopping old container..."
$USE_SUDO docker stop $CONTAINER_NAME 2>/dev/null || true
$USE_SUDO docker rm $CONTAINER_NAME 2>/dev/null || true

# Start new container
echo "🔄 Starting new container..."
$USE_SUDO docker run -d \
    --name $CONTAINER_NAME \
    --network app-network \
    --restart always \
    -p 80:5000 \
    -e FLASK_ENV=production \
    -e DATABASE_URL=mysql+pymysql://testuser:testpass@mysql-prod:3306/testdb \
    $DOCKER_IMAGE

# Wait for container to start
echo "⏳ Waiting for application to start..."
sleep 30

# Health check
echo "🏥 Performing health check..."
for i in {1..15}; do
    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$HEALTH_CHECK" = "200" ]; then
        echo "✅ Health check passed! Deployment successful."
        echo "🌐 Application is running at http://localhost/"
        echo "🗑️ Cleaning up old images..."
        $USE_SUDO docker image prune -f
        exit 0
    else
        echo "⚠️ Health check attempt $i/15 failed - Status: $HEALTH_CHECK"
        sleep 10
    fi
done

echo "❌ Health check failed! Rolling back..."

# Stop failed container
$USE_SUDO docker stop $CONTAINER_NAME 2>/dev/null || true
$USE_SUDO docker rm $CONTAINER_NAME 2>/dev/null || true

# Rollback to previous image
if [ -n "$CURRENT_IMAGE" ] && [ "$CURRENT_IMAGE" != "REPOSITORY" ] && [ "$CURRENT_IMAGE" != "$DOCKER_IMAGE" ]; then
    echo "🔄 Rolling back to: $CURRENT_IMAGE"
    $USE_SUDO docker run -d \
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
                    scp -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no simple_deploy.sh ec2-user@$EC2_IP:/tmp/
                    
                    # Execute deployment
                    echo "🚀 Executing deployment on EC2..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP \
                        "chmod +x /tmp/simple_deploy.sh && /tmp/simple_deploy.sh $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
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
                    for i in {1..10}; do
                        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP/ 2>/dev/null || echo "000")
                        if [ "$RESPONSE" = "200" ]; then
                            echo "✅ Application is responding correctly (attempt $i)"
                            
                            # Additional verification
                            echo "🔍 Additional verification checks..."
                            
                            # Check container status
                            ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                                echo '=== Container Status ==='
                                sudo docker ps -f name=student-registration-app
                                echo '=== Application Logs (last 10 lines) ==='
                                sudo docker logs --tail 10 student-registration-app
                            "
                            
                            break
                        else
                            echo "⚠️ Health check failed (attempt $i/10) - Status: $RESPONSE"
                            if [ $i -eq 10 ]; then
                                echo "❌ Final health check failed!"
                                
                                # Debug information
                                ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                                    echo '=== Debugging Information ==='
                                    echo 'Container Status:'
                                    sudo docker ps -a
                                    echo 'Application Logs:'
                                    sudo docker logs student-registration-app || echo 'No container logs available'
                                    echo 'System Services:'
                                    sudo systemctl status docker --no-pager
                                    echo 'Port 80 Status:'
                                    sudo netstat -tulpn | grep :80 || echo 'Nothing listening on port 80'
                                "
                                exit 1
                            fi
                            sleep 15
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
        }
        
        success {
            echo '🎉 Build, test, and deployment completed successfully!'
            sh '''
                # Use local Terraform installation
                export PATH=${WORKSPACE}/terraform:$PATH
                
                # Get instance IP for final message
                EC2_IP=$(terraform output -raw ec2_public_ip || echo "Unknown")
                GRAFANA_IP=$(terraform output -raw prometheus_url | sed 's|http://||' | sed 's|:9090||' || echo "Unknown")
                
                echo "════════════════════════════════════════════════════════"
                echo "🎉 DEPLOYMENT SUCCESSFUL!"
                echo "📦 Docker Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                echo "🌐 Application URL: http://$EC2_IP/"
                echo "📊 Grafana URL: http://$GRAFANA_IP:3000 (admin/admin)"
                echo "📈 Prometheus URL: http://$GRAFANA_IP:9090"
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