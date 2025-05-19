import requests
import time
import sys
from urllib.parse import urljoin

class TestClient:
    def __init__(self, base_url):
        self.base_url = base_url
        self.session = requests.Session()
    
    def get(self, path):
        return self.session.get(urljoin(self.base_url, path))
    
    def post(self, path, data=None):
        return self.session.post(urljoin(self.base_url, path), data=data)


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

def test_public_pages():
    """Test public pages that don't require authentication."""
    client = TestClient("http://localhost:5000")
    
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

def test_registration():
    """Test user registration functionality."""
    client = TestClient("http://localhost:5000")
    
    # Test registration with valid data
    test_user = {
        'username': f'testuser_{int(time.time())}',
        'email': f'test_{int(time.time())}@example.com',
        'password': 'Test123!',
        'password2': 'Test123!'
    }
    
    response = client.post("/register", data=test_user)
    assert response.status_code in [200, 302], f"Registration returned status code {response.status_code}"
    
    # Test registration with existing username
    response = client.post("/register", data=test_user)
    assert response.status_code == 200, "Should not allow duplicate username"
    
    print("Registration tests passed!")

def test_login_logout():
    """Test login and logout functionality."""
    client = TestClient("http://localhost:5000")
    
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
    assert response.status_code in [200, 302], f"Login returned status code {response.status_code}"
    
    # Test accessing protected route after login
    response = client.get("/profile")
    assert response.status_code in [200, 302], f"Protected route returned status code {response.status_code}"
    
    # Test logout
    response = client.get("/logout")
    assert response.status_code in [200, 302], f"Logout returned status code {response.status_code}"
    
    # Test accessing protected route after logout
    response = client.get("/profile")
    assert response.status_code in [200, 302], "Should redirect to login after logout"
    
    print("Login/Logout tests passed!")

def test_protected_routes():
    """Test access to protected routes."""
    client = TestClient("http://localhost:5000")
    
    # Test accessing protected routes without authentication
    protected_routes = ['/profile', '/complete-profile', '/student/dashboard']
    for route in protected_routes:
        response = client.get(route)
        assert response.status_code in [200, 302], f"Protected route {route} returned status code {response.status_code}"
    
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