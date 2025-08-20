#!/bin/bash

# Start ML Trading Analytics Dashboard
# This script starts both the analytics server and the React dashboard

echo "🚀 Starting ML Trading Analytics Dashboard..."

# Check if we're in the right directory
if [ ! -f "app.py" ]; then
    echo "❌ Error: Please run this script from the analytics directory"
    exit 1
fi

# Function to cleanup background processes
cleanup() {
    echo "🛑 Shutting down services..."
    if [ ! -z "$ANALYTICS_PID" ]; then
        kill $ANALYTICS_PID 2>/dev/null
        echo "   ✅ Analytics server stopped"
    fi
    if [ ! -z "$DASHBOARD_PID" ]; then
        kill $DASHBOARD_PID 2>/dev/null
        echo "   ✅ Dashboard stopped"
    fi
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start analytics server in background
echo "📊 Starting analytics server..."
python app.py &
ANALYTICS_PID=$!

# Wait a moment for server to start
sleep 3

# Check if analytics server is running
if ! curl -s http://localhost:5001/health > /dev/null; then
    echo "❌ Analytics server failed to start"
    exit 1
fi

echo "✅ Analytics server running on http://localhost:5001"

# Start React dashboard in background
echo "🎨 Starting React dashboard..."
cd dashboard
npm start &
DASHBOARD_PID=$!

# Wait a moment for dashboard to start
sleep 5

echo "✅ Dashboard starting on http://localhost:3000"
echo ""
echo "🌐 Services running:"
echo "   📊 Analytics Server: http://localhost:5001"
echo "   🎨 React Dashboard:  http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop all services"

# Wait for user to stop
wait
