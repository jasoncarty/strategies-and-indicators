#!/bin/bash

# Setup Test Environment Script
# Uses the new configuration system to set up testing

set -e

echo "🔧 Setting up test environment..."

# Check if we're in the right directory
if [ ! -f "config/__init__.py" ]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

echo "🔧 Setting up test environment..."

# Create test directories
echo "📁 Creating test directories..."
mkdir -p tests/logs
mkdir -p tests/test_models
mkdir -p tests/test_models/backups

# Set up test database using Docker MySQL container
echo "🗄️ Setting up test database using Docker MySQL container..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Start complete test environment using docker-compose with test environment variables
echo "🚀 Starting complete test environment (MySQL + Analytics + ML)..."
docker-compose --env-file docker.test.env up -d

# Wait for all services to be ready
echo "⏳ Waiting for all test services to be ready..."
sleep 20

# Verify test database access
echo "🔍 Verifying test database access..."
docker exec trading_test_mysql mysql -u test_user -ptest_password_2024 -e "
    USE test_breakout_analytics;
    SELECT 1 as test;
" 2>/dev/null && echo "✅ Test database access verified" || echo "⚠️ Test database access failed"

# Verify test services are running
echo "🔍 Verifying test services are running..."
if docker ps | grep -q trading_analytics; then
    echo "✅ Test analytics service is running"
else
    echo "⚠️ Test analytics service is not running"
fi

if docker ps | grep -q trading_ml_service; then
    echo "✅ Test ML service is running"
else
    echo "⚠️ Test ML service is not running"
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 10

echo "🎯 Test environment setup complete!"
echo "   - MySQL: localhost:3308 (test database)"
echo "   - Analytics: localhost:5002"
echo "   - ML Service: localhost:5004"

echo "✅ Test environment setup complete!"
echo ""
echo "To run tests:"
echo "  python -m pytest tests/ -v"
echo ""
echo "To run specific test categories:"
echo "  python -m pytest tests/unit/ -v"
echo "  python -m pytest tests/integration/ -v"
