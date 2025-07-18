#!/bin/bash

# Cleanup script for old Strategy Tester data files
# This removes old data collected before the strategy improvements

echo "🧹 Cleaning up old Strategy Tester data files..."

# Path to MetaTrader Common Files directory
MT5_COMMON_FILES="/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"

# Files to remove (old data files)
FILES_TO_REMOVE=(
    "StrategyTester_ML_Data.json"
    "StrategyTester_Results.json"
    "StrategyTester_Trade_Results.json"
    "StrategyTester_Comprehensive_Results.json"
)

# Files to keep (ML models and parameters)
FILES_TO_KEEP=(
    "ml_model_params_simple.txt"
    "ml_model_params.json"
    "buy_trade_success_predictor.pkl"
    "sell_trade_success_predictor.pkl"
    "trade_success_predictor.pkl"
    "buy_scaler.pkl"
    "sell_scaler.pkl"
    "scaler.pkl"
    "buy_label_encoders.pkl"
    "sell_label_encoders.pkl"
    "combined_label_encoders.pkl"
)

echo "📁 Target directory: $MT5_COMMON_FILES"
echo ""

# Check if directory exists
if [ ! -d "$MT5_COMMON_FILES" ]; then
    echo "❌ Error: MetaTrader Common Files directory not found!"
    echo "   Expected: $MT5_COMMON_FILES"
    exit 1
fi

echo "🗑️  Removing old data files:"
for file in "${FILES_TO_REMOVE[@]}"; do
    filepath="$MT5_COMMON_FILES/$file"
    if [ -f "$filepath" ]; then
        echo "   Removing: $file"
        rm "$filepath"
    else
        echo "   Not found: $file"
    fi
done

echo ""
echo "✅ Preserving ML models and parameters:"
for file in "${FILES_TO_KEEP[@]}"; do
    filepath="$MT5_COMMON_FILES/$file"
    if [ -f "$filepath" ]; then
        echo "   Keeping: $file"
    else
        echo "   Not found: $file"
    fi
done

echo ""
echo "📊 Summary of remaining files:"
ls -la "$MT5_COMMON_FILES"/*.json "$MT5_COMMON_FILES"/*.pkl "$MT5_COMMON_FILES"/*.txt 2>/dev/null | grep -E "(StrategyTester|ml_model)" || echo "   No remaining data files found"

echo ""
echo "🎯 Cleanup complete! Ready for fresh data collection with improved strategy."
echo ""
echo "📝 Next steps:"
echo "   1. Run the updated EA in Strategy Tester"
echo "   2. Collect fresh data with proper zone detection and new indicators"
echo "   3. Train ML models with enhanced feature set"
echo "   4. Compare results with previous baseline" 