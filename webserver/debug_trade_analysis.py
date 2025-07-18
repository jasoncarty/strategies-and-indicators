#!/usr/bin/env python3
import json
import pandas as pd

def debug_trade_analysis():
    """Debug the trade analysis to find the issue"""
    
    # Load trade results
    with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Trade_Results.json', 'r') as f:
        data = json.load(f)
        trades = data['trade_results']
    
    # Convert to DataFrame (like the ML trainer does)
    df = pd.DataFrame(trades)
    
    print("🔍 DEBUGGING TRADE ANALYSIS")
    print("=" * 50)
    
    # Show the raw data
    print("📊 RAW TRADE DATA:")
    for i, trade in enumerate(trades, 1):
        print(f"  {i:2d}. {trade['direction']:4s} - ${trade['profit']:7.2f} - {trade['exit_reason']}")
    
    print(f"\n📊 DATAFRAME INFO:")
    print(f"Shape: {df.shape}")
    print(f"Columns: {list(df.columns)}")
    print(f"Direction values: {df['direction'].unique()}")
    print(f"Profit values: {df['profit'].tolist()}")
    
    # Replicate the ML trainer logic exactly
    print(f"\n🔍 REPLICATING ML TRAINER LOGIC:")
    
    total_trades = len(df)
    print(f"Total trades: {total_trades}")
    
    # Direction analysis
    buy_trades = df[df['direction'] == 'buy']
    sell_trades = df[df['direction'] == 'sell']
    
    print(f"Buy trades filter: df['direction'] == 'buy'")
    print(f"Buy trades found: {len(buy_trades)}")
    print(f"Buy trades data:")
    for i, trade in buy_trades.iterrows():
        print(f"  {trade['direction']} - ${trade['profit']:.2f}")
    
    print(f"\nSell trades filter: df['direction'] == 'sell'")
    print(f"Sell trades found: {len(sell_trades)}")
    print(f"Sell trades data:")
    for i, trade in sell_trades.iterrows():
        print(f"  {trade['direction']} - ${trade['profit']:.2f}")
    
    # Calculate win rates
    if len(buy_trades) > 0:
        buy_wins = buy_trades[buy_trades['profit'] > 0]
        buy_win_rate = (len(buy_wins) / len(buy_trades)) * 100
        buy_total_profit = buy_trades['profit'].sum()
        print(f"\nBuy analysis:")
        print(f"  Total buy trades: {len(buy_trades)}")
        print(f"  Winning buy trades: {len(buy_wins)}")
        print(f"  Buy win rate: {buy_win_rate:.1f}%")
        print(f"  Buy total profit: ${buy_total_profit:.2f}")
    
    if len(sell_trades) > 0:
        sell_wins = sell_trades[sell_trades['profit'] > 0]
        sell_win_rate = (len(sell_wins) / len(sell_trades)) * 100
        sell_total_profit = sell_trades['profit'].sum()
        print(f"\nSell analysis:")
        print(f"  Total sell trades: {len(sell_trades)}")
        print(f"  Winning sell trades: {len(sell_wins)}")
        print(f"  Sell win rate: {sell_win_rate:.1f}%")
        print(f"  Sell total profit: ${sell_total_profit:.2f}")
    
    # Check for any data type issues
    print(f"\n🔍 DATA TYPE ANALYSIS:")
    print(f"Direction column type: {df['direction'].dtype}")
    print(f"Profit column type: {df['profit'].dtype}")
    print(f"Direction values (as list): {df['direction'].tolist()}")
    
    # Check for any whitespace or case issues
    print(f"\n🔍 STRING ANALYSIS:")
    for direction in df['direction'].unique():
        print(f"Direction '{direction}' - length: {len(direction)}, repr: {repr(direction)}")
    
    # Manual verification
    print(f"\n🔍 MANUAL VERIFICATION:")
    buy_count = 0
    sell_count = 0
    buy_wins = 0
    sell_wins = 0
    
    for trade in trades:
        if trade['direction'] == 'buy':
            buy_count += 1
            if trade['profit'] > 0:
                buy_wins += 1
        elif trade['direction'] == 'sell':
            sell_count += 1
            if trade['profit'] > 0:
                sell_wins += 1
    
    print(f"Manual count - Buy: {buy_count}, Sell: {sell_count}")
    print(f"Manual wins - Buy: {buy_wins}, Sell: {sell_wins}")
    print(f"Manual win rates - Buy: {buy_wins/buy_count*100:.1f}%, Sell: {sell_wins/sell_count*100:.1f}%")

if __name__ == "__main__":
    debug_trade_analysis() 