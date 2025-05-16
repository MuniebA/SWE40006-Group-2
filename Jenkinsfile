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
                echo 'Running unit tests...'
                sh './venv/bin/python -m pytest tests/'
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
                sh 'sleep 30'  // Give services time to initialize
                
                echo 'Running Docker tests...'
                sh '''
                    ./venv/tests/test_docker.py
                    if [ $? -eq 0 ]; then
                        echo "Docker tests passed!"
                    else
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
