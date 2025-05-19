pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_DEBUG = 'true'
        DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration'
        TEST_DATABASE_URL = 'mysql+pymysql://jenkins:password@localhost/student_registration_test'
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
                    
                    # Activate using . instead of source (compatible with all shells)
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
                    
                    # Create test database
                    mysql -u jenkins -pjenkins_password -e "DROP DATABASE IF EXISTS student_registration_test;"
                    mysql -u jenkins -pjenkins_password -e "CREATE DATABASE student_registration_test;"
                    
                    # Initialize schema
                    mysql -u jenkins -pjenkins_password student_registration_test < init.sql
                '''
            }
        }

        stage('Run Basic Tests') {
            steps {
                echo 'Running basic Python unit tests...'
                sh '''#!/bin/bash
                    # Activate using . instead of source
                    . $VENV_DIR/bin/activate
                    
                    # Run pytest for non-database, non-docker tests
                    python -m pytest tests/ -v -k "not docker and not database"
                '''
            }
        }
        
        stage('Run Database Tests') {
            steps {
                echo 'Running database tests...'
                sh '''#!/bin/bash
                    # Activate using . instead of source
                    . $VENV_DIR/bin/activate
                    
                    # Run pytest for database tests
                    python -m pytest tests/ -v -k "database"
                '''
            }
        }

        stage('Build Success') {
            steps {
                echo '✅ Student Registration System built and tested successfully!'
            }
        }
    }
    
    post {
        always {
            echo 'Cleaning up workspace...'
            sh '''
                # Clean up test database
                mysql -u jenkins -pjenkins_password -e "DROP DATABASE IF EXISTS student_registration_test;" || true
            '''
            // cleanWs()
        }
        
        success {
            echo 'Build completed successfully!'
        }
        
        failure {
            echo 'Build failed! Check the logs for details.'
        }
    }
}