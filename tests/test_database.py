# tests/test_database.py
import pytest


@pytest.mark.database
def test_database_connection():
    """Test that we can connect to the database."""
    from app import create_app, db

    app = create_app('testing')
    with app.app_context():
        # Try to connect to the database
        conn = db.engine.connect()
        assert conn is not None
        conn.close()


@pytest.mark.database
def test_create_user():
    """Test that we can create a user in the database."""
    from app import create_app, db
    from app.models import User

    app = create_app('testing')
    with app.app_context():
        # Create a test user
        user = User(
            username='testuser',
            email='test@example.com',
            role='student'
        )
        user.password = 'password123'

        # Save to database
        db.session.add(user)
        db.session.commit()

        # Check that user exists
        found_user = User.query.filter_by(username='testuser').first()
        assert found_user is not None
        assert found_user.email == 'test@example.com'

        # Clean up
        db.session.delete(found_user)
        db.session.commit()
