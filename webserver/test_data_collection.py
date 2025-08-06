#!/usr/bin/env python3
"""
Test script to verify data collection from SimpleBreakoutML_EA
"""

import json
import os
import sys
from pathlib import Path

def test_ml_data_file():
    """Test ML data file format and content"""
    print("🔍 Testing ML Data File...")
    
    # Path to ML data file
    ml_data_path = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_ML_Data.json"
    
    if not ml_data_path.exists():
        print("❌ ML data file not found:", ml_data_path)
        return False
    
    try:
        with open(ml_data_path, 'r') as f:
            data = json.load(f)
        
        trades = data.get('trades', [])
        print(f"✅ ML data file loaded successfully")
        print(f"📊 Found {len(trades)} trades in ML data")
        
        if len(trades) > 0:
            # Check first trade structure
            first_trade = trades[0]
            required_fields = ['trade_id', 'test_run_id', 'symbol', 'direction', 'entry', 'sl', 'tp', 'rsi', 'stoch_main']
            missing_fields = [field for field in required_fields if field not in first_trade]
            
            if missing_fields:
                print(f"❌ Missing required fields in ML data: {missing_fields}")
                return False
            else:
                print(f"✅ ML data structure is correct")
                print(f"📊 Sample trade: {first_trade['symbol']} {first_trade['direction']} at {first_trade['entry']}")
        
        return True
        
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON in ML data file: {e}")
        return False
    except Exception as e:
        print(f"❌ Error reading ML data file: {e}")
        return False

def test_trade_results_file():
    """Test trade results file format and content"""
    print("\n🔍 Testing Trade Results File...")
    
    # Path to trade results file
    trade_results_path = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json"
    
    if not trade_results_path.exists():
        print("❌ Trade results file not found:", trade_results_path)
        return False
    
    try:
        with open(trade_results_path, 'r') as f:
            data = json.load(f)
        
        # Check if it's a list (new format) or dict with trade_results (old format)
        if isinstance(data, list):
            trades = data
        else:
            trades = data.get('trade_results', [])
        
        print(f"✅ Trade results file loaded successfully")
        print(f"📊 Found {len(trades)} trades in results")
        
        if len(trades) > 0:
            # Check first trade structure
            first_trade = trades[0]
            required_fields = ['test_run_id', 'trade_id', 'symbol', 'direction', 'open_price', 'close_price', 'net_profit', 'trade_success']
            missing_fields = [field for field in required_fields if field not in first_trade]
            
            if missing_fields:
                print(f"❌ Missing required fields in trade results: {missing_fields}")
                return False
            else:
                print(f"✅ Trade results structure is correct")
                print(f"📊 Sample result: {first_trade['symbol']} {first_trade['direction']} - Profit: ${first_trade['net_profit']}")
                
                # Check success rates
                successful_trades = [t for t in trades if t.get('trade_success', False)]
                win_rate = len(successful_trades) / len(trades) * 100 if trades else 0
                print(f"📊 Win rate: {win_rate:.1f}% ({len(successful_trades)}/{len(trades)})")
        
        return True
        
    except json.JSONDecodeError as e:
        print(f"❌ Invalid JSON in trade results file: {e}")
        return False
    except Exception as e:
        print(f"❌ Error reading trade results file: {e}")
        return False

def test_data_linking():
    """Test if ML data and trade results can be linked"""
    print("\n🔍 Testing Data Linking...")
    
    # Load both files
    ml_data_path = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_ML_Data.json"
    trade_results_path = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json"
    
    if not ml_data_path.exists() or not trade_results_path.exists():
        print("❌ Cannot test linking - one or both files missing")
        return False
    
    try:
        # Load ML data
        with open(ml_data_path, 'r') as f:
            ml_data = json.load(f)
        ml_trades = ml_data.get('trades', [])
        
        # Load trade results
        with open(trade_results_path, 'r') as f:
            trade_data = json.load(f)
        
        if isinstance(trade_data, list):
            result_trades = trade_data
        else:
            result_trades = trade_data.get('trade_results', [])
        
        print(f"📊 ML trades: {len(ml_trades)}")
        print(f"📊 Result trades: {len(result_trades)}")
        
        if len(ml_trades) == 0 or len(result_trades) == 0:
            print("❌ Cannot test linking - one or both files are empty")
            return False
        
        # Try to link by test_run_id and trade_id
        linked_count = 0
        for ml_trade in ml_trades:
            ml_test_run = ml_trade.get('test_run_id', '')
            ml_trade_id = ml_trade.get('trade_id', 0)
            
            for result_trade in result_trades:
                result_test_run = result_trade.get('test_run_id', '')
                result_trade_id = result_trade.get('trade_id', 0)
                
                if ml_test_run == result_test_run and ml_trade_id == result_trade_id:
                    linked_count += 1
                    break
        
        print(f"📊 Successfully linked {linked_count} trades")
        
        if linked_count > 0:
            print("✅ Data linking is working")
            return True
        else:
            print("❌ No trades could be linked")
            return False
            
    except Exception as e:
        print(f"❌ Error testing data linking: {e}")
        return False

def main():
    """Main test function"""
    print("🧪 Testing SimpleBreakoutML_EA Data Collection")
    print("=" * 50)
    
    # Test ML data file
    ml_data_ok = test_ml_data_file()
    
    # Test trade results file
    trade_results_ok = test_trade_results_file()
    
    # Test data linking
    linking_ok = test_data_linking()
    
    print("\n" + "=" * 50)
    print("📊 Test Results Summary:")
    print(f"   ML Data File: {'✅ OK' if ml_data_ok else '❌ FAILED'}")
    print(f"   Trade Results File: {'✅ OK' if trade_results_ok else '❌ FAILED'}")
    print(f"   Data Linking: {'✅ OK' if linking_ok else '❌ FAILED'}")
    
    if ml_data_ok and trade_results_ok and linking_ok:
        print("\n🎉 All tests passed! Data collection is working correctly.")
        return 0
    else:
        print("\n⚠️  Some tests failed. Check the EA data collection.")
        return 1

if __name__ == "__main__":
    sys.exit(main()) 