#!/bin/bash

# Legacy Analytics to Test Container Migration Script
# This script migrates data from your legacy analytics database to the test container

set -e

echo "🚀 Starting Legacy Analytics to Test Container Migration"
echo "========================================================"

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Check if legacy container is running
echo "🔍 Checking if legacy container is running..."
if ! docker ps | grep -q "analytics"; then
    echo "❌ Legacy analytics container is not running"
    echo "💡 Start it with: docker-compose --profile mysql,analytics up -d"
    exit 1
fi

echo "✅ legacy container is running"

echo ""
echo "🔍 Running dry-run migration to verify connection and data..."
echo "=============================================================="

# Run dry-run migration using pre-configured container details
python3 scripts/migrate_analytics_db.py \
    --from-container legacy \
    --to-container prod \
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

        # Run actual migration
        python3 scripts/migrate_analytics_db.py \
            --from-container legacy \
            --to-container prod \
            --backup

        if [ $? -eq 0 ]; then
            echo ""
            echo "🎉 Migration completed successfully!"
            echo "📊 Your legacy analytics data is now in the legacy container"
            echo "🔍 Check the logs/ directory for detailed migration reports"
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
