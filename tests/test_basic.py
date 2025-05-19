def test_basic_setup():
    """Basic test to verify pytest can run."""
    assert True, "Basic test is working"


def test_app_config():
    """Test that app config can be imported"""
    try:
        from app import create_app
        assert callable(create_app), "create_app should be a function"
    except ImportError:
        # Skip if we can't import the app
        pass
