pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_ENV = 'testing'
        // Use withCredentials instead of directly referencing credentials
        // DB_PASSWORD = credentials('db-password')
    }

    stages {
        stage('Clone Repo') {
            steps {
                // This already happens automatically when using 'Pipeline script from SCM'
                echo 'Repository cloned automatically'
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh 'python3 -m venv $VENV_DIR || python -m venv $VENV_DIR'
                sh '''
                    source $VENV_DIR/bin/activate || $VENV_DIR/Scripts/activate 
                    pip install --upgrade pip
                    pip install -r requirements.txt
                    pip install pytest pytest-cov
                '''
            }
        }

        stage('Run Tests') {
            steps {
                echo 'Running tests...'
                // We'll enable this after adding tests
                // sh '''
                //     source $VENV_DIR/bin/activate || $VENV_DIR/Scripts/activate 
                //     python -m pytest tests/
                // '''
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
            // Wrap all post actions in a node block
            node {
                echo 'Cleaning up workspace...'
                cleanWs()
            }
        }
        
        success {
            node {
                echo 'Build completed successfully!'
            }
        }
        
        failure {
            node {
                echo 'Build failed! Check the logs for details.'
            }
        }
    }
}