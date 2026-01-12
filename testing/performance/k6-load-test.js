import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Ramp up to 10 users
    { duration: '5m', target: 10 },   // Stay at 10 users
    { duration: '2m', target: 50 },   // Ramp up to 50 users
    { duration: '5m', target: 50 },   // Stay at 50 users
    { duration: '2m', target: 100 },  // Ramp up to 100 users
    { duration: '5m', target: 100 },  // Stay at 100 users
    { duration: '2m', target: 0 },    // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete below 500ms
    http_req_failed: ['rate<0.1'],    // Error rate must be below 10%
    errors: ['rate<0.1'],             // Custom error rate must be below 10%
  },
};

// Test data
const BASE_URL = __ENV.BASE_URL || 'http://demo.dev.local';
const endpoints = [
  '/status/200',
  '/get',
  '/post',
  '/headers',
  '/user-agent',
];

export default function () {
  // Select random endpoint
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  const url = `${BASE_URL}${endpoint}`;

  // Make HTTP request
  const response = http.get(url, {
    headers: {
      'User-Agent': 'k6-load-test/1.0',
      'Accept': 'application/json',
    },
  });

  // Check response
  const result = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'response time < 1000ms': (r) => r.timings.duration < 1000,
    'response has body': (r) => r.body.length > 0,
  });

  // Record errors
  errorRate.add(!result);

  // Simulate user think time
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

// Setup function - runs once before the test
export function setup() {
  console.log('Starting load test...');
  console.log(`Target URL: ${BASE_URL}`);
  
  // Health check
  const response = http.get(`${BASE_URL}/status/200`);
  if (response.status !== 200) {
    throw new Error(`Health check failed: ${response.status}`);
  }
  
  return { baseUrl: BASE_URL };
}

// Teardown function - runs once after the test
export function teardown(data) {
  console.log('Load test completed');
  console.log(`Tested URL: ${data.baseUrl}`);
}

