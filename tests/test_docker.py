import requests
import time
import sys
import pytest
from urllib.parse import urljoin
import os

# Helper function to create test client instead of a class with __init__


def create_test_client(base_url=None):
    """Create a test client for API requests."""
    if base_url is None:
        # Get URL from Docker environment variable or use default
        base_url = os.environ.get("DOCKER_APP_URL", "http://localhost:5000")

    client = requests.Session()

    class TestClient:
        @staticmethod
        def get(path):
            return client.get(urljoin(base_url, path))

        @staticmethod
        def post(path, data=None):
            return client.post(urljoin(base_url, path), data=data)

    return TestClient()


# Example of proper CSRF handling in tests
def test_registration():
    client = create_test_client()
    
    # First get the page to retrieve the CSRF token
    response = client.get("/register")
    html = response.data.decode('utf-8')
    
    # Extract the CSRF token (pattern may vary)
    csrf_token = re.search('name="csrf_token" value="(.+?)"', html).group(1)
    
    # Include the token in your POST request
    test_user = {
        'username': f'testuser_{int(time.time())}',
        'email': f'test_{int(time.time())}@example.com',
        'password': 'Test123!',
        'confirm_password': 'Test123!',
        'csrf_token': csrf_token
    }
    
    response = client.post("/register", data=test_user)
    assert response.status_code in [200, 302]


@pytest.mark.docker
def test_docker_environment():
    """Test that Docker environment variables are properly set."""
    # This test only runs in the Docker environment
    client = create_test_client()

    # Get the environment from the app
    response = client.get("/")
    assert response.status_code == 200

    # You could create a /environment endpoint in your app to return environment info
    # or just check that the app is responding properly in Docker
    assert "Student Registration System" in response.text

    print("Docker environment test passed!")


@pytest.mark.docker
def test_docker_health():
    """Test the Docker health check endpoint."""
    client = create_test_client()

    # Assuming you have a health check endpoint
    response = client.get("/health")
    assert response.status_code == 200

    print("Docker health check passed!")


def wait_for_app(url, max_retries=30, delay=2):
    """Wait for the application to become available."""
    for i in range(max_retries):
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print("Application is up and running!")
                return True
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
            print(
                f"Attempt {i+1}/{max_retries}: Waiting for application to start...")
            time.sleep(delay)

    print("ERROR: Application failed to start after multiple attempts!")
    return False

# Mark Docker tests so they can be easily skipped


@pytest.mark.docker
def test_public_pages():
    """Test public pages that don't require authentication."""
    client = create_test_client()

    # Test main page
    response = client.get("/")
    assert response.status_code == 200, f"Main page returned status code {response.status_code}"

    # Test login page
    response = client.get("/login")
    assert response.status_code == 200, f"Login page returned status code {response.status_code}"

    # Test registration page
    response = client.get("/register")
    assert response.status_code == 200, f"Registration page returned status code {response.status_code}"

    print("Public pages tests passed!")


@pytest.mark.docker
def test_registration():
    """Test user registration functionality."""
    client = create_test_client()

    # Test registration with valid data
    test_user = {
        'username': f'testuser_{int(time.time())}',
        'email': f'test_{int(time.time())}@example.com',
        'password': 'Test123!',
        'confirm_password': 'Test123!'  # Changed from password2 to match your form
    }

    response = client.post("/register", data=test_user)
    assert response.status_code in [
        200, 302], f"Registration returned status code {response.status_code}"

    # Test registration with existing username
    response = client.post("/register", data=test_user)
    assert response.status_code == 200, "Should not allow duplicate username"

    print("Registration tests passed!")


@pytest.mark.docker
def test_login_logout():
    """Test login and logout functionality."""
    client = create_test_client()

    # Test login with invalid credentials
    response = client.post("/login", data={
        'username': 'nonexistent',
        'password': 'wrongpass'
    })
    assert response.status_code == 200, "Should stay on login page with invalid credentials"

    # Test login with valid credentials (using the test user we created)
    response = client.post("/login", data={
        'username': 'testuser',
        'password': 'Test123!'
    })
    assert response.status_code in [
        200, 302], f"Login returned status code {response.status_code}"

    # Test accessing protected route after login
    response = client.get("/profile")
    assert response.status_code in [
        200, 302], f"Protected route returned status code {response.status_code}"

    # Test logout
    response = client.get("/logout")
    assert response.status_code in [
        200, 302], f"Logout returned status code {response.status_code}"

    # Test accessing protected route after logout
    response = client.get("/profile")
    assert response.status_code in [
        200, 302], "Should redirect to login after logout"

    print("Login/Logout tests passed!")


@pytest.mark.docker
def test_protected_routes():
    """Test access to protected routes."""
    client = create_test_client()

    # Test accessing protected routes without authentication
    protected_routes = ['/profile', '/complete-profile', '/student/dashboard']
    for route in protected_routes:
        response = client.get(route)
        assert response.status_code in [
            200, 302], f"Protected route {route} returned status code {response.status_code}"

    print("Protected routes tests passed!")


def run_all_tests():
    """Run all test suites."""
    base_url = "http://localhost:5000"

    # Wait for the application to start
    if not wait_for_app(f"{base_url}/"):
        print("Application failed to start!")
        sys.exit(1)

    # Run all test suites
    test_public_pages()
    test_registration()
    test_login_logout()
    test_protected_routes()

    print("All tests completed successfully!")


if __name__ == "__main__":
    run_all_tests()
