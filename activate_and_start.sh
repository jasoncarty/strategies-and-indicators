#!/bin/bash

# Activate virtual environment and start all servers
echo "🚀 Activating virtual environment and starting servers"
echo "======================================================"

# Check if we're in the right directory
if [ ! -f "requirements.txt" ]; then
    echo "❌ requirements.txt not found in current directory"
    echo "   Please run this script from the project root"
    exit 1
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "❌ Virtual environment not found"
    echo "   Please run setup_environment.py first"
    exit 1
fi

# Activate virtual environment
echo "📦 Activating virtual environment..."
source venv/bin/activate

# Verify activation
if [ -z "$VIRTUAL_ENV" ]; then
    echo "❌ Failed to activate virtual environment"
    exit 1
fi

echo "✅ Virtual environment activated: $VIRTUAL_ENV"

# Check if key packages are available
echo "🔍 Checking dependencies..."
python -c "import flask, pymysql, numpy, pandas, sklearn; print('✅ All dependencies available')"

if [ $? -ne 0 ]; then
    echo "❌ Missing dependencies"
    echo "   Please run setup_environment.py first"
    exit 1
fi

# Start all servers
echo "🚀 Starting all servers..."
python start_all_servers.py
