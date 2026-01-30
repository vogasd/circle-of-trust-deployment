# Smoke Tests

This directory contains smoke tests that run against deployed environments.

## Running Tests

```bash
# Activate virtual environment
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run smoke tests
pytest tests/smoke/ --environment=production

# Or with custom BASE_URL
BASE_URL=https://circle.example.com pytest tests/smoke/
```

## Test Coverage

- Health endpoint validation
- Readiness checks
- API version verification
- Metrics endpoint
- Basic LLM interaction
- Database connectivity
- Response time validation
- Concurrent request handling
- SSL validation (production only)
