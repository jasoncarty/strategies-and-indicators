#!/bin/bash

echo "🎯 Starting Strategy Results Auto Analyzer..."
echo "📊 This will monitor StrategyTester_Results.json for changes"
echo "💡 Run a strategy test in MetaTrader to see automatic analysis"
echo ""

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "🔧 Activating virtual environment..."
    source venv/bin/activate
fi

# Start the auto analyzer
python3 auto_analyzer.py 