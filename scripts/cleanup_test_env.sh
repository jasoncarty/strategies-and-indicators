#!/bin/bash
# Clean up test environment

set -e

echo "🧹 Cleaning up test environment..."

# Stop and remove test containers
echo "🛑 Stopping test containers..."
docker-compose --env-file docker.test.env down

# Remove test volumes (optional - uncomment if you want to completely reset test data)
# echo "🗑️ Removing test volumes..."
# docker volume rm trading_test_mysql_data 2>/dev/null || echo "Test volume already removed"

echo "✅ Test environment cleaned up!"
echo ""
echo "To restart test environment:"
echo "  ./scripts/setup_test_env.sh"
