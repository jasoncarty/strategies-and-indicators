# Integration Tests

This directory contains integration tests that verify end-to-end functionality using the new pytest framework and DRY configuration system.

## 🎯 **New Integration Tests (Using New Framework)**

### **`test_database_migrations_new.py`**
- **Purpose**: Test database migrations and schema verification
- **Uses**: `test_db_connection` fixture, new configuration system
- **Tests**:
  - Migration log table existence and structure
  - Core tables creation
  - Database connectivity
  - Migration execution order

### **`test_end_to_end_workflow_new.py`**
- **Purpose**: Test end-to-end service communication and configuration
- **Uses**: `test_config`, `test_analytics_client`, `test_ml_client` fixtures
- **Tests**:
  - Service health endpoints
  - Service communication
  - Configuration consistency
  - Database configuration
  - Service URL validation

### **`test_ml_retraining_integration_new.py`**
- **Purpose**: Test ML service integration and endpoints
- **Uses**: `test_config`, `test_ml_client` fixtures
- **Tests**:
  - ML service model endpoints
  - Performance and health endpoints
  - Model reload functionality
  - Bulk prediction endpoints
  - ML service configuration
  - Analytics integration

## 🔧 **Legacy Integration Tests (Need Updates)**

The following tests still use the old `test_db_manager` and need to be updated:

- `test_database_migrations.py` - ❌ References deleted `test_db_manager`
- `test_database_scenarios.py` - ❌ References deleted `test_db_manager`
- `test_database_verification.py` - ❌ References deleted `test_db_manager`
- `test_end_to_end_workflow.py` - ❌ References deleted `test_db_manager`
- `test_ml_retraining_integration.py` - ❌ References deleted `test_db_manager`

## 🚀 **Benefits of New Framework**

1. **DRY Configuration**: Uses `test_config.get_test_analytics_port()` instead of direct access
2. **Pytest Fixtures**: Clean, maintainable test setup and teardown
3. **Service Management**: Automatic service startup/shutdown via fixtures
4. **Database Isolation**: Separate test database for each test session
5. **Configuration Consistency**: All tests use the same configuration source

## 📋 **Running Integration Tests**

```bash
# Run all new integration tests
python -m pytest tests/integration/test_*_new.py -v

# Run specific test file
python -m pytest tests/integration/test_end_to_end_workflow_new.py -v

# Run tests that don't require services
python -m pytest tests/integration/test_end_to_end_workflow_new.py::test_configuration_consistency -v
```

## 🔄 **Migration Path**

To migrate legacy tests to the new framework:

1. **Replace imports**: Remove `from tests.test_db_manager import create_test_database_manager`
2. **Use fixtures**: Replace manual setup with pytest fixtures
3. **Use DRY methods**: Replace `config.analytics.port` with `config.get_test_analytics_port()`
4. **Convert to pytest**: Change from `unittest.TestCase` to pytest functions

## 📊 **Current Status**

- **New Tests**: ✅ Working with new framework
- **Legacy Tests**: ❌ Need updates to remove old manager references
- **Configuration**: ✅ Using DRY methods successfully
- **Service Management**: ✅ Automatic via pytest fixtures
