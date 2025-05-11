# Student Registration System

A web-based student registration system built with Flask, Bootstrap, and MySQL. This application allows administrators to manage classes and student registrations, while students can register for classes subject to admin approval.

## Features

- **User Authentication**: Secure login and registration system with role-based access control
- **Student Management**: Admins can view, edit, and manage student information
- **Class Management**: Create, edit, and delete classes with associated schedules
- **Registration System**: Students can register for classes, with admin approval workflow
- **Fee Management**: Automatic fee calculation based on class attendance days
- **Responsive Design**: Mobile-friendly interface built with Bootstrap 5

## Technology Stack

- **Backend**: Flask (Python)
- **Frontend**: Bootstrap 5, HTML, CSS, JavaScript
- **Database**: MySQL
- **Authentication**: Flask-Login
- **Form Handling**: Flask-WTF
- **Containerization**: Docker & Docker Compose
- **CI/CD**: Jenkins Pipeline

## Installation & Setup

### Prerequisites

- Python 3.9 or higher
- MySQL 8.0 or higher
- pip (Python package manager)
- Docker & Docker Compose (optional, for containerized deployment)

### Local Development Setup

1. Clone the repository:

   ```
   git clone https://github.com/yourusername/student-registration-system.git
   cd student-registration-system
   ```
2. Create and activate a virtual environment:

   ```
   python -m venv venv
   source venv/bin/activate  # On Windows, use: venv\Scripts\activate
   ```
3. Install the required dependencies:

   ```
   pip install -r requirements.txt
   ```
4. Set up environment variables:

   ```
   export FLASK_APP=run.py
   export FLASK_ENV=development
   export SECRET_KEY=your_secret_key
   export DATABASE_URL=mysql+pymysql://username:password@localhost/student_registration
   ```

   On Windows, use `set` instead of `export`.
5. Initialize the database:

   ```
   flask init-db
   ```
6. Create an admin user:

   ```
   flask create-admin admin admin@example.com password
   ```
7. Run the application:

   ```
   flask run
   ```
8. Access the application at http://localhost:5000

### Docker Deployment

1. Clone the repository:

   ```
   git clone https://github.com/yourusername/student-registration-system.git
   cd student-registration-system
   ```
2. Create a `.env` file with required environment variables:

   ```
   FLASK_ENV=production
   SECRET_KEY=your_secret_key
   DB_PASSWORD=your_db_password
   MYSQL_ROOT_PASSWORD=your_mysql_root_password
   ```
3. Start the containers using Docker Compose:

   ```
   docker-compose up -d
   ```
4. Access the application at http://localhost:5000

## Project Structure

```
student_registration_system/
├── app/                  # Application package
│   ├── __init__.py       # Flask application initialization
│   ├── models.py         # Database models
│   ├── forms.py          # Form definitions
│   ├── routes/           # Route handlers
│   ├── static/           # Static assets (CSS, JS)
│   └── templates/        # HTML templates
├── migrations/           # Database migrations
├── tests/                # Test files
├── venv/                 # Virtual environment (not in version control)
├── .gitignore            # Git ignore file
├── Dockerfile            # Docker configuration
├── docker-compose.yml    # Docker Compose configuration
├── init.sql              # Database initialization script
├── Jenkinsfile           # CI/CD pipeline configuration
├── requirements.txt      # Python dependencies
├── run.py                # Application entry point
└── README.md             # Project documentation
```

## Default Credentials

After initialization, you can log in with the following credentials:

- **Admin User**:
  - Username: admin
  - Password: admin123

**Important**: Change these credentials immediately after first login.

## License
