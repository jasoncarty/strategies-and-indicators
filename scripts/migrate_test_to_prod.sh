#!/bin/bash

# Test to Production Analytics Migration Script
# This script migrates data from the test container to the production container

set -e

echo "🚀 Starting Test to Production Analytics Migration"
echo "=================================================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Check if both containers are running
echo "🔍 Checking container status..."

# Check test container
if ! docker ps | grep -q "trading_test_analytics"; then
    echo "❌ Test analytics container is not running"
    echo "💡 Start it with: docker-compose --profile mysql,analytics up -d"
    exit 1
fi

# Check production container
if ! docker ps | grep -q "trading_dev_analytics"; then
    echo "❌ Production analytics container is not running"
    echo "💡 Start it with: docker-compose --profile mysql,analytics,ml_service,nginx,dashboard up -d"
    exit 1
fi

echo "✅ Both containers are running"

# Confirm migration
echo ""
echo "⚠️  WARNING: This will overwrite the production analytics database!"
echo "📊 Source: Test container (trading_test_analytics)"
echo "🎯 Target: Production container (trading_dev_analytics)"
echo ""
read -p "Are you sure you want to proceed? (y/N): " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "🛑 Migration cancelled by user"
    exit 0
fi

echo ""
echo "🔍 Running dry-run migration to verify data..."
echo "================================================"

# Run dry-run migration
python3 scripts/migrate_analytics_db.py \
    --from-container test \
    --to-container dev \
    --dry-run

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Dry-run completed successfully!"
    echo ""
    read -p "Do you want to proceed with the actual migration? (y/N): " CONFIRM

    if [[ $CONFIRM =~ ^[Yy]$ ]]; then
        echo ""
        echo "🚀 Starting actual migration..."
        echo "================================="

        # Run actual migration with backup
        python3 scripts/migrate_analytics_db.py \
            --from-container test \
            --to-container dev \
            --backup

        if [ $? -eq 0 ]; then
            echo ""
            echo "🎉 Migration completed successfully!"
            echo "📊 Your test analytics data is now in the production container"
            echo "🔍 Check the logs/ directory for detailed migration reports"
            echo ""
            echo "💡 Next steps:"
            echo "   1. Verify the data in your production dashboard"
            echo "   2. Test the analytics endpoints"
            echo "   3. Monitor for any issues"
        else
            echo ""
            echo "❌ Migration failed. Check the logs for details."
            exit 1
        fi
    else
        echo "🛑 Migration cancelled by user"
    fi
else
    echo ""
    echo "❌ Dry-run failed. Please check the logs and try again."
    exit 1
fi
