#!/bin/bash
# Switch between different Docker environments

set -e

ENV_FILE=""

case "$1" in
    "dev"|"development")
        ENV_FILE="docker.dev.env"
        echo "🚀 Switching to DEVELOPMENT environment"
        ;;
    "test"|"testing")
        ENV_FILE="docker.test.env"
        echo "🧪 Switching to TESTING environment"
        ;;
    "prod"|"production")
        ENV_FILE="docker.prod.env"
        echo "🏭 Switching to PRODUCTION environment"
        ;;
    *)
        echo "Usage: $0 {dev|test|prod}"
        echo "  dev   - Development environment (ports 5004, 5005, 3307)"
        echo "  test  - Testing environment (ports 5002, 5003, 3308)"
        echo "  prod  - Production environment (ports 5006, 5007, 3309)"
        exit 1
        ;;
esac

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Environment file $ENV_FILE not found"
    exit 1
fi

# Stop any running containers
echo "🛑 Stopping any running containers..."
docker-compose down 2>/dev/null || true

# Start the selected environment
echo "🚀 Starting $1 environment..."
docker-compose --env-file "$ENV_FILE" up -d

echo "✅ $1 environment started successfully!"
echo ""
echo "Container names:"
echo "  MySQL: $(grep CONTAINER_PREFIX "$ENV_FILE" | cut -d'=' -f2)_mysql"
echo "  Analytics: $(grep CONTAINER_PREFIX "$ENV_FILE" | cut -d'=' -f2)_analytics"
echo "  ML Service: $(grep CONTAINER_PREFIX "$ENV_FILE" | cut -d'=' -f2)_ml_service"
echo ""
echo "Ports:"
echo "  MySQL: $(grep DB_PORT "$ENV_FILE" | cut -d'=' -f2)"
echo "  Analytics: $(grep ANALYTICS_PORT "$ENV_FILE" | cut -d'=' -f2)"
echo "  ML Service: $(grep ML_SERVICE_PORT "$ENV_FILE" | cut -d'=' -f2)"
