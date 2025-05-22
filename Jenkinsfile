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
        EC2_SSH_KEY = credentials('ec2-ssh-private-key') // You'll need to add this credential
        // These should be set to your actual EC2 instance details
        EC2_PUBLIC_IP = credentials('ec2-public-ip') // Store as secret text
        EC2_USER = 'ec2-user'
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

        stage('Run Tests') {
            steps {
                sh '''#!/bin/bash
                    # Activate virtual environment
                    . $VENV_DIR/bin/activate
                    
                    echo "Running all tests..."
                    # Run all tests except Docker tests (since we're not spinning up docker-compose here)
                    python -m pytest tests/ -v -k "not docker" --junitxml=test-results.xml
                    
                    # Check if tests passed
                    if [ $? -ne 0 ]; then
                        echo "❌ Tests failed! Stopping pipeline."
                        exit 1
                    fi
                    echo "✅ All tests passed!"
                '''
            }
            post {
                always {
                    // Archive test results
                    junit 'test-results.xml'
                }
            }
        }

        stage('Build Docker Image') {
            when {
                // Only build if tests passed
                expression { currentBuild.currentResult == 'SUCCESS' }
            }
            steps {
                sh '''
                    echo "Building Docker image with tag: $DOCKER_IMAGE_TAG"
                    
                    # Build the Docker image
                    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .
                    
                    # Also tag as latest
                    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG $DOCKER_IMAGE_NAME:latest
                    
                    # List images to verify
                    docker images | grep $DOCKER_IMAGE_NAME
                '''
            }
        }

        stage('Push Docker Image') {
            when {
                expression { currentBuild.currentResult == 'SUCCESS' }
            }
            steps {
                sh '''
                    echo "Pushing Docker image to Docker Hub..."
                    
                    # Login to Docker Hub
                    echo $DOCKER_HUB_CREDENTIALS_PSW | docker login -u $DOCKER_HUB_CREDENTIALS_USR --password-stdin
                    
                    # Push both versioned and latest tags
                    docker push $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG
                    docker push $DOCKER_IMAGE_NAME:latest
                    
                    echo "✅ Docker image pushed successfully!"
                    
                    # Logout
                    docker logout
                '''
            }
        }

        stage('Deploy to EC2') {
            when {
                expression { currentBuild.currentResult == 'SUCCESS' }
            }
            steps {
                sh '''#!/bin/bash
                    echo "Deploying new Docker image to EC2 instance..."
                    
                    # Create deployment script
                    cat > deploy.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
set -e

IMAGE_NAME="$1"
IMAGE_TAG="$2"
ROLLBACK_TAG="$3"

echo "Starting deployment of $IMAGE_NAME:$IMAGE_TAG..."

# Create backup of current version for rollback
echo "Creating backup of current deployment..."
if docker ps -q -f name=student-registration-web; then
    CURRENT_IMAGE=$(docker inspect student-registration-web --format='{{.Config.Image}}' 2>/dev/null || echo "none")
    echo "Current image: $CURRENT_IMAGE"
    
    # Stop current container gracefully
    echo "Stopping current container..."
    docker stop student-registration-web || true
    docker rm student-registration-web || true
else
    echo "No existing container found"
fi

# Pull new image
echo "Pulling new Docker image..."
docker pull $IMAGE_NAME:$IMAGE_TAG

# Start new container
echo "Starting new container..."
docker run -d \\
    --name student-registration-web \\
    --restart unless-stopped \\
    -p 80:5000 \\
    -e FLASK_ENV=production \\
    -e FLASK_CONFIG=production \\
    $IMAGE_NAME:$IMAGE_TAG

# Wait for container to start
echo "Waiting for container to start..."
sleep 10

# Health check
echo "Performing health check..."
for i in {1..12}; do
    if curl -f http://localhost/ >/dev/null 2>&1; then
        echo "✅ Health check passed! Deployment successful."
        
        # Clean up old images (keep last 3 versions)
        echo "Cleaning up old Docker images..."
        docker images $IMAGE_NAME --format "table {{.Tag}}" | grep -E "^[0-9]+$" | sort -nr | tail -n +4 | xargs -I {} docker rmi $IMAGE_NAME:{} 2>/dev/null || true
        
        exit 0
    fi
    echo "Health check attempt $i failed, retrying in 10 seconds..."
    sleep 10
done

# If we reach here, health check failed
echo "❌ Health check failed! Rolling back..."

# Stop failed container
docker stop student-registration-web || true
docker rm student-registration-web || true

# Rollback to previous version if available
if [ "$ROLLBACK_TAG" != "none" ] && [ "$ROLLBACK_TAG" != "" ]; then
    echo "Rolling back to previous version: $ROLLBACK_TAG"
    docker run -d \\
        --name student-registration-web \\
        --restart unless-stopped \\
        -p 80:5000 \\
        -e FLASK_ENV=production \\
        -e FLASK_CONFIG=production \\
        $IMAGE_NAME:$ROLLBACK_TAG
    
    echo "Rollback completed"
else
    echo "No rollback version available"
fi

exit 1
DEPLOY_SCRIPT

                    # Make deployment script executable
                    chmod +x deploy.sh
                    
                    # Get previous successful build number for rollback
                    PREVIOUS_TAG=$(expr $BUILD_NUMBER - 1 2>/dev/null || echo "none")
                    
                    # Copy deployment script to EC2 and execute
                    scp -i $EC2_SSH_KEY -o StrictHostKeyChecking=no deploy.sh $EC2_USER@$EC2_PUBLIC_IP:/tmp/
                    
                    # Execute deployment on EC2
                    ssh -i $EC2_SSH_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_PUBLIC_IP "
                        chmod +x /tmp/deploy.sh
                        /tmp/deploy.sh $DOCKER_IMAGE_NAME $DOCKER_IMAGE_TAG $PREVIOUS_TAG
                        rm /tmp/deploy.sh
                    "
                    
                    echo "✅ Deployment completed successfully!"
                '''
            }
        }

        stage('Post-Deployment Health Check') {
            when {
                expression { currentBuild.currentResult == 'SUCCESS' }
            }
            steps {
                sh '''#!/bin/bash
                    echo "Running post-deployment health checks..."
                    
                    # Wait a bit for the application to fully start
                    sleep 15
                    
                    # Test the application endpoints
                    echo "Testing application health..."
                    
                    # Basic connectivity test
                    if curl -f -s http://$EC2_PUBLIC_IP/ >/dev/null; then
                        echo "✅ Application is responding"
                    else
                        echo "❌ Application health check failed"
                        exit 1
                    fi
                    
                    # Test a specific endpoint if you have one
                    # if curl -f -s http://$EC2_PUBLIC_IP/health >/dev/null; then
                    #     echo "✅ Health endpoint is responding"
                    # else
                    #     echo "❌ Health endpoint failed"
                    #     exit 1
                    # fi
                    
                    echo "✅ All post-deployment checks passed!"
                '''
            }
        }
    }

    post {
        always {
            echo 'Cleaning up local resources...'
            sh '''
                # Clean up test database
                mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;" || true
                
                # Clean up local Docker images (keep last 2 builds)
                docker images $DOCKER_IMAGE_NAME --format "table {{.Tag}}" | grep -E "^[0-9]+$" | sort -nr | tail -n +3 | xargs -I {} docker rmi $DOCKER_IMAGE_NAME:{} 2>/dev/null || true
                
                # General cleanup
                docker system prune -f || true
            '''
        }
        
        success {
            script {
                // Store successful build information
                writeFile file: 'last_successful_build.txt', text: "${BUILD_NUMBER}"
            }
            echo "✅ Deployment pipeline completed successfully!"
            echo "🌐 Application URL: http://${EC2_PUBLIC_IP}/"
        }
        
        failure {
            echo '❌ Pipeline failed!'
            
            // Attempt emergency rollback
            script {
                try {
                    sh '''#!/bin/bash
                        echo "Attempting emergency rollback..."
                        
                        # Get last successful build if available
                        LAST_SUCCESSFUL=$(cat last_successful_build.txt 2>/dev/null || echo "none")
                        
                        if [ "$LAST_SUCCESSFUL" != "none" ] && [ "$LAST_SUCCESSFUL" != "$BUILD_NUMBER" ]; then
                            echo "Rolling back to build $LAST_SUCCESSFUL"
                            
                            ssh -i $EC2_SSH_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_PUBLIC_IP "
                                docker stop student-registration-web || true
                                docker rm student-registration-web || true
                                docker run -d \\
                                    --name student-registration-web \\
                                    --restart unless-stopped \\
                                    -p 80:5000 \\
                                    -e FLASK_ENV=production \\
                                    -e FLASK_CONFIG=production \\
                                    $DOCKER_IMAGE_NAME:$LAST_SUCCESSFUL
                            "
                            
                            echo "Emergency rollback completed"
                        else
                            echo "No previous successful build available for rollback"
                        fi
                    '''
                } catch (Exception e) {
                    echo "Emergency rollback failed: ${e.getMessage()}"
                }
            }
        }
    }
}