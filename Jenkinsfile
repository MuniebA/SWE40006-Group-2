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
                    docker-compose down -v || true
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
                        docker-compose down -v || true
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
                    
                    # Wait for EC2 to be fully ready (longer wait since app is deploying)
                    echo "⏳ Waiting for EC2 instance and application to be fully ready..."
                    sleep 180  # 3 minutes for complete initialization
                    
                    # Test SSH connection
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
        
        stage('Wait for Application Deployment') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    echo "🔍 Waiting for application deployment to complete..."
                    echo "📍 Monitoring EC2 instance: $EC2_IP"
                    
                    # Give some initial time for the instance to boot
                    echo "⏳ Initial wait for instance boot (60 seconds)..."
                    sleep 60
                    
                    # Wait for user_data script to complete (with longer timeout for debug version)
                    echo "⏳ Waiting for user_data initialization..."
                    for i in {1..35}; do
                        if ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=15 ec2-user@$EC2_IP "test -f /var/log/user-data-complete"; then
                            echo "✅ Infrastructure initialization completed!"
                            break
                        else
                            echo "⏳ Waiting for initialization... attempt $i/35 (waiting 30 seconds)"
                            
                            # Every 5 attempts, show current progress
                            if [ $((i % 5)) -eq 0 ]; then
                                echo "📊 Progress check - showing current logs..."
                                ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                                    echo '=== Current Progress ==='
                                    echo 'Last 10 lines of user-data log:'
                                    tail -10 /var/log/user-data.log 2>/dev/null || echo 'No user-data.log yet'
                                    echo 'Completion marker status:'
                                    ls -la /var/log/user-data-complete 2>/dev/null || echo 'Completion marker not found yet'
                                " || echo "Cannot connect to instance yet"
                            fi
                            
                            sleep 30
                        fi
                        
                        if [ $i -eq 35 ]; then
                            echo "⚠️ Initialization timeout - performing detailed diagnosis"
                            
                            # Comprehensive debugging
                            ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                                echo '========================================================================'
                                echo '=== DETAILED DIAGNOSIS ==='
                                echo '========================================================================'
                                
                                echo 'SECTION 1: Basic System Info'
                                echo 'Current time:' \$(date)
                                echo 'Uptime:' \$(uptime)
                                echo 'Disk space:' \$(df -h / | tail -1)
                                echo 'Memory:' \$(free -h)
                                echo ''
                                
                                echo 'SECTION 2: User Data Logs'
                                if [ -f /var/log/user-data.log ]; then
                                    echo 'User-data log exists. Last 50 lines:'
                                    tail -50 /var/log/user-data.log
                                else
                                    echo 'No user-data.log found!'
                                fi
                                echo ''
                                
                                echo 'SECTION 3: Cloud-Init Status'
                                if [ -f /var/log/cloud-init-output.log ]; then
                                    echo 'Cloud-init log exists. Last 30 lines:'
                                    tail -30 /var/log/cloud-init-output.log
                                else
                                    echo 'No cloud-init-output.log found!'
                                fi
                                echo ''
                                
                                echo 'SECTION 4: Service Status'
                                echo 'Docker service status:'
                                systemctl status docker --no-pager || echo 'Docker status check failed'
                                echo ''
                                
                                echo 'SECTION 5: Command Availability'
                                echo 'Available commands:'
                                which docker && echo '✅ Docker: available' || echo '❌ Docker: not found'
                                which docker-compose && echo '✅ Docker-compose: available' || echo '❌ Docker-compose: not found'
                                which git && echo '✅ Git: available' || echo '❌ Git: not found'
                                which curl && echo '✅ Curl: available' || echo '❌ Curl: not found'
                                echo ''
                                
                                echo 'SECTION 6: File System Check'
                                echo 'Files in /home/ec2-user:'
                                ls -la /home/ec2-user/ || echo 'Cannot list /home/ec2-user'
                                echo 'Files in /home/ec2-user/app (if exists):'
                                ls -la /home/ec2-user/app/ 2>/dev/null || echo 'No app directory'
                                echo ''
                                
                                echo 'SECTION 7: Network and Processes'
                                echo 'Listening ports:'
                                netstat -tlnp | grep LISTEN | head -10 || echo 'Cannot check listening ports'
                                echo 'Docker processes:'
                                docker ps -a 2>/dev/null || echo 'Cannot run docker ps'
                                echo ''
                                
                                echo 'SECTION 8: Recent System Messages'
                                echo 'Recent kernel/system messages:'
                                tail -20 /var/log/messages 2>/dev/null || echo 'Cannot access system messages'
                                echo ''
                                
                                echo 'SECTION 9: User Data Script Search'
                                echo 'Looking for user-data execution:'
                                ps aux | grep cloud || echo 'No cloud processes'
                                echo ''
                                
                                echo '========================================================================'
                                echo '=== END DIAGNOSIS ==='
                                echo '========================================================================'
                            " || echo "❌ Cannot SSH to instance for diagnosis"
                            
                            echo "❌ Deployment initialization failed - check detailed logs above"
                            echo "💡 The script continues without 'set -e', so we can see partial progress"
                            echo "💡 Check which sections completed successfully vs failed"
                        fi
                    done
                    
                    # Additional verification regardless of completion marker
                    echo "🌐 Verifying current application state..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "
                        echo '=== Current Application State ==='
                        echo 'Docker status:'
                        docker --version 2>/dev/null && echo '✅ Docker available' || echo '❌ Docker not available'
                        docker ps -a 2>/dev/null || echo 'Cannot list containers'
                        echo ''
                        echo 'Application connectivity:'
                        curl -I http://localhost/ 2>/dev/null && echo '✅ App responding locally' || echo '❌ App not responding locally'
                        echo ''
                        echo 'Files and directories:'
                        ls -la /home/ec2-user/app/ 2>/dev/null || echo 'No app directory'
                        echo 'Docker compose files:'
                        ls -la /home/ec2-user/app/*compose* 2>/dev/null || echo 'No compose files'
                    " || echo "Cannot verify application state"
                '''
            }
        }
        
        stage('Update Running Application') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    
                    echo "🔄 Updating running application with new image..."
                    echo "📦 New Docker image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
                    # Create update script
                    cat > update_app.sh << 'EOF'
#!/bin/bash
set -e

NEW_IMAGE="$1"
echo "🔄 Updating application to: $NEW_IMAGE"

# Navigate to app directory
cd /home/ec2-user/app

# Pull new image
echo "⬇️ Pulling new image..."
docker pull $NEW_IMAGE

# Update the docker-compose file to use new image
sed -i "s|image: munieb/student-registration:.*|image: $NEW_IMAGE|g" docker-compose.prod.yml

# Recreate the web container with new image
echo "🔄 Updating web container..."
docker-compose -f docker-compose.prod.yml up -d --force-recreate web

# Wait for container to be ready
echo "⏳ Waiting for container to be ready..."
sleep 30

# Health check
echo "🏥 Performing health check..."
for i in {1..10}; do
    if curl -f http://localhost/ >/dev/null 2>&1; then
        echo "✅ Application update successful!"
        # Clean up old images
        docker image prune -f
        exit 0
    fi
    echo "⏳ Health check attempt $i/10..."
    sleep 10
done

echo "⚠️ Health check failed after update"
exit 1
EOF

                    # Copy and execute update script
                    echo "📤 Copying update script to EC2..."
                    scp -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no update_app.sh ec2-user@$EC2_IP:/tmp/
                    
                    echo "🚀 Executing application update..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP \
                        "chmod +x /tmp/update_app.sh && /tmp/update_app.sh $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
                    echo "🎉 Application update completed successfully!"
                '''
            }
        }

        stage('Final Verification') {
            steps {
                sh '''#!/bin/bash
                    # Use local Terraform installation
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Get EC2 instance IP and monitoring IP
                    EC2_IP=$(terraform output -raw ec2_public_ip)
                    MONITOR_IP=$(terraform output -raw prometheus_url | sed 's|http://||' | sed 's|:9090||' || echo "Unknown")
                    
                    # Perform comprehensive health check
                    echo "🔍 Performing final verification..."
                    
                    # Check if application is responding
                    for i in {1..5}; do
                        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP/ 2>/dev/null || echo "000")
                        if [ "$RESPONSE" = "200" ]; then
                            echo "✅ Application is responding correctly (attempt $i)"
                            
                            # Check monitoring endpoints
                            echo "🔍 Checking monitoring endpoints..."
                            curl -s -o /dev/null -w "📊 Grafana (%{http_code}): http://$MONITOR_IP:3000\n" http://$MONITOR_IP:3000/ || true
                            curl -s -o /dev/null -w "📈 Prometheus (%{http_code}): http://$MONITOR_IP:9090\n" http://$MONITOR_IP:9090/ || true
                            
                            break
                        else
                            echo "⚠️ Health check failed (attempt $i/5) - Status: $RESPONSE"
                            if [ $i -eq 5 ]; then
                                echo "❌ Final health check failed!"
                                exit 1
                            fi
                            sleep 15
                        fi
                    done
                    
                    echo "🎯 Final verification complete!"
                    echo "📊 Application Status: HEALTHY"
                    echo "🌐 Application URL: http://$EC2_IP/"
                    echo "📊 Grafana URL: http://$MONITOR_IP:3000 (admin/admin)"
                    echo "📈 Prometheus URL: http://$MONITOR_IP:9090"
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
                
                # Get instance IPs for final message
                EC2_IP=$(terraform output -raw ec2_public_ip || echo "Unknown")
                MONITOR_IP=$(terraform output -raw prometheus_url | sed 's|http://||' | sed 's|:9090||' || echo "Unknown")
                
                echo "════════════════════════════════════════════════════════"
                echo "🎉 DEPLOYMENT SUCCESSFUL!"
                echo "📦 Docker Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                echo "🌐 Application URL: http://$EC2_IP/"
                echo "📊 Grafana URL: http://$MONITOR_IP:3000 (admin/admin)"
                echo "📈 Prometheus URL: http://$MONITOR_IP:9090"
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