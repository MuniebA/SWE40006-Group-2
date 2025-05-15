pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
        FLASK_APP = 'run.py'
        FLASK_ENV = 'testing'
        // Database credentials for testing - these will be used only within Jenkins
        DB_USER = 'student_app'
        DB_PASSWORD = credentials('db-password')
        DB_NAME = 'student_registration_test'
    }

    stages {
        stage('Clone Repo') {
            steps {
                // Update this URL to your actual GitHub repository
                git branch: 'main', url: 'https://github.com/yourusername/SWE40006-Group-2.git'
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh 'python3 -m venv $VENV_DIR'
                sh './$VENV_DIR/bin/pip install --upgrade pip'
                sh './$VENV_DIR/bin/pip install -r requirements.txt'
                
                // Install test dependencies if needed
                sh './$VENV_DIR/bin/pip install pytest pytest-cov'
            }
        }
        
        stage('Setup Test Database') {
            steps {
                // Create a testing database if it doesn't exist
                sh '''
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
                mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
                mysql -u root -e "FLUSH PRIVILEGES;"
                '''
                
                // Initialize the test database with schema
                sh '''
                mysql -u root $DB_NAME < init.sql
                '''
            }
        }

        stage('Run Linting') {
            steps {
                // Run flake8 if you want to check code style
                sh './$VENV_DIR/bin/pip install flake8'
                sh './$VENV_DIR/bin/flake8 app --count --select=E9,F63,F7,F82 --show-source --statistics'
            }
        }

        stage('Run Unit Tests') {
            steps {
                // Set environment variables for testing
                sh '''
                export FLASK_APP=$FLASK_APP
                export FLASK_ENV=$FLASK_ENV
                export DATABASE_URL="mysql+pymysql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME"
                
                # Run unit tests with pytest
                ./$VENV_DIR/bin/pytest --cov=app tests/
                '''
            }
        }
        
        stage('Generate Test Report') {
            steps {
                // Generate coverage report
                sh './$VENV_DIR/bin/coverage xml'
                
                // Publish test results
                junit 'test-reports/**/*.xml'
                
                // Publish coverage report
                cobertura coberturaReportFile: 'coverage.xml'
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
            // Clean up the database after tests
            sh 'mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME;"'
            
            // Clean up workspace
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