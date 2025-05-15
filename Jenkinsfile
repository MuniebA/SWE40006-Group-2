pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_ENV = 'testing'
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

        stage('Run Tests') {
            steps {
                echo 'Running tests...'
                // Uncomment and add actual tests folder later
                // sh './venv/bin/python -m pytest tests/'
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
