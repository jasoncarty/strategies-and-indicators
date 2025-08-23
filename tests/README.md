# Testing Framework

This directory contains the testing framework for the trading strategies project. The framework has been simplified to use the new configuration system, eliminating complex conditional logic and duplicated code.

## 🎯 **Key Features**

- **Configuration-based**: Uses `config/testing.json` for all test settings
- **Simple fixtures**: Clean pytest fixtures for database, services, and clients
- **No complex managers**: Eliminated `test_db_manager.py` and `test_webserver_manager.py`
- **Environment isolation**: Tests run in isolated environment with separate database

## 🚀 **Quick Start**

### 1. Setup Test Environment
```bash
# From project root
./scripts/setup_test_env.sh
```

### 2. Run Tests
```bash
# Run all tests
python -m pytest tests/ -v

# Run specific test categories
python -m pytest tests/unit/ -v
python -m pytest tests/integration/ -v

# Run specific test file
python -m pytest tests/example_test.py -v
```

## 📋 **Available Fixtures**

### **Session-scoped fixtures** (created once for all tests)
- `test_config`: Loads test configuration from `config/testing.json`
- `test_database`: Creates and manages test database lifecycle
- `test_services`: Starts test services (analytics, ML) on configured ports

### **Function-scoped fixtures** (created for each test)
- `test_db_connection`: Database connection for individual tests
- `test_analytics_client`: HTTP client for testing analytics endpoints
- `test_ml_client`: HTTP client for testing ML endpoints

## 🔧 **Configuration**

The test configuration is defined in `config/templates/testing.json.template` and generated as `config/testing.json`:

```json
{
  "environment": "testing",
  "database": {
    "host": "localhost",
    "port": 3306,
    "name": "test_breakout_analytics",
    "user": "breakout_user",
    "password": "breakout_password_2024"
  },
  "services": {
    "analytics": {
      "host": "0.0.0.0",
      "port": 5002
    },
    "ml_service": {
      "host": "0.0.0.0",
      "port": 5004
    }
  }
}
```

## 📝 **Writing Tests**

### **Basic Test Structure**
```python
def test_something(test_config, test_db_connection):
    """Example test using fixtures"""
    # test_config provides configuration
    # test_db_connection provides database access

    with test_db_connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        assert result[0] == 1
```

### **Testing Services**
```python
def test_analytics_endpoint(test_analytics_client):
    """Test analytics service endpoint"""
    response = test_analytics_client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
```

### **Testing ML Service**
```python
def test_ml_endpoint(test_ml_client):
    """Test ML service endpoint"""
    response = test_ml_client.get("/health")
    assert response.status_code == 200
```

## 🗄️ **Test Database**

- **Name**: `test_breakout_analytics`
- **Lifecycle**: Created fresh for each test session, dropped after completion
- **Migrations**: Automatically run on test database setup
- **Isolation**: Completely separate from development/production databases

## 🔄 **Service Management**

- **Analytics Service**: Runs on port 5002 (configurable)
- **ML Service**: Runs on port 5004 (configurable)
- **Startup**: Services start automatically when tests begin
- **Cleanup**: Services stop automatically when tests complete

## 🧹 **Cleanup**

All test resources are automatically cleaned up:
- Test database is dropped
- Service processes are terminated
- Database connections are closed
- HTTP sessions are closed

## 📚 **Examples**

See `tests/example_test.py` for complete examples of how to use all fixtures and write tests.

## 🚨 **Troubleshooting**

### **Configuration Issues**
- Ensure `config/testing.json` exists (run `./scripts/setup_test_env.sh`)
- Check that MySQL is accessible with test credentials
- Verify test ports (5002, 5004) are available

### **Service Startup Issues**
- Check if ports are already in use
- Verify environment variables are set correctly
- Check service logs for startup errors

### **Database Issues**
- Ensure MySQL server is running
- Verify user permissions for test database
- Check migration script exists and is executable
