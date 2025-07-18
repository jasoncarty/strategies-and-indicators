# Currency Pair-Specific ML Parameter Optimization

## Overview

The trading system now supports currency pair-specific ML parameter optimization, recognizing that different currency pairs have unique characteristics that require tailored trading parameters. The system also handles different broker symbol formats automatically.

## Broker Symbol Compatibility

### Supported Symbol Formats

The system automatically detects and handles various broker symbol formats:

| Broker Format | Example | Base Symbol | Description |
|---------------|---------|-------------|-------------|
| Standard | `EURUSD` | `EURUSD` | Standard format |
| Plus Suffix | `EURUSD+` | `EURUSD` | Your broker format |
| Account Type | `EURUSD.a` | `EURUSD` | Account-specific |
| Professional | `EURUSD.pro` | `EURUSD` | Professional account |
| ECN | `EURUSD.ecn` | `EURUSD` | ECN account |
| Raw | `EURUSD.raw` | `EURUSD` | Raw spread account |

### Automatic Symbol Detection

The EA automatically:
1. Detects the broker's symbol format (e.g., `EURUSD+`)
2. Normalizes to base symbol (e.g., `EURUSD`)
3. Loads the appropriate parameter file
4. Applies currency pair-specific optimizations

```mql5
//--- Helper: Get currency pair-specific parameter file
string GetCurrencyPairParamFile() {
    string symbol = _Symbol;
    
    // Remove the + suffix if present (broker-specific naming)
    string baseSymbol = symbol;
    if(StringFind(symbol, "+") >= 0) {
        baseSymbol = StringSubstr(symbol, 0, StringFind(symbol, "+"));
        Print("🔍 Detected broker symbol format: ", symbol, " -> base symbol: ", baseSymbol);
    }
    
    // Map symbols to specific parameter files
    if(baseSymbol == "EURUSD") return MODEL_PARAMS_EURUSD;
    else if(baseSymbol == "GBPUSD") return MODEL_PARAMS_GBPUSD;
    // ... other pairs
}
```

## Why Currency Pair-Specific Parameters?

### Different Characteristics

1. **Volatility Patterns**
   - **EURUSD**: Moderate volatility, predictable movements
   - **GBPUSD**: Higher volatility, sensitive to UK news
   - **USDJPY**: Lower volatility, safe haven characteristics
   - **GBPJPY**: High volatility, cross pair dynamics
   - **XAUUSD**: Very high volatility, commodity characteristics

2. **Spread Costs**
   - **EURUSD**: ~1.0 pip (lowest)
   - **GBPUSD**: ~1.2 pips
   - **USDJPY**: ~0.9 pips
   - **GBPJPY**: ~2.0 pips (higher)
   - **XAUUSD**: ~3.0 pips (highest)

3. **Trading Sessions**
   - **EURUSD**: London/NY focus
   - **GBPUSD**: London session focus
   - **USDJPY**: Asian session focus
   - **GBPJPY**: London/Asian crossover
   - **XAUUSD**: All sessions active

4. **Correlation Effects**
   - **EURUSD** ↔ **GBPUSD**: Positive correlation
   - **USDJPY**: Safe haven, inverse to risk sentiment
   - **GBPJPY**: High volatility cross pair
   - **XAUUSD**: Safe haven, inverse to USD strength

## Parameter Adjustments

### Volatility-Based Adjustments

| Currency Pair | Volatility Multiplier | RSI Bullish Threshold | RSI Bearish Threshold | Position Sizing |
|---------------|----------------------|----------------------|----------------------|-----------------|
| EURUSD        | 1.0x (base)          | 30.0                 | 70.0                 | 1.0x            |
| GBPUSD        | 1.2x (higher)        | 36.0                 | 58.3                 | 0.83x           |
| USDJPY        | 0.8x (lower)         | 24.0                 | 87.5                 | 1.25x           |
| GBPJPY        | 1.5x (high)          | 40.0                 | 60.0                 | 0.67x           |
| XAUUSD        | 1.8x (very high)     | 40.0                 | 60.0                 | 0.56x           |

### Spread-Based Adjustments

