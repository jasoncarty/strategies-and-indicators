#!/bin/bash

# BreakoutStrategy Analytics Database Setup Script
echo "🚀 Setting up BreakoutStrategy Analytics Database"
echo "=================================================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not available. Please ensure Docker Desktop is running."
    exit 1
fi

echo "✅ Docker and Docker Compose are available"

# Stop any existing containers
echo "🛑 Stopping any existing containers..."
docker compose down 2>/dev/null

# Start the database
echo "🐳 Starting MySQL database container..."
docker compose up -d

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
sleep 10

# Check if database is running
if docker compose ps | grep -q "Up"; then
    echo "✅ Database container is running"
else
    echo "❌ Database container failed to start"
    docker compose logs mysql
    exit 1
fi

# Install Python dependencies
echo "📦 Installing Python dependencies..."
cd "$(dirname "$0")"
pip install -r requirements.txt

# Run migrations
echo "🔄 Running database migrations..."
python database/run_migrations.py

echo ""
echo "🎉 Database setup complete!"
echo "=========================="
echo "📊 Database Details:"
echo "   Host: localhost"
echo "   Port: 3306"
echo "   Database: breakout_analytics"
echo "   User: breakout_user"
echo "   Password: breakout_password_2024"
echo ""
echo "🔧 Management Commands:"
echo "   Start database: docker compose up -d"
echo "   Stop database:  docker compose down"
echo "   View logs:      docker compose logs mysql"
echo "   Reset database: docker compose down && docker volume rm analytics_mysql_data && docker compose up -d"
echo ""
echo "📈 Next Steps:"
echo "   1. Integrate analytics into your BreakoutStrategy_ML.mq5"
echo "   2. Start collecting trade data"
echo "   3. Analyze performance with the analytics system"
echo ""
echo "🌐 Optional: Uncomment phpMyAdmin in docker-compose.yml for web-based database management"
