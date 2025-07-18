#!/usr/bin/env python3
"""
Clean and Restart ML Training Process
=====================================

This script cleans up corrupted ML training data and prepares for fresh training
with correctly labeled trade directions.

The problem: The EA was recording closing deal types instead of opening deal types,
which corrupted all the training data with wrong buy/sell labels.
"""

import os
import glob
import shutil
import json
from datetime import datetime

def clean_corrupted_data():
    """Remove all corrupted ML training data files"""
    print("🧹 CLEANING CORRUPTED ML TRAINING DATA")
    print("=" * 50)
    
    # Files to clean up
    files_to_remove = [
        "StrategyTester_ML_Data.json",
        "StrategyTester_Results.json", 
        "StrategyTester_Trade_Results.json",
        "StrategyTester_Comprehensive_Results.json",
        "ml_model_params_simple.txt",
        "ml_model_params.json"
    ]
    
    # Directories to clean up
    dirs_to_remove = [
        "ml_models"
    ]
    
    # Remove files
    removed_files = 0
    for filename in files_to_remove:
        if os.path.exists(filename):
            os.remove(filename)
            print(f"🗑️  Removed: {filename}")
            removed_files += 1
        else:
            print(f"✅ Already clean: {filename}")
    
    # Remove directories
    removed_dirs = 0
    for dirname in dirs_to_remove:
        if os.path.exists(dirname):
            shutil.rmtree(dirname)
            print(f"🗑️  Removed directory: {dirname}")
            removed_dirs += 1
        else:
            print(f"✅ Already clean: {dirname}")
    
    # Also clean up any backup files
    backup_patterns = [
        "*.json.bak",
        "*.txt.bak", 
        "*.pkl.bak"
    ]
    
    for pattern in backup_patterns:
        for filepath in glob.glob(pattern):
            os.remove(filepath)
            print(f"🗑️  Removed backup: {filepath}")
            removed_files += 1
    
    print(f"\n📊 Cleanup Summary:")
    print(f"   Files removed: {removed_files}")
    print(f"   Directories removed: {removed_dirs}")
    print("✅ Data cleanup completed!")

def create_fresh_directories():
    """Create fresh directories for new training data"""
    print("\n📁 CREATING FRESH DIRECTORIES")
    print("=" * 30)
    
    directories = [
        "ml_models",
        "data_backups"
    ]
    
    for directory in directories:
        if not os.path.exists(directory):
            os.makedirs(directory)
            print(f"📁 Created: {directory}")
        else:
            print(f"✅ Already exists: {directory}")

def create_restart_instructions():
    """Create instructions for restarting the training process"""
    print("\n📋 RESTART INSTRUCTIONS")
    print("=" * 30)
    
    instructions = f"""
🧹 CLEANUP COMPLETED - READY FOR FRESH START

The corrupted ML training data has been removed. Here's what to do next:

1. 🎯 RUN THE EA WITH CORRECTED DIRECTION RECORDING
   - The EA now correctly records opening deal types (not closing)
   - This will generate clean, properly labeled training data
   - Run a Strategy Tester session to collect new data

2. 📊 COLLECT FRESH TRAINING DATA
   - Run the EA in Strategy Tester for at least 50-100 trades
   - Ensure both buy and sell trades are generated
   - The data will be saved with correct direction labels

3. 🤖 RETRAIN THE ML MODEL
   - Run: python strategy_tester_ml_trainer.py
   - This will train on the fresh, correct data
   - Generate new optimized parameters

4. 🔄 UPDATE THE EA
   - The new parameters will be automatically copied to MetaTrader
   - Test the EA with the fresh ML model

IMPORTANT NOTES:
- All previous ML training data was corrupted due to wrong direction labels
- The new data will have correct buy/sell labels based on opening deal types
- This should result in much better ML model performance
- The separate buy/sell models will now be trained on correctly labeled data

Cleanup completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
    
    # Save instructions to file
    with open("RESTART_INSTRUCTIONS.txt", "w") as f:
        f.write(instructions)
    
    print("📝 Instructions saved to: RESTART_INSTRUCTIONS.txt")
    print(instructions)

def verify_ea_fix():
    """Verify that the EA has the correct direction recording fix"""
    print("\n🔍 VERIFYING EA FIX")
    print("=" * 20)
    
    ea_file = "../Experts/StrategyTesterML_EA.mq5"
    
    if not os.path.exists(ea_file):
        print("❌ EA file not found!")
        return False
    
    try:
        with open(ea_file, 'r') as f:
            content = f.read()
        
        # Check for the fix: using opening deal type instead of closing
        if "trades[tradeCount].type = (HistoryDealGetInteger(openTicket, DEAL_TYPE) == DEAL_TYPE_BUY) ? \"BUY\" : \"SELL\"" in content:
            print("✅ EA has correct direction recording fix")
            print("   - Uses opening deal type for trade direction")
            print("   - Will generate correct buy/sell labels")
            return True
        else:
            print("❌ EA does NOT have the direction recording fix!")
            print("   - Still using closing deal type (incorrect)")
            print("   - Need to apply the fix before collecting new data")
            return False
            
    except Exception as e:
        print(f"❌ Error checking EA file: {e}")
        return False

def main():
    """Main cleanup and restart process"""
    print("🚀 ML TRAINING CLEANUP AND RESTART")
    print("=" * 50)
    print("This will remove all corrupted ML training data and prepare for fresh training.")
    print("The corruption was caused by the EA recording wrong trade directions.")
    print()
    
    # Verify EA fix first
    if not verify_ea_fix():
        print("\n⚠️  WARNING: EA does not have the direction recording fix!")
        print("Please apply the fix to the EA before proceeding.")
        print("The fix ensures correct buy/sell labels in training data.")
        return
    
    # Clean up corrupted data
    clean_corrupted_data()
    
    # Create fresh directories
    create_fresh_directories()
    
    # Create restart instructions
    create_restart_instructions()
    
    print("\n🎉 CLEANUP AND RESTART COMPLETED!")
    print("=" * 40)
    print("✅ All corrupted data removed")
    print("✅ Fresh directories created") 
    print("✅ EA has correct direction recording fix")
    print("✅ Ready for fresh ML training")
    print("\n📋 Next steps:")
    print("   1. Run the EA in Strategy Tester to collect fresh data")
    print("   2. Run: python strategy_tester_ml_trainer.py")
    print("   3. Test the EA with new ML parameters")

if __name__ == "__main__":
    main() 