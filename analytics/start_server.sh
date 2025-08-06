#!/bin/bash

# Start Analytics Server Script
echo "🚀 Starting BreakoutStrategy Analytics Server"
echo "=============================================="

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found. Please run setup_database.sh first."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Check if database is running
echo "🔍 Checking database connection..."
python -c "from database.manager import analytics_db; analytics_db.connect(); print('✅ Database connected'); analytics_db.disconnect()"

if [ $? -ne 0 ]; then
    echo "❌ Database connection failed. Please ensure the database is running:"
    echo "   docker compose up -d"
    exit 1
fi

# Start the Flask server
echo "🌐 Starting Flask server on http://localhost:5001"
echo "   Press Ctrl+C to stop the server"
echo ""

python app.py
