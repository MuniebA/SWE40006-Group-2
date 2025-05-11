# Student Registration System

A web-based student registration system built with Flask, Bootstrap, and MySQL. This application modernizes the original terminal-based student registration system into a user-friendly web application while preserving the core functionality.

## Features

- **User Authentication System**
  - Secure login and registration
  - Role-based access control (admin/student)
  - Profile management

- **Admin Features**
  - Dashboard with system statistics
  - Student management (view, edit, delete)
  - Class management (create, edit, delete)
  - Registration approval workflow
  - Fee management

- **Student Features**
  - Personal dashboard
  - Class registration
  - Registration status tracking
  - Fee calculation

## Technology Stack

- **Backend**: Flask (Python web framework)
- **Frontend**: Bootstrap 5, HTML, CSS, JavaScript
- **Database**: MySQL
- **Authentication**: Flask-Login
- **Form Handling**: Flask-WTF
- **ORM**: SQLAlchemy

## Installation & Setup

### Prerequisites

- Python 3.9 or higher
- MySQL 5.7 or higher
- pip (Python package manager)

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/student-registration-system.git
cd student-registration-system
```

### Step 2: Create a Virtual Environment

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment
# On Windows:
venv\Scripts\activate

# On macOS/Linux:
source venv/bin/activate
```

### Step 3: Install Dependencies

```bash
pip install -r requirements.txt
```

### Step 4: Database Setup

1. Create MySQL database and user:

```sql
CREATE DATABASE student_registration;
CREATE USER 'student_app'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON student_registration.* TO 'student_app'@'localhost';
FLUSH PRIVILEGES;
```

2. Initialize database with schema:
   
You can use phpMyAdmin to run the following SQL script or run it directly in MySQL:

```sql
-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(10) NOT NULL DEFAULT 'student',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Students Table
CREATE TABLE IF NOT EXISTS students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    age INT NOT NULL,
    contact VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Classes Table
CREATE TABLE IF NOT EXISTS classes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_no INT NOT NULL,
    day_of_week VARCHAR(10) NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    teacher VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_class_day (class_no, day_of_week)
);

-- Registrations Table
CREATE TABLE IF NOT EXISTS registrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    class_id INT NOT NULL,
    month INT NOT NULL,
    fee DECIMAL(10, 2) NOT NULL,
    status VARCHAR(10) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
    FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    UNIQUE KEY unique_registration (student_id, class_id, month)
);

-- Settings Table
CREATE TABLE IF NOT EXISTS settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    year INT NOT NULL,
    fee_per_session DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create default admin account (password: admin123)
INSERT INTO users (username, email, password_hash, role)
VALUES ('admin', 'admin@example.com', 'pbkdf2:sha256:260000$xrKAZvQxJcg14X7H$4994b05e1f2f94c71791005c5ca9e8492e07af994a01d916fe1a42fa11915fea', 'admin');

-- Initialize settings
INSERT INTO settings (year, fee_per_session)
VALUES (YEAR(CURDATE()), 50.00);

-- Create sample classes
INSERT INTO classes (class_no, day_of_week, start_time, end_time, teacher)
VALUES 
(101, 'monday', '09:00:00', '10:30:00', 'John Smith'),
(102, 'monday', '11:00:00', '12:30:00', 'Sarah Johnson'),
(201, 'wednesday', '14:00:00', '15:30:00', 'Michael Brown'),
(301, 'friday', '16:00:00', '17:30:00', 'Jennifer Davis');
```

### Step 5: Environment Configuration

1. Create a `.env` file or set environment variables:

```
FLASK_APP=run.py
FLASK_DEBUG=1
SECRET_KEY=dev-secret-key
DATABASE_URL=mysql+pymysql://student_app:password@localhost/student_registration
```

2. For PowerShell, set variables using:

```powershell
$env:FLASK_APP = "run.py"
$env:FLASK_DEBUG = "1"
$env:SECRET_KEY = "dev-secret-key"
$env:DATABASE_URL = "mysql+pymysql://student_app:password@localhost/student_registration"
```

### Step 6: Run the Application

```bash
flask run
```

The application will be available at http://127.0.0.1:5000.

## Default Login Credentials

- **Admin User:**
  - Username: admin
  - Password: admin123

## Project Structure

```
student_registration_system/
├── app/
│   ├── __init__.py           # Flask application initialization
│   ├── models.py             # Database models
│   ├── config.py             # Configuration settings
│   ├── forms.py              # Form definitions
│   │
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── auth.py           # Authentication routes
│   │   ├── admin.py          # Admin panel routes
│   │   ├── student.py        # Student routes
│   │   └── classes.py        # Class management routes
│   │
│   ├── static/
│   │   ├── css/
│   │   │   └── style.css     # Custom stylesheets
│   │   ├── js/
│   │   │   └── script.js     # Custom scripts
│   │   └── img/              # Image assets
│   │
│   └── templates/
│       ├── base.html         # Base template
│       ├── index.html        # Home page
│       ├── auth/             # Authentication templates
│       ├── admin/            # Admin templates
│       └── student/          # Student templates
│
├── .env                      # Environment variables (not in version control)
├── .gitignore                # Git ignore file
├── requirements.txt          # Python dependencies
├── run.py                    # Application entry point
└── README.md                 # Project documentation
```

## Development Notes

### Adding a New Template

1. Create the HTML file in the appropriate template directory
2. Extend the base template: `{% extends "base.html" %}`
3. Define the title block: `{% block title %}Page Title{% endblock %}`
4. Define the content block: `{% block content %}...{% endblock %}`

### Working with Forms

All forms are defined in `app/forms.py` and use Flask-WTF for validation and CSRF protection.

### Database Migrations

If you need to make changes to the database schema:

1. Initialize migrations (first time only):
   ```
   flask db init
   ```

2. Create a migration:
   ```
   flask db migrate -m "Description of changes"
   ```

3. Apply the migration:
   ```
   flask db upgrade
   ```

## Troubleshooting

- **Database Connection Error**: Ensure MySQL server is running and the database exists
- **Template Not Found Error**: Check that the template file exists in the correct directory
- **Form Validation Error**: Verify that custom validation methods accept the `extra_validators` parameter

## License

