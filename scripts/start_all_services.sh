#!/bin/bash

# Start All Trading Services with Docker Compose
# This script starts all services using the appropriate environment file

echo "🚀 Starting all trading services with Docker Compose..."

# Determine environment
ENV_FILE="docker.dev.env"
if [ "$1" = "test" ]; then
    ENV_FILE="docker.test.env"
    echo "🧪 Using test environment: $ENV_FILE"
elif [ "$1" = "prod" ]; then
    ENV_FILE="docker.env"
    echo "🏭 Using production environment: $ENV_FILE"
else
    echo "🔧 Using development environment: $ENV_FILE"
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Error: docker-compose is not installed"
    exit 1
fi

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: Environment file $ENV_FILE not found"
    exit 1
fi

echo "📋 Starting services..."
echo "   🗄️  MySQL Database"
echo "   📊 Analytics Service"
echo "   🤖 ML Prediction Service"
echo "   🎨 React Dashboard"
echo "   🔄 ML Retraining Service"

# Start all services
docker-compose --env-file "$ENV_FILE" up -d

# Wait for services to be ready
echo ""
echo "⏳ Waiting for services to be ready..."

# Wait for MySQL
echo "   ⏳ Waiting for MySQL..."
while ! docker-compose --env-file "$ENV_FILE" exec -T mysql mysqladmin ping -h"localhost" -u"root" -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; do
    echo "      Waiting for MySQL..."
    sleep 3
done
echo "      ✅ MySQL is ready!"

# Wait for analytics service
echo "   ⏳ Waiting for analytics service..."
while ! curl -f "http://localhost:$ANALYTICS_PORT/health" > /dev/null 2>&1; do
    echo "      Waiting for analytics service..."
    sleep 3
done
echo "      ✅ Analytics service is ready!"

# Wait for ML service
echo "   ⏳ Waiting for ML service..."
while ! curl -f "http://localhost:$ML_SERVICE_PORT/health" > /dev/null 2>&1; do
    echo "      Waiting for ML service..."
    sleep 3
done
echo "      ✅ ML service is ready!"

# Wait for dashboard
echo "   ⏳ Waiting for dashboard..."
while ! curl -f "http://localhost:$DASHBOARD_PORT" > /dev/null 2>&1; do
    echo "      Waiting for dashboard..."
    sleep 3
done
echo "      ✅ Dashboard is ready!"

# Wait for retraining service
echo "   ⏳ Waiting for retraining service..."
while ! curl -f "http://localhost:$RETRAINING_PORT/health" > /dev/null 2>&1; do
    echo "      Waiting for retraining service..."
    sleep 3
done
echo "      ✅ Retraining service is ready!"

echo ""
echo "🎉 All services are ready!"
echo ""
echo "🌐 Services available at:"
echo "   🗄️  MySQL:           localhost:$DB_PORT"
echo "   📊 Analytics API:    http://localhost:$ANALYTICS_PORT"
echo "   🤖 ML Service:       http://localhost:$ML_SERVICE_PORT"
echo "   🎨 Dashboard:        http://localhost:$DASHBOARD_PORT"
echo "   🔄 Retraining:       http://localhost:$RETRAINING_PORT"
echo ""
echo "📋 To view logs: docker-compose --env-file $ENV_FILE logs -f"
echo "🛑 To stop:      docker-compose --env-file $ENV_FILE down"

