#!/bin/bash

# Development Startup Script for MT5 Strategy Tester
# This script provides different startup options for development

echo "=== MT5 Strategy Tester Development Startup ==="
echo ""
echo "Choose your startup mode:"
echo "1) Standard mode - Start server only"
echo "2) Enhanced mode - Start server with file watching (recommended)"
echo "3) Server-only mode - Start server, watch only server files"
echo "4) MT5-only mode - Start server, watch only MT5 files"
echo "5) Exit"
echo ""

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo "Starting in standard mode..."
        python3 app.py
        ;;
    2)
        echo "Starting in enhanced mode (watching both MT5 and server files)..."
        python3 simple_enhanced_watcher.py --both
        ;;
    3)
        echo "Starting in server-only mode (watching only server files)..."
        python3 simple_enhanced_watcher.py --server-only
        ;;
    4)
        echo "Starting in MT5-only mode (watching only MT5 files)..."
        python3 simple_enhanced_watcher.py --mt5-only
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice. Please run the script again."
        exit 1
        ;;
esac
