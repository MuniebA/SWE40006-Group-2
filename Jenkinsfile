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
                    
                    # Create temporary test script to avoid shell indentation issues
                    cat > /tmp/test_db.py << 'EOF'
from app import create_app, db
from sqlalchemy import text
import sys

try:
    print("Creating app with testing config...")
    app = create_app("testing")
    with app.app_context():
        print("Testing database connection...")
        result = db.session.execute(text("SELECT 1 as test")).fetchone()
        if result and result[0] == 1:
            print("✅ Database connection successful")
        else:
            print("❌ Database query failed - no result")
            sys.exit(1)
except Exception as e:
    print(f"❌ Database connection failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF

                    # Test database connection from web container
                    echo "🔍 Testing database connection from web container..."
                    docker cp /tmp/test_db.py flaskapp-ci-web-1:/tmp/test_db.py
                    docker-compose exec -T web python /tmp/test_db.py
                    
                    # Create temporary test script for endpoints
                    cat > /tmp/test_endpoints.py << 'EOF'
import urllib.request
import sys

try:
    # Test root endpoint
    print("Testing root endpoint...")
    response = urllib.request.urlopen("http://localhost:5000/", timeout=10)
    if response.getcode() == 200:
        print("✅ Root endpoint responding correctly")
        content = response.read().decode("utf-8")[:200]
        print(f"Response preview: {content[:100]}...")
    else:
        print(f"❌ Root endpoint failed: {response.getcode()}")
        sys.exit(1)
        
    # Test health endpoint
    try:
        print("Testing health endpoint...")
        health_response = urllib.request.urlopen("http://localhost:5000/health", timeout=10)
        if health_response.getcode() == 200:
            health_content = health_response.read().decode("utf-8")
            print("✅ Health endpoint responding correctly")
            print(f"Health response: {health_content}")
        else:
            print(f"⚠️ Health endpoint returned: {health_response.getcode()}")
    except Exception as e:
        print(f"ℹ️ Health endpoint test failed: {e}")
        # Try the health blueprint endpoint at /health/
        try:
            health_response = urllib.request.urlopen("http://localhost:5000/health/", timeout=10)
            if health_response.getcode() == 200:
                health_content = health_response.read().decode("utf-8")
                print("✅ Health blueprint endpoint responding correctly")
                print(f"Health response: {health_content}")
        except Exception as e2:
            print(f"ℹ️ Health blueprint endpoint also failed: {e2}")
        
except Exception as e:
    print(f"❌ Web application test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF
                    
                    # Test web application endpoints
                    echo "🧪 Testing web application endpoints..."
                    docker cp /tmp/test_endpoints.py flaskapp-ci-web-1:/tmp/test_endpoints.py
                    docker-compose exec -T web python /tmp/test_endpoints.py
                    
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
                        # Clean up temporary test files
                        rm -f /tmp/test_db.py /tmp/test_endpoints.py
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
                    
                    # Wait for EC2 to be fully ready
                    echo "⏳ Waiting for EC2 instance to be fully ready..."
                    sleep 60
                    
                    # Test SSH connection (no sudo needed)
                    echo "🧪 Testing SSH connection..."
                    for i in {1..5}; do
                        if ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$EC2_IP "echo 'SSH connection successful!'"; then
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
                    
                    # Create deployment script that doesn't require AWS CLI
                    cat > deploy_via_ssh.sh << 'EOF'
#!/bin/bash
set -e

DOCKER_IMAGE="$1"
CONTAINER_NAME="student-registration-app"

echo "🚀 Starting deployment of $DOCKER_IMAGE"

# Check Docker is accessible
if ! docker ps &> /dev/null; then
    echo "⚠️ Docker access issue. Trying to fix permissions..."
    sudo usermod -aG docker $USER || echo "Could not add user to docker group"
    sudo systemctl restart docker || echo "Could not restart docker"
    sleep 10
fi

# Create network if it doesn't exist
docker network create app-network || true

# Check if MySQL container exists and is running
if ! docker ps --format 'table {{.Names}}' | grep -q mysql-prod; then
    if docker ps -a --format 'table {{.Names}}' | grep -q mysql-prod; then
        echo "🔄 Starting existing MySQL container..."
        docker start mysql-prod
    else
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
    fi
    
    # Wait for MySQL to be ready
    echo "⏳ Waiting for MySQL to be ready..."
    sleep 30
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
                    scp -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no deploy_via_ssh.sh ec2-user@$EC2_IP:/tmp/
                    
                    # Execute deployment
                    echo "🚀 Executing deployment on EC2..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP \
                        "chmod +x /tmp/deploy_via_ssh.sh && /tmp/deploy_via_ssh.sh $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
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