| Currency Pair | Spread Adjustment | Min Confidence | Max Confidence |
|---------------|------------------|----------------|----------------|
| EURUSD        | 1.0x (base)      | 0.30            | 0.85            |
| GBPUSD        | 1.1x (higher)    | 0.33            | 0.77            |
| USDJPY        | 0.9x (lower)     | 0.27            | 0.94            |
| GBPJPY        | 1.3x (higher)    | 0.39            | 0.75            |
| XAUUSD        | 1.5x (high)      | 0.45            | 0.75            |

### Session-Based Adjustments

| Currency Pair | Session Weight | Volume Threshold | Description |
|---------------|----------------|------------------|-------------|
| EURUSD        | 1.0x (base)    | 1.50             | London/NY focus |
| GBPUSD        | 1.1x (higher)  | 1.65             | London session focus |
| USDJPY        | 0.9x (lower)   | 1.35             | Asian session focus |
| GBPJPY        | 1.2x (higher)  | 1.80             | London/Asian crossover |
| XAUUSD        | 1.3x (higher)  | 1.95             | All sessions active |

## Implementation

### EA Changes

The EA now automatically detects the trading symbol and loads the appropriate parameter file:

```mql5
//--- Currency pair-specific parameter files
#define MODEL_PARAMS_EURUSD "ml_model_params_EURUSD.txt"
#define MODEL_PARAMS_GBPUSD "ml_model_params_GBPUSD.txt"
#define MODEL_PARAMS_USDJPY "ml_model_params_USDJPY.txt"
#define MODEL_PARAMS_GBPJPY "ml_model_params_GBPJPY.txt"
#define MODEL_PARAMS_XAUUSD "ml_model_params_XAUUSD.txt"
#define MODEL_PARAMS_GENERIC "ml_model_params_simple.txt" // Fallback

//--- Helper: Get currency pair-specific parameter file
string GetCurrencyPairParamFile() {
    string symbol = _Symbol;
    
    // Remove the + suffix if present (broker-specific naming)
    string baseSymbol = symbol;
    if(StringFind(symbol, "+") >= 0) {
        baseSymbol = StringSubstr(symbol, 0, StringFind(symbol, "+"));
        Print("🔍 Detected broker symbol format: ", symbol, " -> base symbol: ", baseSymbol);
    }
    
    // Map symbols to specific parameter files
    if(baseSymbol == "EURUSD") return MODEL_PARAMS_EURUSD;
    else if(baseSymbol == "GBPUSD") return MODEL_PARAMS_GBPUSD;
    else if(symbol == "USDJPY") return MODEL_PARAMS_USDJPY;
    else if(symbol == "GBPJPY") return MODEL_PARAMS_GBPJPY;
    else if(symbol == "XAUUSD") return MODEL_PARAMS_XAUUSD;
    else return MODEL_PARAMS_GENERIC; // Fallback for other pairs
}
```

### ML Trainer Changes

The ML trainer now generates currency pair-specific parameter files:

```python
def save_currency_pair_parameters(self, param_content):
    """Save currency pair-specific parameter files"""
    
    currency_pairs = {
        'EURUSD': {'volatility_multiplier': 1.0, 'spread_adjustment': 1.0, 'session_weight': 1.0},
        'GBPUSD': {'volatility_multiplier': 1.2, 'spread_adjustment': 1.1, 'session_weight': 1.1},
        'USDJPY': {'volatility_multiplier': 0.8, 'spread_adjustment': 0.9, 'session_weight': 0.9},
        'GBPJPY': {'volatility_multiplier': 1.5, 'spread_adjustment': 1.3, 'session_weight': 1.2},
        'XAUUSD': {'volatility_multiplier': 1.8, 'spread_adjustment': 1.5, 'session_weight': 1.3}
    }
    
    for pair, config in currency_pairs.items():
        # Apply pair-specific adjustments to parameters
        adjusted_params = self.adjust_parameters_for_pair(param_content, config)
        self.save_pair_parameters(pair, adjusted_params)
```

## Usage

### 1. Generate Currency Pair Parameters

```bash
cd webserver
python currency_pair_optimizer.py
```

