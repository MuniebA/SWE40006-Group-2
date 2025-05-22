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
        
        // Rollback variables
        PREVIOUS_IMAGE_TAG = ""
        DEPLOYMENT_SUCCESS = "false"
        MONITORING_DEPLOYMENT_SUCCESS = "false"
    }

    stages {
        stage('Clone Repo') {
            steps {
                echo 'Repository cloned automatically'
                script {
                    // Get the previous successful build number for rollback
                    def lastSuccessfulBuild = currentBuild.getPreviousSuccessfulBuild()
                    if (lastSuccessfulBuild) {
                        env.PREVIOUS_IMAGE_TAG = lastSuccessfulBuild.number
                        echo "Previous successful image tag: ${env.PREVIOUS_IMAGE_TAG}"
                    } else {
                        env.PREVIOUS_IMAGE_TAG = "latest"
                        echo "No previous successful build found, using 'latest' tag"
                    }
                }
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''#!/bin/bash
                    python3 -m venv $VENV_DIR
                    . $VENV_DIR/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    pip install pytest pytest-cov flask-migrate
                '''
            }
        }

        stage('Check Database Changes') {
            steps {
                script {
                    // Check if init.sql or migrations have changed
                    def initSqlChanged = sh(
                        script: "git diff --name-only HEAD~1 HEAD | grep -q 'init.sql' || echo 'not_changed'",
                        returnStdout: true
                    ).trim()
                    
                    def migrationsChanged = sh(
                        script: "git diff --name-only HEAD~1 HEAD | grep -q 'migrations/' || echo 'not_changed'",
                        returnStdout: true
                    ).trim()
                    
                    def monitoringChanged = sh(
                        script: "git diff --name-only HEAD~1 HEAD | grep -q 'monitoring/' || echo 'not_changed'",
                        returnStdout: true
                    ).trim()
                    
                    env.INIT_SQL_CHANGED = (initSqlChanged != 'not_changed') ? 'true' : 'false'
                    env.MIGRATIONS_CHANGED = (migrationsChanged != 'not_changed') ? 'true' : 'false'
                    env.MONITORING_CHANGED = (monitoringChanged != 'not_changed') ? 'true' : 'false'
                    
                    echo "Init.sql changed: ${env.INIT_SQL_CHANGED}"
                    echo "Migrations changed: ${env.MIGRATIONS_CHANGED}"
                    echo "Monitoring config changed: ${env.MONITORING_CHANGED}"
                }
            }
        }

        stage('Setup Test Database') {
            steps {
                sh '''#!/bin/bash
                    . $VENV_DIR/bin/activate
                    
                    # Test MySQL connectivity
                    if ! mysql -u jenkins -ppassword -e "SELECT 1"; then
                        echo "ERROR: Cannot connect to MySQL server!"
                        exit 1
                    fi
                    
                    # Create test database
                    mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;"
                    mysql -u jenkins -ppassword -e "CREATE DATABASE student_registration_test;"
                    
                    # Initialize schema
                    mysql -u jenkins -ppassword student_registration_test < init.sql
                    
                    # Run migrations if they exist
                    export DATABASE_URL="mysql+pymysql://jenkins:password@localhost/student_registration_test"
                    if [ -d "migrations/versions" ] && [ "$(ls -A migrations/versions)" ]; then
                        echo "Running database migrations on test database..."
                        flask db upgrade || echo "Migration failed, continuing with init.sql only"
                    else
                        echo "No migrations found, using init.sql schema only"
                    fi
                '''
            }
        }

        stage('Run All Tests') {
            steps {
                sh '''#!/bin/bash
                    . $VENV_DIR/bin/activate
                    
                    echo "Running basic tests..."
                    python -m pytest tests/test_basic.py -v
                    
                    echo "Running database tests..."
                    export DATABASE_URL="mysql+pymysql://jenkins:password@localhost/student_registration_test"
                    python -m pytest tests/test_database.py -v
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "Building Docker image with tag: $DOCKER_IMAGE_TAG"
                    docker build -t $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG .
                    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG $DOCKER_IMAGE_NAME:latest-candidate
                    
                    docker images | grep $DOCKER_IMAGE_NAME
                '''
            }
        }
        
        stage('Docker Integration Tests') {
            steps {
                sh '''
                    # Modify docker-compose for testing if needed
                    if netstat -tuln | grep -q ":3306"; then
                        sed -i 's/"3306:3306"/"3307:3306"/g' docker-compose.yml
                    fi
                    
                    # Stop existing containers
                    docker-compose down -v
                    
                    # Use the newly built image for testing
                    export DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG}
                    docker-compose up -d
                    
                    echo "Waiting for containers to start..."
                    sleep 30
                    
                    # Run Docker tests
                    . venv/bin/activate && python -m pytest tests/test_docker.py -v
                '''
            }
            post {
                always {
                    sh 'docker-compose down -v || true'
                }
            }
        }

        stage('Database Migration Test') {
            when {
                expression { env.MIGRATIONS_CHANGED == 'true' }
            }
            steps {
                echo "Testing database migrations..."
                sh '''#!/bin/bash
                    . $VENV_DIR/bin/activate
                    
                    # Create a separate migration test database
                    mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS migration_test;"
                    mysql -u jenkins -ppassword -e "CREATE DATABASE migration_test;"
                    mysql -u jenkins -ppassword migration_test < init.sql
                    
                    # Test migrations
                    export DATABASE_URL="mysql+pymysql://jenkins:password@localhost/migration_test"
                    flask db upgrade
                    
                    # Verify migration success
                    echo "Migration test completed successfully"
                    
                    # Cleanup
                    mysql -u jenkins -ppassword -e "DROP DATABASE migration_test;"
                '''
            }
        }

        stage('Push Docker Image') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                sh '''
                    echo $DOCKER_HUB_CREDENTIALS_PSW | docker login -u $DOCKER_HUB_CREDENTIALS_USR --password-stdin
                    
                    # Push the tested image
                    docker push $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG
                    
                    # Update latest tag only after successful tests
                    docker tag $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG $DOCKER_IMAGE_NAME:latest
                    docker push $DOCKER_IMAGE_NAME:latest
                    
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
                    python3 -c "
import urllib.request
import zipfile
import os
import sys

version = os.environ.get('TERRAFORM_VERSION', '1.7.4')
url = f'https://releases.hashicorp.com/terraform/{version}/terraform_{version}_linux_amd64.zip'
zip_path = 'terraform.zip'

print(f'Downloading Terraform {version}...')
urllib.request.urlretrieve(url, zip_path)

print('Extracting Terraform binary...')
with zipfile.ZipFile(zip_path, 'r') as zip_ref:
    zip_ref.extractall('.')

os.chmod('terraform', 0o755)
print('Terraform installed successfully!')
"
                    
                    # Add to PATH for this session
                    export PATH=${WORKSPACE}/terraform:$PATH
                    
                    # Verify installation
                    ./terraform version
                '''
            }
        }
        
        stage('Deploy Infrastructure to AWS') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                script {
                    try {
                        sh '''
                            export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                            export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                            export AWS_DEFAULT_REGION=ap-southeast-1
                            
                            # Use local Terraform installation
                            export PATH=${WORKSPACE}/terraform:$PATH
                            
                            # Initialize Terraform
                            terraform init
                            
                            # Plan the changes (include docker image tag)
                            terraform plan -var="docker_image_tag=${DOCKER_IMAGE_TAG}" -out=tfplan
                            
                            # Apply the changes
                            terraform apply -auto-approve tfplan
                            
                            # Wait for instances to be ready
                            echo "Waiting for instances to be ready..."
                            sleep 90
                            
                            # Extract deployment information
                            echo "===================================================="
                            echo "                DEPLOYMENT DETAILS                 "
                            echo "===================================================="
                            
                            terraform output -json > deployment_info.json
                            
                            # Extract key information
                            WEB_IP=$(terraform output -raw ec2_public_ip)
                            MONITOR_IP=$(terraform output -raw monitoring_instance_ip)
                            GRAFANA_URL=$(terraform output -raw grafana_url)
                            PROMETHEUS_URL=$(terraform output -raw prometheus_url)
                            WEBSITE_URL=$(terraform output -raw website_url)
                            
                            echo "🌐 Website URL: $WEBSITE_URL"
                            echo "📊 Grafana Dashboard: $GRAFANA_URL"
                            echo "📈 Prometheus Metrics: $PROMETHEUS_URL"
                            echo "🔐 SSH to web: ssh -i tf-ec2.pem ec2-user@$WEB_IP"
                            echo "🔐 SSH to monitor: ssh -i tf-ec2.pem ec2-user@$MONITOR_IP"
                            echo "===================================================="
                            
                            # Save deployment info for other stages
                            echo "$WEB_IP" > web_ip.txt
                            echo "$MONITOR_IP" > monitor_ip.txt
                            echo "$GRAFANA_URL" > grafana_url.txt
                            
                            # Copy SSH key for potential debugging
                            cp tf-ec2.pem ${WORKSPACE}/deployment_key.pem || echo "SSH key copy failed"
                        '''
                        
                        // Mark deployment as successful
                        env.DEPLOYMENT_SUCCESS = "true"
                        
                    } catch (Exception e) {
                        echo "Infrastructure deployment failed: ${e.getMessage()}"
                        env.DEPLOYMENT_SUCCESS = "false"
                        throw e
                    }
                }
            }
        }

        stage('Verify Web Application Deployment') {
            when {
                expression { env.DEPLOYMENT_SUCCESS == "true" }
            }
            steps {
                sh '''
                    WEB_IP=$(cat web_ip.txt)
                    echo "Verifying web application deployment at http://$WEB_IP/"
                    
                    # Wait for application to be ready
                    for i in {1..15}; do
                        if curl -f -s "http://$WEB_IP/" > /dev/null; then
                            echo "✅ Web application is responding successfully!"
                            break
                        else
                            echo "Waiting for web application... ($i/15)"
                            sleep 20
                        fi
                        
                        if [ $i -eq 15 ]; then
                            echo "❌ Web application verification failed after 5 minutes!"
                            exit 1
                        fi
                    done
                '''
            }
        }

        stage('Verify Monitoring Deployment') {
            when {
                expression { env.DEPLOYMENT_SUCCESS == "true" }
            }
            steps {
                script {
                    try {
                        sh '''
                            MONITOR_IP=$(cat monitor_ip.txt)
                            echo "Verifying monitoring stack deployment..."
                            
                            # Check Grafana
                            echo "Testing Grafana at http://$MONITOR_IP:3000"
                            for i in {1..10}; do
                                if curl -f -s "http://$MONITOR_IP:3000/api/health" > /dev/null; then
                                    echo "✅ Grafana is responding successfully!"
                                    break
                                else
                                    echo "Waiting for Grafana... ($i/10)"
                                    sleep 20
                                fi
                                
                                if [ $i -eq 10 ]; then
                                    echo "⚠️ Grafana verification failed, but continuing..."
                                    break
                                fi
                            done
                            
                            # Check Prometheus
                            echo "Testing Prometheus at http://$MONITOR_IP:9090"
                            for i in {1..10}; do
                                if curl -f -s "http://$MONITOR_IP:9090/api/v1/status/config" > /dev/null; then
                                    echo "✅ Prometheus is responding successfully!"
                                    break
                                else
                                    echo "Waiting for Prometheus... ($i/10)"
                                    sleep 20
                                fi
                                
                                if [ $i -eq 10 ]; then
                                    echo "⚠️ Prometheus verification failed, but continuing..."
                                    break
                                fi
                            done
                            
                            # Test if Prometheus can scrape web instance metrics
                            echo "Testing Prometheus metrics collection..."
                            sleep 30
                            
                            if curl -s "http://$MONITOR_IP:9090/api/v1/query?query=up" | grep -q '"value":[.*,"1"]'; then
                                echo "✅ Prometheus is successfully collecting metrics!"
                            else
                                echo "⚠️ Prometheus metrics collection needs time to stabilize"
                            fi
                        '''
                        
                        env.MONITORING_DEPLOYMENT_SUCCESS = "true"
                        
                    } catch (Exception e) {
                        echo "Monitoring verification failed: ${e.getMessage()}"
                        env.MONITORING_DEPLOYMENT_SUCCESS = "false"
                        // Don't fail the pipeline for monitoring issues
                    }
                }
            }
        }

        stage('Final Deployment Summary') {
            when {
                expression { env.DEPLOYMENT_SUCCESS == "true" }
            }
            steps {
                sh '''
                    echo "===================================================="
                    echo "🎉           DEPLOYMENT SUCCESSFUL!              🎉"
                    echo "===================================================="
                    
                    WEB_IP=$(cat web_ip.txt)
                    MONITOR_IP=$(cat monitor_ip.txt)
                    
                    echo "📱 Student Registration System:"
                    echo "   🌐 Application: http://$WEB_IP/"
                    echo "   🗄️ Database: MySQL (containerized)"
                    echo "   🐳 Docker Image: $DOCKER_IMAGE_NAME:$DOCKER_IMAGE_TAG"
                    echo ""
                    echo "📊 Monitoring Stack:"
                    echo "   📈 Grafana Dashboard: http://$MONITOR_IP:3000"
                    echo "   📊 Prometheus Metrics: http://$MONITOR_IP:9090"
                    echo "   🔐 Grafana Login: admin / admin"
                    echo ""
                    echo "🔧 SSH Access:"
                    echo "   💻 Web Server: ssh -i tf-ec2.pem ec2-user@$WEB_IP"
                    echo "   📊 Monitor Server: ssh -i tf-ec2.pem ec2-user@$MONITOR_IP"
                    echo "   🔑 SSH Key: Available in workspace as tf-ec2.pem"
                    echo ""
                    echo "📁 Deployment Files:"
                    echo "   📄 SSH Config: ssh_config (use: ssh -F ssh_config web)"
                    echo "   🗂️ Terraform State: terraform.tfstate"
                    echo "   📋 Deployment Info: deployment_info.json"
                    echo "===================================================="
                '''
                
                // Archive important deployment files
                archiveArtifacts artifacts: 'tf-ec2.pem,ssh_config,deployment_info.json', allowEmptyArchive: true
            }
        }
    }
    
    post {
        failure {
            script {
                echo '❌ Pipeline failed! Initiating rollback...'
                
                if (env.PREVIOUS_IMAGE_TAG && env.PREVIOUS_IMAGE_TAG != "") {
                    try {
                        sh '''
                            echo "Rolling back to previous image: $DOCKER_IMAGE_NAME:$PREVIOUS_IMAGE_TAG"
                            
                            # Pull previous working image
                            echo $DOCKER_HUB_CREDENTIALS_PSW | docker login -u $DOCKER_HUB_CREDENTIALS_USR --password-stdin
                            docker pull $DOCKER_IMAGE_NAME:$PREVIOUS_IMAGE_TAG
                            
                            # Tag it as latest
                            docker tag $DOCKER_IMAGE_NAME:$PREVIOUS_IMAGE_TAG $DOCKER_IMAGE_NAME:latest
                            docker push $DOCKER_IMAGE_NAME:latest
                            
                            docker logout
                            
                            echo "✅ Docker image rollback completed"
                            
                            # If Terraform was deployed, try to redeploy with previous image
                            if [ "$DEPLOYMENT_SUCCESS" == "true" ]; then
                                echo "Attempting to redeploy infrastructure with previous image..."
                                export PATH=${WORKSPACE}/terraform:$PATH
                                export AWS_ACCESS_KEY_ID=$AWS_CREDENTIALS_USR
                                export AWS_SECRET_ACCESS_KEY=$AWS_CREDENTIALS_PSW
                                export AWS_DEFAULT_REGION=ap-southeast-1
                                
                                terraform apply -var="docker_image_tag=$PREVIOUS_IMAGE_TAG" -auto-approve || echo "Infrastructure rollback failed"
                            fi
                        '''
                    } catch (Exception rollbackError) {
                        echo "❌ Rollback failed: ${rollbackError.getMessage()}"
                    }
                } else {
                    echo "⚠️ No previous successful build found for rollback"
                }
            }
        }
        
        always {
            sh '''
                # Cleanup test resources
                mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS student_registration_test;" || true
                mysql -u jenkins -ppassword -e "DROP DATABASE IF EXISTS migration_test;" || true
                docker-compose down -v || true
                docker system prune -f || true
                
                # Don't clean up Terraform files - keep for potential debugging
                # rm -rf ${WORKSPACE}/terraform || true
            '''
        }
        
        success {
            echo '🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉'
            echo '🎉                                          🎉'
            echo '🎉     CONTINUOUS DEPLOYMENT SUCCESSFUL!     🎉'
            echo '🎉                                          🎉'
            echo '🎉  ✅ Tests Passed                          🎉'
            echo '🎉  ✅ Docker Image Built & Pushed          🎉'
            echo '🎉  ✅ Infrastructure Deployed               🎉'
            echo '🎉  ✅ Web Application Running               🎉'
            echo '🎉  ✅ Monitoring Stack Active               🎉'
            echo '🎉                                          🎉'
            echo '🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉'
        }
    }
}