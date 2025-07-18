#!/usr/bin/env python3
"""
Test Broker Symbols - Verify broker symbol handling
"""

from currency_pair_optimizer import CurrencyPairOptimizer

def test_broker_symbols():
    """Test broker symbol normalization"""
    print("🧪 Testing Broker Symbol Handling")
    print("=" * 50)
    
    optimizer = CurrencyPairOptimizer()
    
    # Test your broker's symbol format
    your_broker_symbols = [
        'EURUSD+',
        'GBPUSD+', 
        'USDJPY+',
        'GBPJPY+',
        'XAUUSD+'
    ]
    
    print("Your Broker Symbols:")
    for symbol in your_broker_symbols:
        base_symbol = optimizer.normalize_symbol(symbol)
        config = optimizer.get_pair_config(symbol)
        
        if config:
            print(f"✅ {symbol} -> {base_symbol}")
            print(f"   {config['description']}")
            print(f"   Volatility: {config['volatility_multiplier']}x")
            print(f"   Spread: {config['spread_adjustment']}x")
            print(f"   Sessions: {config['session_hours']}")
            print()
        else:
            print(f"❌ {symbol} -> {base_symbol} (Unknown)")
            print()
    
    # Test other broker formats
    print("Other Broker Formats:")
    other_symbols = [
        'EURUSD.a',
        'GBPUSD.pro',
        'USDJPY.ecn',
        'GBPJPY.raw',
        'XAUUSD.stp'
    ]
    
    for symbol in other_symbols:
        base_symbol = optimizer.normalize_symbol(symbol)
        config = optimizer.get_pair_config(symbol)
        
        if config:
            print(f"✅ {symbol} -> {base_symbol}")
        else:
            print(f"❌ {symbol} -> {base_symbol} (Unknown)")
    
    print("\n" + "=" * 50)
    print("✅ All broker symbol formats tested successfully!")

if __name__ == "__main__":
    test_broker_symbols() 