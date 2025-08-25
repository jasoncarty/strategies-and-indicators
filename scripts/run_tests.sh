#!/bin/bash

echo "🚀 Starting test suite execution..."

# Function to run tests with proper error handling
run_test_suite() {
    local test_type=$1
    local test_path=$2

    echo "📋 Running $test_type tests..."

    python3 -m pytest "$test_path" -v --tb=short
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ $test_type tests completed successfully"
    else
        echo "❌ $test_type tests failed with exit code $exit_code"
        return $exit_code
    fi
}

# Run integration tests (all use pytest)
echo "🔗 Running integration tests..."
run_test_suite "Integration" "tests/integration"
integration_exit_code=$?

# Run unit tests (all now use pytest)
echo "🧪 Running unit tests..."

# Analytics unit tests
echo "📊 Running analytics unit tests..."
run_test_suite "Analytics Unit" "tests/unit/analytics"
analytics_exit_code=$?

# ML Service unit tests
echo "🤖 Running ML service unit tests..."
run_test_suite "ML Service Unit" "tests/unit/ml_service"
ml_service_exit_code=$?

# EA unit tests (if any exist)
if [ -d "tests/unit/ea" ] && [ "$(ls -A tests/unit/ea)" ]; then
    echo "📈 Running EA unit tests..."
    run_test_suite "EA Unit" "tests/unit/ea"
    ea_exit_code=$?
else
    echo "ℹ️  No EA unit tests found, skipping..."
    ea_exit_code=0
fi

# Summary
echo ""
echo "📊 Test Suite Summary:"
echo "======================"

if [ $integration_exit_code -eq 0 ]; then
    echo "✅ Integration Tests: PASSED"
else
    echo "❌ Integration Tests: FAILED"
fi

if [ $analytics_exit_code -eq 0 ]; then
    echo "✅ Analytics Unit Tests: PASSED"
else
    echo "❌ Analytics Unit Tests: FAILED"
fi

if [ $ml_service_exit_code -eq 0 ]; then
    echo "✅ ML Service Unit Tests: PASSED"
else
    echo "❌ ML Service Unit Tests: FAILED"
fi

if [ $ea_exit_code -eq 0 ]; then
    echo "✅ EA Unit Tests: PASSED"
else
    echo "❌ EA Unit Tests: FAILED"
fi

# Overall result
total_exit_code=$((integration_exit_code + analytics_exit_code + ml_service_exit_code + ea_exit_code))

if [ $total_exit_code -eq 0 ]; then
    echo ""
    echo "🎉 All test suites completed successfully!"
    exit 0
else
    echo ""
    echo "⚠️  Some test suites failed. Check the output above for details."
    exit 1
fi