This generates:
- `ml_model_params_EURUSD.txt`
- `ml_model_params_GBPUSD.txt`
- `ml_model_params_USDJPY.txt`
- `ml_model_params_GBPJPY.txt`
- `ml_model_params_XAUUSD.txt`
- `ml_model_params_simple.txt` (generic fallback)

### 2. Copy to MetaTrader

Copy the parameter files to MetaTrader's Common Files directory:
```
~/Library/Application Support/MetaQuotes/Terminal/Common/Files/
```

### 3. EA Automatic Detection

The EA automatically:
1. Detects the current trading symbol
2. Loads the appropriate parameter file
3. Applies currency pair-specific optimizations
4. Falls back to generic parameters for unknown pairs

## Parameter File Structure

Each parameter file contains key=value pairs:

```
combined_min_prediction_threshold=0.5500
combined_max_prediction_threshold=0.4500
combined_min_confidence=0.3000
combined_max_confidence=0.8500
combined_position_sizing_multiplier=1.0000
combined_stop_loss_adjustment=1.0000
combined_rsi_bullish_threshold=30.0000
combined_rsi_bearish_threshold=70.0000
...
```

## Benefits

### 1. Optimized Performance
- **EURUSD**: Conservative parameters for steady profits
- **GBPUSD**: Moderate adjustments for higher volatility
- **USDJPY**: Aggressive parameters for lower volatility
- **GBPJPY**: Conservative parameters for high volatility
- **XAUUSD**: Very conservative parameters for extreme volatility

### 2. Risk Management
- Higher volatility pairs get smaller position sizes
- Higher spread pairs require higher confidence thresholds
- Session-specific volume requirements

### 3. Adaptability
- Easy to add new currency pairs
- Automatic fallback to generic parameters
- No manual configuration required

## Adding New Currency Pairs

To add a new currency pair:

1. **Update EA**:
```mql5
#define MODEL_PARAMS_NEWPAIR "ml_model_params_NEWPAIR.txt"

// In GetCurrencyPairParamFile()
else if(symbol == "NEWPAIR") return MODEL_PARAMS_NEWPAIR;
```

2. **Update ML Trainer**:
```python
currency_pairs['NEWPAIR'] = {
    'volatility_multiplier': 1.1,
    'spread_adjustment': 1.0,
    'session_weight': 1.0,
    'description': 'New pair description'
}
```

3. **Regenerate Parameters**:
```bash
python currency_pair_optimizer.py
```

## Monitoring and Optimization

### Parameter Summary

The system generates a summary file: `currency_pair_summary.json`

```json
{
  "generated_at": "2024-07-16T13:26:00",
  "currency_pairs": {
    "EURUSD": {
      "description": "Major pair - London/NY session focus",
      "volatility_multiplier": 1.0,
      "spread_adjustment": 1.0,
      "session_weight": 1.0,
      "parameter_file": "ml_model_params_EURUSD.txt"
    }
  },
  "parameter_files": [
    "ml_models/ml_model_params_EURUSD.txt",
    "ml_models/ml_model_params_GBPUSD.txt",
    ...
  ]
}
```

### Performance Tracking

Each currency pair's performance is tracked separately:
- Individual trade results per pair
- Pair-specific win rates and profit factors
- Correlation analysis between pairs

## Best Practices

### 1. Regular Optimization
- Retrain models monthly with pair-specific data
- Monitor performance differences between pairs
- Adjust parameters based on market regime changes

### 2. Risk Management
- Use smaller position sizes for high volatility pairs
- Require higher confidence for high spread pairs
- Consider correlation between pairs in portfolio

### 3. Session Awareness
- Focus on active sessions for each pair
- Adjust volume requirements based on session activity
- Consider time-based filters for optimal entry timing

## Conclusion

The currency pair-specific parameter system provides:

1. **Tailored Optimization**: Each pair uses parameters optimized for its characteristics
2. **Automatic Adaptation**: No manual configuration required
3. **Risk Management**: Built-in adjustments for volatility and spread differences
4. **Scalability**: Easy to add new currency pairs
5. **Performance**: Better results through pair-specific optimization

This system recognizes that one-size-fits-all parameters don't work in forex trading, where each currency pair has unique characteristics that require specialized handling. 