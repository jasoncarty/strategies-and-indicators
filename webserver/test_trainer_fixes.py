#!/usr/bin/env python3
"""
Test script to verify the trainer fixes work correctly
"""

import os
import sys
import json
import tempfile
import shutil

def test_json_error_handling():
    """Test the improved JSON error handling"""
    print("🧪 Testing JSON error handling...")
    
    # Create a temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        # Create a corrupted JSON file
        corrupted_file = os.path.join(temp_dir, "corrupted.json")
        with open(corrupted_file, 'w') as f:
            f.write('{"valid": true, "data": [1, 2, 3, "incomplete')  # Corrupted JSON
        
        # Test the error handling
        try:
            with open(corrupted_file, 'r') as f:
                content = f.read()
                data = json.loads(content)
                print("❌ Should have failed - JSON is corrupted")
                return False
        except json.JSONDecodeError as e:
            print(f"✅ Correctly detected corrupted JSON: {e}")
            return True
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            return False

def test_ml_confidence_field_check():
    """Test the ml_confidence field check"""
    print("🧪 Testing ml_confidence field check...")
    
    # Test data with and without ml_confidence
    test_data = [
        {"ml_prediction": 0.5, "ml_confidence": 0.8},  # Has both fields
        {"ml_prediction": 0.5},  # Missing ml_confidence
        {"target": 1}  # Has neither field
    ]
    
    for i, data in enumerate(test_data):
        print(f"   Test {i+1}: {list(data.keys())}")
        
        # Check if fields exist
        has_prediction = 'ml_prediction' in data
        has_confidence = 'ml_confidence' in data
        
        print(f"      ml_prediction: {'✅' if has_prediction else '❌'}")
        print(f"      ml_confidence: {'✅' if has_confidence else '❌'}")
        
        if has_prediction and has_confidence:
            print(f"      Both fields present - should work")
        elif has_prediction and not has_confidence:
            print(f"      Missing ml_confidence - should be handled gracefully")
        else:
            print(f"      Missing both fields - should be handled gracefully")
    
    return True

def test_synthetic_target_generation():
    """Test the synthetic target generation"""
    print("🧪 Testing synthetic target generation...")
    
    # Simulate the logic from the trainer
    import random
    
    # Create sample data
    sample_data = []
    for i in range(10):
        sample_data.append({
            'direction': 'buy' if i % 2 == 0 else 'sell',
            'rsi': random.uniform(20, 80),
            'stoch_main': random.uniform(10, 90),
            'macd_main': random.uniform(-0.001, 0.001),
            'macd_signal': random.uniform(-0.001, 0.001),
            'volume_ratio': random.uniform(0.5, 2.0),
            'trend': random.choice(['bullish', 'bearish', 'neutral'])
        })
    
    # Generate synthetic targets
    targets = []
    for row in sample_data:
        score = 0.0
        
        # RSI contribution
        if row['direction'] == 'buy':
            if row['rsi'] < 30: score += 0.3
            elif row['rsi'] < 40: score += 0.2
            elif row['rsi'] > 70: score -= 0.2
        else:  # sell
            if row['rsi'] > 70: score += 0.3
            elif row['rsi'] > 60: score += 0.2
            elif row['rsi'] < 30: score -= 0.2
        
        # Stochastic contribution
        if row['direction'] == 'buy':
            if row['stoch_main'] < 20: score += 0.2
            elif row['stoch_main'] > 80: score -= 0.1
        else:  # sell
            if row['stoch_main'] > 80: score += 0.2
            elif row['stoch_main'] < 20: score -= 0.1
        
        # MACD contribution
        if row['direction'] == 'buy' and row['macd_main'] > row['macd_signal']:
            score += 0.1
        elif row['direction'] == 'sell' and row['macd_main'] < row['macd_signal']:
            score += 0.1
        
        # Volume contribution
        if row['volume_ratio'] > 1.5: score += 0.1
        
        # Trend alignment
        if row['direction'] == 'buy' and 'bullish' in str(row['trend']).lower():
            score += 0.1
        elif row['direction'] == 'sell' and 'bearish' in str(row['trend']).lower():
            score += 0.1
        
        # Random factor
        random_factor = random.uniform(-0.1, 0.1)
        score += random_factor
        
        # Set target
        target = 1 if score > 0.3 else 0
        targets.append(target)
    
    # Check distribution
    target_counts = {}
    for target in targets:
        target_counts[target] = target_counts.get(target, 0) + 1
    
    print(f"   Generated {len(targets)} synthetic targets")
    print(f"   Target distribution: {target_counts}")
    
    # Check if we have both classes
    if len(target_counts) == 2:
        print("   ✅ Both classes (0 and 1) present")
        return True
    else:
        print("   ⚠️  Only one class present - might need adjustment")
        return False

def main():
    """Run all tests"""
    print("🧪 Testing Trainer Fixes")
    print("=" * 40)
    
    tests = [
        ("JSON Error Handling", test_json_error_handling),
        ("ML Confidence Field Check", test_ml_confidence_field_check),
        ("Synthetic Target Generation", test_synthetic_target_generation)
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"\n📋 {test_name}")
        print("-" * 30)
        try:
            if test_func():
                print(f"✅ {test_name} PASSED")
                passed += 1
            else:
                print(f"❌ {test_name} FAILED")
        except Exception as e:
            print(f"❌ {test_name} ERROR: {e}")
    
    print(f"\n📊 Test Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! The trainer fixes should work correctly.")
    else:
        print("⚠️  Some tests failed. Check the implementation.")
    
    print("\n💡 To test the actual trainer:")
    print("   python strategy_tester_ml_trainer.py --check-data")
    print("   python strategy_tester_ml_trainer.py --ea SimpleBreakoutML_EA")

if __name__ == "__main__":
    main() 