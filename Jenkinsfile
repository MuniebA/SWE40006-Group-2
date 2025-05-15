pipeline {
    agent any

    environment {
        VENV_DIR = 'venv'
    }

    stages {
        stage('Clone Repo') {
            steps {
                git branch: 'main', url: 'https://github.com/your-username/your-flask-repo.git'
            }
        }

        stage('Setup Python') {
            steps {
                sh 'python3 -m venv $VENV_DIR'
                sh './$VENV_DIR/bin/pip install --upgrade pip'
                sh './$VENV_DIR/bin/pip install -r requirements.txt'
            }
        }

        stage('Run Tests') {
            steps {
                sh './$VENV_DIR/bin/python -m unittest discover tests'
            }
        }

        stage('Notify') {
            steps {
                echo '✅ Flask app built and tested successfully!'
            }
        }
    }
}
