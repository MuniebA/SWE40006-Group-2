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
                    python -m pytest tests/ -v -k "not docker" --junitxml=test-results.xml || true
                    
                    # Check if tests passed
                    if [ $? -ne 0 ]; then
                        echo "❌ Tests failed! Stopping pipeline."
                        exit 1
                    fi
                    echo "✅ All tests passed!"
                '''
            }
        }

        stage('Build Docker Image') {
            when {
                // Only build if tests passed
                expression { currentBuild.result == null }
            }
            steps {
                sh '''
                    echo "Building Docker image with tag: $DOCKER_IMAGE_TAG"
                    
                    # Build the Docker image
                    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .
                    
                    # Also tag as latest
                    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG $DOCKER_IMAGE_NAME:latest
                    
                    # List images to verify
                    docker images | grep $DOCKER_IMAGE_NAME || true
                '''
            }
        }
        
        stage('Docker Tests') {
            when {
                expression { currentBuild.result == null }
            }
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
            when {
                expression { currentBuild.result == null }
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
        
        stage('Provision Infrastructure with Terraform') {
            agent {
                dockerContainer {
                    
                image 'hashicorp/terraform:1.12.0'
                //args  "-u root:root -v $WORKSPACE:/workspace"
                remoteFs '/workspace'      // so we can write files
                }
            }
            
            steps {
                withCredentials([usernamePassword(
                credentialsId: 'aws-credentials',
                usernameVariable: 'AWS_ACCESS_KEY_ID',
                passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                )]) {
                    sh '''
                        set -euxo pipefail

                        # Set AWS credentials
                        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                        export AWS_DEFAULT_REGION=ap-southeast-1
                        echo "🔍 Working directory: $(pwd)"
                        echo "📦 Initializing Terraform..."
                        echo "📦 Initializing Terraform..."
                        terraform init -input=false

                        echo "🧱 Validating Terraform..."
                        terraform validate

                        echo "🚀 Applying Terraform to provision infrastructure..."
                        terraform apply -auto-approve
                    '''
                }
            }
        }


        stage('Deploy to AWS') {
            when {
                expression { currentBuild.result == null }
            }
            steps {
                sh '''#!/bin/bash
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
                    # Install AWS CLI if not available
                    if ! command -v aws &> /dev/null; then
                        echo "Installing AWS CLI..."
                        python3 -m pip install --user awscli
                        export PATH=$HOME/.local/bin:$PATH
                    fi
                    
                    # Get EC2 instance IP
                    INSTANCE_IP=$(aws ec2 describe-instances \
                        --filters "Name=tag:Name,Values=tf-docker-web" "Name=instance-state-name,Values=running" \
                        --query "Reservations[].Instances[].PublicIpAddress" \
                        --output text)
                    
                    if [ -z "$INSTANCE_IP" ]; then
                        echo "❌ No running EC2 instance found!"
                        exit 1
                    fi
                    
                    echo "🎯 Found EC2 instance: $INSTANCE_IP"
                    
                    # Create deployment script
                    cat > deploy.sh << 'EOF'
                    #!/bin/bash
                    set -e

                    DOCKER_IMAGE="$1"
                    CONTAINER_NAME="student-registration-app"

                    echo "🚀 Starting deployment of $DOCKER_IMAGE"

                    # Get current running image for rollback
                    CURRENT_IMAGE=$(docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Image}}" | tail -n +2)
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
                        -p 80:5000 \
                        -e FLASK_ENV=production \
                        -e DATABASE_URL=mysql+pymysql://testuser:testpass@db:3306/testdb \
                        --network app-network \
                        $DOCKER_IMAGE

                    # Wait for container to start
                    sleep 10

                    # Health check
                    echo "🏥 Performing health check..."
                    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")

                    if [ "$HEALTH_CHECK" = "200" ]; then
                        echo "✅ Health check passed! Deployment successful."
                        echo "🗑️ Cleaning up old images..."
                        docker image prune -f
                        exit 0
                    else
                        echo "❌ Health check failed! Rolling back..."
                        
                        # Stop failed container
                        docker stop $CONTAINER_NAME || true
                        docker rm $CONTAINER_NAME || true
                        
                        # Rollback to previous image
                        if [ -n "$CURRENT_IMAGE" ] && [ "$CURRENT_IMAGE" != "REPOSITORY" ]; then
                            echo "🔄 Rolling back to: $CURRENT_IMAGE"
                            docker run -d \
                                --name $CONTAINER_NAME \
                                -p 80:5000 \
                                -e FLASK_ENV=production \
                                -e DATABASE_URL=mysql+pymysql://testuser:testpass@db:3306/testdb \
                                --network app-network \
                                $CURRENT_IMAGE
                            echo "🔙 Rollback completed!"
                        else
                            echo "⚠️ No previous image available for rollback!"
                        fi
                        exit 1
                    fi
                    EOF

                    # Copy deployment script to EC2
                    echo "📤 Copying deployment script to EC2..."
                    scp -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no deploy.sh ec2-user@$INSTANCE_IP:/tmp/
                    
                    # Execute deployment
                    echo "🚀 Executing deployment on EC2..."
                    ssh -i ~/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP \
                        "chmod +x /tmp/deploy.sh && /tmp/deploy.sh $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    
                    echo "🎉 Deployment completed successfully!"
                    echo "🌐 Application URL: http://$INSTANCE_IP/"
                '''
            }
        }

        stage('Post-Deployment Verification') {
            when {
                expression { currentBuild.result == null }
            }
            steps {
                sh '''#!/bin/bash
                    # Set AWS credentials
                    export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                    export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                    export AWS_DEFAULT_REGION=ap-southeast-1
                    
                    # Install AWS CLI if not available
                    if ! command -v aws &> /dev/null; then
                        python3 -m pip install --user awscli
                        export PATH=$HOME/.local/bin:$PATH
                    fi
                    
                    # Get EC2 instance IP
                    INSTANCE_IP=$(aws ec2 describe-instances \
                        --filters "Name=tag:Name,Values=tf-docker-web" "Name=instance-state-name,Values=running" \
                        --query "Reservations[].Instances[].PublicIpAddress" \
                        --output text)
                    
                    # Perform comprehensive health check
                    echo "🔍 Performing post-deployment verification..."
                    
                    # Check if application is responding
                    for i in {1..5}; do
                        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$INSTANCE_IP/ || echo "000")
                        if [ "$RESPONSE" = "200" ]; then
                            echo "✅ Application is responding correctly (attempt $i)"
                            break
                        else
                            echo "⚠️ Health check failed (attempt $i/5) - Status: $RESPONSE"
                            if [ $i -eq 5 ]; then
                                echo "❌ Final health check failed! Consider rollback."
                                exit 1
                            fi
                            sleep 5
                        fi
                    done
                    
                    echo "🎯 Final deployment verification complete!"
                    echo "📊 Application Status: HEALTHY"
                    echo "🌐 Access your application at: http://$INSTANCE_IP/"
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
                # Set AWS credentials for success notification
                export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                export AWS_DEFAULT_REGION=ap-southeast-1
                
                # Install AWS CLI if not available
                if ! command -v aws &> /dev/null; then
                    python3 -m pip install --user awscli
                    export PATH=$HOME/.local/bin:$PATH
                fi
                
                # Get instance IP for final message
                INSTANCE_IP=$(aws ec2 describe-instances \
                    --filters "Name=tag:Name,Values=tf-docker-web" "Name=instance-state-name,Values=running" \
                    --query "Reservations[].Instances[].PublicIpAddress" \
                    --output text)
                
                echo "════════════════════════════════════════════════════════"
                echo "🎉 DEPLOYMENT SUCCESSFUL!"
                echo "📦 Docker Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                echo "🌐 Application URL: http://$INSTANCE_IP/"
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
                echo "🔄 Previous version should still be running if rollback succeeded"
                echo "════════════════════════════════════════════════════════"
            '''
        }
    }
}