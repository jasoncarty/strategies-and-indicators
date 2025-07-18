#!/usr/bin/env python3
import json
import os

def analyze_trade_file(file_path):
    """Comprehensive analysis of the trade results file"""
    print(f"🔍 Analyzing trade file: {file_path}")
    print("=" * 60)
    
    # Check if file exists
    if not os.path.exists(file_path):
        print(f"❌ File does not exist: {file_path}")
        return
    
    # Get file size
    file_size = os.path.getsize(file_path)
    print(f"📁 File size: {file_size:,} bytes")
    
    # Read the entire file content
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        print(f"📖 File content length: {len(content):,} characters")
        
        # Try to parse as JSON
        try:
            data = json.loads(content)
            print("✅ JSON parsing successful")
            
            # Analyze structure
            print(f"📊 JSON structure keys: {list(data.keys())}")
            
            if 'trade_results' in data:
                trades = data['trade_results']
                print(f"📈 Found 'trade_results' array with {len(trades)} trades")
                
                # Analyze first few trades
                print("\n🔍 First 5 trades:")
                for i, trade in enumerate(trades[:5]):
                    print(f"   Trade {i+1}: ID={trade.get('trade_id', 'N/A')}, "
                          f"Symbol={trade.get('symbol', 'N/A')}, "
                          f"Profit=${trade.get('net_profit', 0):.2f}")
                
                # Calculate totals
                total_profit = sum(trade.get('profit', 0) for trade in trades)
                total_swap = sum(trade.get('swap', 0) for trade in trades)
                total_commission = sum(trade.get('commission', 0) for trade in trades)
                total_net_profit = sum(trade.get('net_profit', 0) for trade in trades)
                
                print(f"\n💰 Summary:")
                print(f"   Total trades: {len(trades)}")
                print(f"   Total profit: ${total_profit:.2f}")
                print(f"   Total swap: ${total_swap:.2f}")
                print(f"   Total commission: ${total_commission:.2f}")
                print(f"   Total net profit (profit+swap+commission): ${total_profit + total_swap + total_commission:.2f}")
                print(f"   Total net_profit field sum: ${total_net_profit:.2f}")
                if abs((total_profit + total_swap + total_commission) - total_net_profit) > 1e-2:
                    print(f"⚠️  Mismatch between calculated net profit and net_profit field!")
                else:
                    print(f"✅ net_profit field matches calculated sum.")
                
                profitable_trades = sum(1 for trade in trades if trade.get('net_profit', 0) > 0)
                print(f"   Profitable trades: {profitable_trades}")
                print(f"   Win rate: {profitable_trades/len(trades)*100:.1f}%")
                
                # Check for unique test_run_ids
                test_run_ids = set(trade.get('test_run_id', 'N/A') for trade in trades)
                print(f"   Unique test run IDs: {len(test_run_ids)}")
                for run_id in test_run_ids:
                    print(f"     - {run_id}")
                
            elif 'test_results' in data:
                print(f"📈 Found 'test_results' array with {len(data['test_results'])} items")
                # This might be a different format
                print("⚠️  This appears to be a test summary file, not trade results")
                
            else:
                print("⚠️  No 'trade_results' or 'test_results' found in JSON")
                print(f"Available keys: {list(data.keys())}")
                
        except json.JSONDecodeError as e:
            print(f"❌ JSON parsing failed: {e}")
            print("🔍 This might be a malformed JSON file")
            
            # Try to find where the JSON breaks
            lines = content.split('\n')
            print(f"📄 File has {len(lines)} lines")
            
            # Look for potential JSON structure
            if 'trade_results' in content:
                print("✅ Found 'trade_results' in content")
                # Try to extract just the trade_results part
                start = content.find('"trade_results"')
                if start != -1:
                    print(f"📍 'trade_results' starts at position {start}")
                    
                    # Count opening brackets after trade_results
                    bracket_count = 0
                    trade_count = 0
                    in_trades = False
                    
                    for i, char in enumerate(content[start:]):
                        if char == '[' and not in_trades:
                            in_trades = True
                            bracket_count = 1
                        elif char == '[' and in_trades:
                            bracket_count += 1
                        elif char == ']' and in_trades:
                            bracket_count -= 1
                            if bracket_count == 0:
                                print(f"📍 'trade_results' array ends at position {start + i}")
                                break
                        elif char == '{' and in_trades:
                            trade_count += 1
                    
                    print(f"🔍 Estimated trade count from brackets: {trade_count}")
            
    except Exception as e:
        print(f"❌ Error reading file: {e}")

def main():
    # Path to the trade results file
    file_path = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json"
    
    analyze_trade_file(file_path)
    
    # Also check if there are multiple files
    print("\n" + "=" * 60)
    print("🔍 Checking for multiple trade result files...")
    
    base_dir = "/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/"
    
    if os.path.exists(base_dir):
        files = os.listdir(base_dir)
        trade_files = [f for f in files if 'Trade_Results' in f]
        
        print(f"📁 Found {len(trade_files)} trade result files:")
        for file in trade_files:
            full_path = os.path.join(base_dir, file)
            file_size = os.path.getsize(full_path)
            print(f"   {file}: {file_size:,} bytes")
            
            # Quick check of each file
            try:
                with open(full_path, 'r') as f:
                    content = f.read()
                    if 'trade_results' in content:
                        # Count trades by counting opening braces
                        trade_count = content.count('"trade_id"')
                        print(f"     Estimated trades: {trade_count}")
            except Exception as e:
                print(f"     Error reading: {e}")

if __name__ == "__main__":
    main() 