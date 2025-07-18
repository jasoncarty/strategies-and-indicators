#!/usr/bin/env python3
import json

# Load trade results
with open('/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/StrategyTester_Trade_Results.json', 'r') as f:
    data = json.load(f)
    trades = data['trade_results']

# Analyze by direction
buy_trades = [t for t in trades if t['direction'] == 'buy']
sell_trades = [t for t in trades if t['direction'] == 'sell']

buy_wins = [t for t in buy_trades if t['profit'] > 0]
sell_wins = [t for t in sell_trades if t['profit'] > 0]

print(f'BUY TRADES: {len(buy_trades)} total')
print(f'  Wins: {len(buy_wins)} ({len(buy_wins)/len(buy_trades)*100:.1f}%)')
print(f'  Total profit: ${sum(t["profit"] for t in buy_trades):.2f}')
print(f'  Avg profit: ${sum(t["profit"] for t in buy_trades)/len(buy_trades):.2f}')

print(f'\nSELL TRADES: {len(sell_trades)} total')
print(f'  Wins: {len(sell_wins)} ({len(sell_wins)/len(sell_trades)*100:.1f}%)')
print(f'  Total profit: ${sum(t["profit"] for t in sell_trades):.2f}')
print(f'  Avg profit: ${sum(t["profit"] for t in sell_trades)/len(sell_trades):.2f}')

print(f'\nOVERALL: {len(trades)} total trades')
print(f'  Total profit: ${sum(t["profit"] for t in trades):.2f}')
print(f'  Win rate: {len([t for t in trades if t["profit"] > 0])/len(trades)*100:.1f}%')

# Show individual trades
print(f'\nINDIVIDUAL TRADES:')
for i, trade in enumerate(trades, 1):
    print(f'  {i:2d}. {trade["direction"]:4s} - ${trade["profit"]:7.2f} - {trade["exit_reason"]}') 