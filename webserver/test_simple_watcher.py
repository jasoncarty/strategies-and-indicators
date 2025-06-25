#!/usr/bin/env python3
"""
Test script for the simple enhanced watcher.
This script simulates file changes to test the watcher's behavior.
"""

import time
import os
import subprocess
import signal
import sys

def test_simple_watcher():
    """Test the simple enhanced watcher."""
    print("🧪 Testing Simple Enhanced Watcher")
    print("==================================")

    # Start the watcher in server-only mode
    print("🚀 Starting simple enhanced watcher in server-only mode...")

    try:
        # Start the watcher process
        process = subprocess.Popen(
            [sys.executable, 'simple_enhanced_watcher.py', '--server-only'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Wait for startup
        time.sleep(5)

        if process.poll() is not None:
            print("❌ Watcher failed to start")
            stdout, stderr = process.communicate()
            print(f"STDOUT: {stdout}")
            print(f"STDERR: {stderr}")
            return False

        print("✅ Watcher started successfully")

        # Test 1: Touch a watched file (should trigger restart)
        print("\n🧪 Test 1: Touching app.py (should trigger restart)")
        os.system('touch app.py')
        time.sleep(15)  # Wait for restart

        # Test 2: Touch an ignored file (should NOT trigger restart)
        print("\n🧪 Test 2: Touching ignored file (should NOT trigger restart)")
        os.system('touch test_ignored_file.py')
        time.sleep(5)

        # Test 3: Touch a template file (should trigger restart)
        print("\n🧪 Test 3: Touching template file (should trigger restart)")
        os.system('touch templates/test_template.html')
        time.sleep(15)

        # Check if process is still running
        if process.poll() is None:
            print("✅ Watcher is still running after tests")
        else:
            print("❌ Watcher stopped unexpectedly")
            stdout, stderr = process.communicate()
            print(f"STDOUT: {stdout}")
            print(f"STDERR: {stderr}")
            return False

        # Clean up
        print("\n🛑 Stopping watcher...")
        process.terminate()
        process.wait(timeout=10)

        print("✅ Test completed successfully")
        return True

    except Exception as e:
        print(f"❌ Test failed: {e}")
        if 'process' in locals():
            process.terminate()
        return False

if __name__ == "__main__":
    success = test_simple_watcher()
    sys.exit(0 if success else 1)
