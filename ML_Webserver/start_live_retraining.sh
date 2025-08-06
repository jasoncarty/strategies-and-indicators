#!/bin/bash
# Start Live Retraining Service

echo "🚀 Starting Live Retraining Service..."

# Check if analytics server is running
if ! curl -s http://127.0.0.1:5001/health > /dev/null; then
    echo "❌ Analytics server is not running on port 5001"
    echo "   Please start the analytics server first:"
    echo "   cd ../analytics && python app.py"
    echo "   or"
    echo "   cd ../analytics && nohup python app.py > analytics_server.log 2>&1 &"
    exit 1
fi

echo "✅ Analytics server is running"

# Start the live retraining service
echo "🔄 Starting live retraining service in background..."
nohup python live_retraining_service.py --start > live_retraining.log 2>&1 &

echo "✅ Live retraining service started!"
echo "📋 To monitor the service:"
echo "   tail -f live_retraining.log"
echo "   python live_retraining_service.py --status"
echo ""
echo "📋 To stop the service:"
echo "   python live_retraining_service.py --stop"
echo "   or"
echo "   pkill -f live_retraining_service.py"
