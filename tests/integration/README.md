# Integration Tests

Integration tests for Circle of Trust that validate service-to-service communication.

## Running Locally

```bash
# Start test environment
docker-compose -f docker-compose.test.yml up -d

# Wait for services
sleep 30

# Run integration tests
docker-compose -f docker-compose.test.yml exec backend pytest tests/integration/ -v

# Cleanup
docker-compose -f docker-compose.test.yml down -v
```

## What to Test

- Database connectivity and CRUD operations
- Ollama service communication
- API endpoint integration
- Authentication flows
- Data persistence

## Writing Integration Tests

```python
import pytest
from your_app import create_app
from your_app.database import db

@pytest.fixture
def app():
    app = create_app('testing')
    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()

def test_conversation_creation(app):
    # Test full conversation flow
    response = app.test_client().post('/api/v1/conversations', json={
        'title': 'Test Conversation'
    })
    assert response.status_code == 201
    assert 'id' in response.json
```
