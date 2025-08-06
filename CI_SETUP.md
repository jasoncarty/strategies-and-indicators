# CI/CD Setup for GitHub Actions

## Overview

This document describes the CI/CD setup for running tests in GitHub Actions, including how Flask servers and MySQL databases are configured for automated testing.

## Architecture

The CI/CD pipeline runs the following components:

1. **MySQL Database** - Running in Docker container
2. **Analytics Service** - Flask app on port 5001
3. **ML Prediction Service** - Flask app on port 5003
4. **Test Suite** - Unit and integration tests

## GitHub Actions Workflow

### Services

The workflow uses GitHub Actions services to provide a MySQL database:

```yaml
services:
  mysql:
    image: mysql:8.0
    env:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: test_breakout_analytics
      MYSQL_USER: testuser
      MYSQL_PASSWORD: testpass
    ports:
      - 3306:3306
    options: --health-cmd="mysqladmin ping" --health-interval=10s --health-timeout=5s --health-retries=3
```

### Environment Variables

The following environment variables are set for the Flask services:

```yaml
env:
  TEST_DATABASE: test_breakout_analytics
  TEST_DB_HOST: 127.0.0.1
  TEST_DB_PORT: 3306
  TEST_DB_USER: root
  TEST_DB_PASSWORD: rootpassword
  FLASK_RUN_PORT: 5001
  ML_SERVICE_PORT: 5003
```

## Test Execution

### CI Test Runner

The `tests/ci_test_runner.py` script handles:

1. **Service Management** - Starting and stopping Flask services
2. **Health Checks** - Verifying services are ready before running tests
3. **Test Execution** - Running all test suites in the correct order
4. **Cleanup** - Ensuring services are properly stopped

### Test Categories

1. **Unit Tests** - Fast, isolated tests that don't require services
2. **Feature Engineering Tests** - Tests for the shared feature engineering utility
3. **Database Tests** - Tests for database migrations and schema
4. **End-to-End Tests** - Full workflow tests using the Flask services
5. **ML Retraining Tests** - Tests for the ML retraining system

## Local Development vs CI

### Local Development
- Uses local MySQL instance
- Services run on default ports (5001, 5003)
- Manual service management

### CI Environment
- Uses GitHub Actions MySQL service
- Services run on specified ports
- Automated service management via CI test runner

## Troubleshooting

### Common Issues

1. **Database Connection Failures**
   - Check MySQL service is running
   - Verify environment variables are set correctly
   - Ensure database exists and is accessible

2. **Service Startup Failures**
   - Check port availability
   - Verify dependencies are installed
   - Check service logs for errors

3. **Test Failures**
   - Ensure services are healthy before running tests
   - Check test database state
   - Verify test data is properly set up

### Debugging

The CI test runner provides detailed logging:

- Service startup logs
- Health check results
- Test execution output
- Service shutdown confirmation

## Benefits

This CI setup provides:

1. **Automated Testing** - All tests run automatically on every push/PR
2. **Real Environment** - Tests run against actual Flask services and MySQL database
3. **Consistent Results** - Same environment for all test runs
4. **Early Detection** - Issues caught before deployment
5. **Confidence** - Ensures code changes don't break existing functionality

## Future Improvements

Potential enhancements:

1. **Parallel Testing** - Run different test categories in parallel
2. **Caching** - Cache dependencies and test artifacts
3. **Performance Testing** - Add performance benchmarks
4. **Security Testing** - Add security scanning
5. **Deployment Testing** - Test deployment process

## Manual Testing

To run the same tests locally:

```bash
# Start MySQL (if not already running)
docker run -d --name mysql-test \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=test_breakout_analytics \
  -p 3306:3306 \
  mysql:8.0

# Set environment variables
export TEST_DATABASE=test_breakout_analytics
export TEST_DB_HOST=127.0.0.1
export TEST_DB_PORT=3306
export TEST_DB_USER=root
export TEST_DB_PASSWORD=rootpassword
export FLASK_RUN_PORT=5001
export ML_SERVICE_PORT=5003

# Run tests
python tests/ci_test_runner.py
```

This ensures that local testing matches the CI environment exactly.
