import os
import click
from flask.cli import with_appcontext
from app import create_app, db
from app.models import User, Student, Class, Registration, Setting

# Print the value to debug
print(f"Using DATABASE_URL: {os.environ.get('DATABASE_URL')}")

app = create_app(os.getenv('FLASK_CONFIG') or 'default')


@app.shell_context_processor
def make_shell_context():
    return dict(db=db, User=User, Student=Student, Class=Class,
                Registration=Registration, Setting=Setting)


@app.cli.command("create-admin")
@click.argument("username")
@click.argument("email")
@click.argument("password")
@with_appcontext
def create_admin(username, email, password):
    """Create an admin user."""
    if User.query.filter_by(username=username).first() is not None:
        click.echo(f"Error: User '{username}' already exists.")
        return

    if User.query.filter_by(email=email).first() is not None:
        click.echo(f"Error: Email '{email}' is already registered.")
        return

    user = User(username=username, email=email, role='admin')
    user.password = password
    db.session.add(user)
    db.session.commit()

    click.echo(f"Admin '{username}' created successfully.")


@app.cli.command("init-db")
@with_appcontext
def init_db():
    """Initialize the database with default values."""
    db.create_all()

    # Create default settings
    if Setting.query.first() is None:
        from datetime import datetime
        setting = Setting(year=datetime.utcnow().year, fee_per_session=50.00)
        db.session.add(setting)
        db.session.commit()
        click.echo("Default settings initialized.")

    click.echo("Database initialized.")


if __name__ == '__main__':
    app.run(debug=True)
