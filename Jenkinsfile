pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_ENV = 'testing'
        DOCKER_IMAGE = 'student-registration-system'
    }

    stages {
        stage('Clone Repo') {
            steps {
                echo 'Repository cloned automatically'
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''
                    python3 -m venv venv
                    ./venv/bin/pip install --upgrade pip
                    ./venv/bin/pip install -r requirements.txt
                    ./venv/bin/pip install pytest pytest-cov
                '''
            }
        }

        stage('Run Unit Tests') {
            steps {
                echo 'Running only Python unit tests (non-Docker tests)...'
                sh './venv/bin/python -m pytest tests/ -k "not test_docker"'
            }
        }

        stage('Build Docker Image') {
            steps {
                echo 'Building Docker image...'
                sh 'docker build -t ${DOCKER_IMAGE}:${BUILD_NUMBER} .'
            }
        }

        stage('Run Docker Tests') {
            steps {
                echo 'Starting Docker Compose environment...'
                sh 'docker-compose up -d'
                
                echo 'Waiting for services to start...'
                sh '''
                    # Wait for the Flask app to become available (up to 2 minutes)
                    MAX_RETRIES=60
                    DELAY=2
                    COUNTER=0
                    
                    until $(curl --output /dev/null --silent --head --fail http://localhost:5000) || [ $COUNTER -eq $MAX_RETRIES ]; do
                        echo "Waiting for Flask app to start... ($COUNTER/$MAX_RETRIES)"
                        sleep $DELAY
                        COUNTER=$((COUNTER+1))
                    done
                    
                    if [ $COUNTER -eq $MAX_RETRIES ]; then
                        echo "Flask app failed to start within the allocated time!"
                        docker-compose logs
                        exit 1
                    fi
                    
                    echo "Flask app is up and running!"
                '''
                
                echo 'Running Docker tests...'
                sh '''
                    ./venv/bin/python tests/test_docker.py
                    if [ $? -ne 0 ]; then
                        echo "Docker tests failed!"
                        exit 1
                    fi
                '''
            }
            post {
                always {
                    echo 'Stopping Docker Compose environment...'
                    sh 'docker-compose down'
                }
            }
        }

        stage('Build Success') {
            steps {
                echo '✅ Student Registration System built successfully!'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up workspace...'
            sh 'docker-compose down -v'  // Remove volumes
            cleanWs()
        }

        success {
            echo 'Build completed successfully!'
        }

        failure {
            echo 'Build failed! Check the logs for details.'
        }
    }
}