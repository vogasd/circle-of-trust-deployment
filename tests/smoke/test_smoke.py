import pytest
import requests
import os
import time

BASE_URL = os.getenv('BASE_URL', 'http://localhost:8000')
TIMEOUT = 30


@pytest.fixture(scope="module")
def api_client():
    """Create API client for testing."""
    return requests.Session()


def test_health_endpoint(api_client):
    """Test that health endpoint is accessible."""
    response = api_client.get(f"{BASE_URL}/health", timeout=TIMEOUT)
    assert response.status_code == 200
    data = response.json()
    assert data.get('status') == 'healthy'


def test_ready_endpoint(api_client):
    """Test that ready endpoint confirms service readiness."""
    response = api_client.get(f"{BASE_URL}/ready", timeout=TIMEOUT)
    assert response.status_code == 200
    data = response.json()
    assert data.get('status') == 'ready'
    assert data.get('database') == 'connected'


def test_api_version(api_client):
    """Test API version endpoint."""
    response = api_client.get(f"{BASE_URL}/api/v1/version", timeout=TIMEOUT)
    assert response.status_code == 200
    data = response.json()
    assert 'version' in data
    assert 'build' in data


def test_metrics_endpoint(api_client):
    """Test that metrics endpoint is accessible."""
    response = api_client.get(f"{BASE_URL}/metrics", timeout=TIMEOUT)
    assert response.status_code == 200
    assert 'http_requests_total' in response.text


def test_basic_llm_interaction(api_client):
    """Test basic LLM interaction."""
    payload = {
        "prompt": "Hello, this is a test.",
        "model": "llama2",
        "max_tokens": 50
    }

    response = api_client.post(
        f"{BASE_URL}/api/v1/chat",
        json=payload,
        timeout=60
    )

    assert response.status_code == 200
    data = response.json()
    assert 'response' in data
    assert len(data['response']) > 0


def test_database_connectivity(api_client):
    """Test database connectivity through API."""
    response = api_client.get(f"{BASE_URL}/api/v1/db/status", timeout=TIMEOUT)
    assert response.status_code == 200
    data = response.json()
    assert data.get('connected') == True


def test_response_time(api_client):
    """Test that response times are within acceptable limits."""
    start_time = time.time()
    response = api_client.get(f"{BASE_URL}/health", timeout=TIMEOUT)
    end_time = time.time()

    assert response.status_code == 200
    response_time = (end_time - start_time) * 1000  # Convert to ms
    assert response_time < 200, f"Response time {response_time}ms exceeds 200ms threshold"


def test_concurrent_requests(api_client):
    """Test system handles concurrent requests."""
    import concurrent.futures

    def make_request():
        response = api_client.get(f"{BASE_URL}/health", timeout=TIMEOUT)
        return response.status_code == 200

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = [executor.submit(make_request) for _ in range(10)]
        results = [f.result()
                   for f in concurrent.futures.as_completed(futures)]

    assert all(results), "Some concurrent requests failed"


@pytest.mark.skipif(os.getenv('ENVIRONMENT') != 'production', reason="Production only test")
def test_ssl_enabled():
    """Test that SSL is enabled in production."""
    import ssl
    import socket

    hostname = BASE_URL.replace(
        'https://', '').replace('http://', '').split('/')[0]
    context = ssl.create_default_context()

    with socket.create_connection((hostname, 443)) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert = ssock.getpeercert()
            assert cert is not None
