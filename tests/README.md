# Trading System Test Suite

This directory contains comprehensive unit and integration tests for the trading system components.

## Test Structure

```
tests/
├── unit/                    # Unit tests for individual components
│   ├── ea/                 # MT5 EA tests (MQL5)
│   ├── ml_service/         # ML Prediction Service tests
│   └── analytics/          # Analytics Service tests
├── integration/            # Integration tests for end-to-end workflows
├── conftest.py            # Pytest configuration and shared fixtures
├── requirements.txt        # Test dependencies
└── README.md              # This file
```

## Test Categories

### Unit Tests
- **ML Service Tests**: Test the ML prediction service functionality
- **Analytics Tests**: Test the analytics service and database operations
- **EA Tests**: Test MQL5 EA functionality (when available)

### Integration Tests
- **End-to-End Workflow**: Test complete data flow from MT5 EA → ML Service → Analytics
- **Service Connectivity**: Test service health and communication
- **Data Structure Consistency**: Ensure data formats are consistent across services

## Running Tests

### Prerequisites
1. Install test dependencies:
   ```bash
   pip install -r tests/requirements.txt
   ```

2. Ensure services are running (for integration tests):
   - ML Prediction Service (port 5003)
   - Analytics Service (port 5000)

### Running All Tests
```bash
python run_tests.py
```

### Running Specific Test Categories
```bash
# Unit tests only
python run_tests.py tests/unit/

# Integration tests only
python run_tests.py tests/integration/

# Specific test file
python run_tests.py tests/unit/ml_service/
```

### Using Pytest (Alternative)
```bash
# Install pytest
pip install pytest

# Run all tests
pytest tests/

# Run with coverage
pytest tests/ --cov=ML_Webserver --cov=analytics --cov-report=html
```

## Test Coverage

### ML Prediction Service
- ✅ Service initialization
- ✅ Feature preparation (19 → 28 features)
- ✅ Model loading and selection
- ✅ Prediction workflow
- ✅ Error handling
- ✅ Service status

### Analytics Service
- ✅ Database connectivity
- ✅ Data structure validation
- ✅ JSON serialization
- ✅ Error handling
- ✅ Timestamp handling

### Integration Tests
- ✅ Service connectivity
- ✅ Complete prediction workflow
- ✅ Data structure consistency
- ✅ Feature count validation
- ✅ Error handling across services

## Test Data

### Sample Features (MT5 EA → ML Service)
```python
{
    'rsi': 50.0,
    'stoch_main': 50.0,
    'stoch_signal': 50.0,
    'macd_main': 0.0,
    'macd_signal': 0.0,
    'bb_upper': 50000.0,
    'bb_lower': 49000.0,
    'williams_r': 50.0,
    'cci': 0.0,
    'momentum': 100.0,
    'force_index': 0.0,
    'volume_ratio': 1.0,
    'price_change': 0.001,
    'volatility': 0.001,
    'spread': 1.0,
    'session_hour': 12,
    'is_news_time': False,
    'day_of_week': 1,
    'month': 7
}
```

### Expected ML Service Output (28 Features)
The ML service adds 9 engineered features to the 19 basic features:
- **Base features**: 17 technical indicators
- **Time features**: 2 (day_of_week, month)
- **Engineered features**: 9 (regimes, sessions, etc.)

## Continuous Integration

Tests are automatically run on:
- Push to main/master branch
- Pull requests to main/master branch

### GitHub Actions
- Runs on Ubuntu with Python 3.8, 3.9, 3.10
- Installs all dependencies
- Runs unit and integration tests
- Uploads test results as artifacts

## Adding New Tests

### Unit Tests
1. Create test file in appropriate directory: `tests/unit/[service]/test_[component].py`
2. Inherit from `unittest.TestCase`
3. Use descriptive test method names
4. Include setup and teardown methods

### Integration Tests
1. Create test file in `tests/integration/`
2. Test complete workflows
3. Mock external dependencies when needed
4. Test error conditions

### Test Naming Convention
- Test files: `test_[component].py`
- Test classes: `Test[Component]`
- Test methods: `test_[functionality]`

## Troubleshooting

### Common Issues

1. **Import Errors**: Ensure Python path includes project directories
2. **Service Connection Errors**: Check if services are running on correct ports
3. **Missing Dependencies**: Install requirements from `tests/requirements.txt`
4. **Mock Data Issues**: Update sample data to match current feature sets

### Debug Mode
Run tests with verbose output:
```bash
python -m pytest tests/ -v -s
```

## Test Maintenance

### When to Update Tests
- When feature sets change
- When service APIs change
- When data structures are modified
- When new components are added

### Test Data Updates
- Keep sample data current with actual feature sets
- Update expected feature counts when models change
- Maintain realistic test scenarios

## Performance Considerations

- Unit tests should run quickly (< 1 second each)
- Integration tests may take longer due to service startup
- Use mocks for external dependencies in unit tests
- Consider parallel test execution for large test suites
