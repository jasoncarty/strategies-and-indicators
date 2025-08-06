#!/usr/bin/env python3
"""
Dynamic ML Utilities
===================

Utility functions for making ML code symbol-agnostic and dynamic.
"""

import re
from pathlib import Path
from typing import Dict, List, Optional

def extract_symbol_from_path(file_path: Path) -> str:
    """Extract symbol from file path dynamically"""
    # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
    path_parts = file_path.parts
    for i, part in enumerate(path_parts):
        if part in ['Models', 'BreakoutStrategy'] and i + 1 < len(path_parts):
            potential_symbol = path_parts[i + 1]
            # Check if it looks like a symbol (6 characters, mostly letters)
            if len(potential_symbol) == 6 and potential_symbol.isalpha():
                return potential_symbol

    # Try to extract from filename
    filename = file_path.name
    # Look for patterns like buy_EURUSD_PERIOD_H1.pkl
    symbol_match = re.search(r'[a-z]+_([A-Z]{6})_PERIOD_', filename)
    if symbol_match:
        return symbol_match.group(1)

    # Default fallback
    return "UNKNOWN_SYMBOL"

def extract_timeframe_from_path(file_path: Path) -> str:
    """Extract timeframe from file path dynamically"""
    # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
    path_parts = file_path.parts
    for i, part in enumerate(path_parts):
        if part in ['Models', 'BreakoutStrategy'] and i + 2 < len(path_parts):
            potential_timeframe = path_parts[i + 2]
            # Check if it looks like a timeframe
            if potential_timeframe in ['M5', 'M15', 'M30', 'H1', 'H4', 'D1']:
                return potential_timeframe

    # Try to extract from filename
    filename = file_path.name
    # Look for patterns like buy_EURUSD_PERIOD_H1.pkl
    timeframe_match = re.search(r'PERIOD_([A-Z][0-9]+)', filename)
    if timeframe_match:
        return timeframe_match.group(1)

    # Default fallback
    return "UNKNOWN_TIMEFRAME"

def create_dynamic_model_key(model_type: str, symbol: str, timeframe: str) -> str:
    """Create dynamic model key"""
    return f"{model_type}_{symbol}_PERIOD_{timeframe}"

def analyze_symbols_dynamically(df) -> Dict[str, Dict]:
    """Analyze all symbols in DataFrame dynamically"""
    if 'symbol' not in df.columns:
        return {}

    symbol_analysis = {}
    for symbol in df['symbol'].unique():
        symbol_data = df[df['symbol'] == symbol]
        symbol_analysis[symbol] = {
            'total_trades': len(symbol_data),
            'timeframes': symbol_data['timeframe'].unique().tolist() if 'timeframe' in symbol_data.columns else [],
            'timeframe_distribution': symbol_data['timeframe'].value_counts().to_dict() if 'timeframe' in symbol_data.columns else {},
            'success_rate': (symbol_data['success'] == 1).mean() if 'success' in symbol_data.columns else 0.0
        }

    return symbol_analysis

def get_all_symbols_from_data(df) -> List[str]:
    """Get all unique symbols from DataFrame"""
    if 'symbol' not in df.columns:
        return []
    return df['symbol'].unique().tolist()

def get_symbol_timeframe_combinations(df) -> List[tuple]:
    """Get all symbol-timeframe combinations from DataFrame"""
    if 'symbol' not in df.columns or 'timeframe' not in df.columns:
        return []
    return df[['symbol', 'timeframe']].drop_duplicates().values.tolist()
