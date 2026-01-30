# Testing Infrastructure

This directory contains test suites for the Circle of Trust application.

## Quick Setup

### Windows
```cmd
setup-tests.bat
```

### Linux/Mac
```bash
chmod +x setup-tests.sh
./setup-tests.sh
```

## Manual Setup

```bash
# Create virtual environment
python3 -m venv test-venv

# Activate (Windows)
test-venv\Scripts\activate.bat

# Activate (Linux/Mac)
source test-venv/bin/activate

# Install dependencies
pip install -r tests/requirements.txt
```

## Running Tests

### Smoke Tests
```bash
# Run all smoke tests
pytest tests/smoke/

# Run with custom endpoint
BASE_URL=https://circle.example.com pytest tests/smoke/

# Run specific test
pytest tests/smoke/test_smoke.py::test_health_endpoint

# Verbose output
pytest tests/smoke/ -v

# With coverage
pytest tests/smoke/ --cov=. --cov-report=html
```

### Performance Tests
```bash
# Run k6 performance tests
docker run --rm -v $(pwd)/tests/performance:/scripts \
  loadimpact/k6:latest run /scripts/basic-load-test.js
```

## Test Structure

```
tests/
├── __init__.py              # Package marker
├── requirements.txt         # Test dependencies
├── smoke/                   # Smoke tests
│   ├── __init__.py
│   ├── test_smoke.py       # Main smoke test suite
│   └── README.md
└── performance/            # Performance tests
    └── basic-load-test.js  # k6 load test
```

## Environment Variables

- `BASE_URL` - API endpoint to test (default: http://localhost:8000)
- `ENVIRONMENT` - Environment name (production/staging)

## Test Dependencies

All dependencies are in [requirements.txt](requirements.txt):
- pytest - Testing framework
- pytest-cov - Coverage reporting
- pytest-mock - Mocking support
- pytest-asyncio - Async test support
- pytest-timeout - Test timeouts
- pytest-xdist - Parallel execution
- requests - HTTP client
- httpx - Async HTTP client
- faker - Test data generation
- responses - HTTP mocking
- freezegun - Time mocking

## CI/CD Integration

Tests are automatically run in the Jenkins pipeline:
- Pre-deployment: Unit and integration tests
- Post-deployment: Smoke tests
- Performance: k6 load tests

See [Jenkinsfile](../Jenkinsfile) for pipeline configuration.

## Troubleshooting

### pytest not found
```bash
# Make sure virtual environment is activated
source test-venv/bin/activate  # or test-venv\Scripts\activate.bat

# Verify pytest is installed
pip list | grep pytest
```

### Connection errors
```bash
# Check BASE_URL is correct
echo $BASE_URL

# Test endpoint manually
curl $BASE_URL/health
```

### Import errors
```bash
# Reinstall dependencies
pip install -r tests/requirements.txt --force-reinstall
```
