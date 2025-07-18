#!/usr/bin/env python3
import json

# Load the trade results file
with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/SimpleBreakoutML_EA/SimpleBreakoutML_EA_Trade_Results.json', 'r') as f:
    data = json.load(f)

trades = data['trade_results']
total_profit = sum(trade['net_profit'] for trade in trades)
profitable_trades = sum(1 for trade in trades if trade['net_profit'] > 0)

print(f'Total trades: {len(trades)}')
print(f'Total net profit: ${total_profit:.2f}')
print(f'Profitable trades: {profitable_trades}')
print(f'Win rate: {profitable_trades/len(trades)*100:.1f}%')

# Show first few trades for verification
print("\nFirst 5 trades:")
for i, trade in enumerate(trades[:5]):
    print(f"Trade {i+1}: {trade['direction']} {trade['volume']} lots, Profit: ${trade['net_profit']:.2f}")

# Show last few trades
print("\nLast 5 trades:")
for i, trade in enumerate(trades[-5:]):
    print(f"Trade {len(trades)-4+i}: {trade['direction']} {trade['volume']} lots, Profit: ${trade['net_profit']:.2f}") 