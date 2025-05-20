from flask import Flask, render_template, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_wtf.csrf import CSRFProtect
from datetime import datetime
from prometheus_flask_exporter import PrometheusMetrics
import logging

# Logging setup
logging.basicConfig(level=logging.DEBUG)

# Initialize extensions
db = SQLAlchemy()
login_manager = LoginManager()
csrf = CSRFProtect()
migrate = Migrate()

def create_app(config_name='default'):
    app = Flask(__name__)

    # Load configuration
    from .config import config
    app.config.from_object(config[config_name])

    # Initialize extensions with app
    db.init_app(app)
    login_manager.init_app(app)
    csrf.init_app(app)
    migrate.init_app(app, db)

    # Initialize Prometheus metrics
    metrics = PrometheusMetrics(app)
    metrics.info('app_info', 'Application Info', version='1.0.0')

    # Set login view for unauthorized redirects
    login_manager.login_view = 'auth.login'
    login_manager.login_message_category = 'info'

    # Import models
    from .models import User, Student, Class, Registration

    # Register blueprints
    from .routes.auth import auth as auth_blueprint
    from .routes.admin import admin as admin_blueprint
    from .routes.student import student as student_blueprint
    from .routes.classes import classes as classes_blueprint
    from .routes.health import health as health_blueprint

    app.register_blueprint(auth_blueprint)
    app.register_blueprint(admin_blueprint, url_prefix='/admin')
    app.register_blueprint(student_blueprint, url_prefix='/student')
    app.register_blueprint(classes_blueprint, url_prefix='/classes')
    app.register_blueprint(health_blueprint, url_prefix='/health')

    # Default route
    @app.route('/')
    def index():
        return render_template('index.html', now=datetime.now())

    return app
