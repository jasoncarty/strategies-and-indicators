#!/bin/bash

# Enhanced File Watcher Startup Script for MT5 Strategy Tester
# This script starts the enhanced file watcher with proper environment setup

echo "🚀 Starting Enhanced MT5 Strategy Tester File Watcher..."

# Check if we're in the right directory
if [ ! -f "app.py" ]; then
    echo "❌ Error: app.py not found. Please run this script from the webserver directory."
    exit 1
fi

# Check if virtual environment exists
if [ -d "venv" ]; then
    echo "📦 Activating virtual environment..."
    source venv/bin/activate
else
    echo "⚠️  No virtual environment found. Using system Python."
fi

# Check if required packages are installed
echo "🔍 Checking required packages..."
python -c "import watchdog, requests, flask" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "❌ Missing required packages. Installing..."
    pip install watchdog requests flask flask-sqlalchemy flask-cors
fi

# Start the enhanced file watcher
echo "👀 Starting enhanced file watcher..."
echo "   - Press Ctrl+C to stop"
echo "   - Use --help for options"
echo ""

python enhanced_file_watcher.py "$@"
