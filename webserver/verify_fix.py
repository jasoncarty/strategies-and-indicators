#!/usr/bin/env python3
print("Checking merge fix...")

# Read the improved_ml_trainer.py file and look for the merge logic
with open('improved_ml_trainer.py', 'r') as f:
    content = f.read()

# Look for the merge logic
if "on=['test_run_id', 'trade_id']" in content:
    print("✅ FIX APPLIED: Merge now uses both test_run_id AND trade_id")
else:
    print("❌ FIX NOT APPLIED: Merge still only uses test_run_id")

if "Merging on test_run_id AND trade_id for exact matching" in content:
    print("✅ FIX APPLIED: Proper merge message found")
else:
    print("❌ FIX NOT APPLIED: Proper merge message not found")

print("Fix verification complete!") 