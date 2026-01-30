import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 10 },  // Ramp up to 10 users
    { duration: '5m', target: 10 },  // Stay at 10 users
    { duration: '2m', target: 20 },  // Ramp up to 20 users
    { duration: '5m', target: 20 },  // Stay at 20 users
    { duration: '2m', target: 0 },   // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],  // 95% of requests should be below 500ms
    errors: ['rate<0.1'],              // Error rate should be less than 10%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

export default function () {
  // Test health endpoint
  let healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    'health check status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  sleep(1);

  // Test API endpoint
  let apiRes = http.get(`${BASE_URL}/api/v1/status`);
  check(apiRes, {
    'api status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  }) || errorRate.add(1);

  sleep(2);

  // Test LLM endpoint (if available)
  const payload = JSON.stringify({
    prompt: 'Hello, how are you?',
    model: 'llama2',
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  let llmRes = http.post(`${BASE_URL}/api/v1/chat`, payload, params);
  check(llmRes, {
    'llm response is 200': (r) => r.status === 200,
    'llm response time < 2000ms': (r) => r.timings.duration < 2000,
  }) || errorRate.add(1);

  sleep(3);
}

export function handleSummary(data) {
  return {
    'k6-results.json': JSON.stringify(data),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}
