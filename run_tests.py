#!/usr/bin/env python3
"""
Test Runner for Trading System
Runs all unit and integration tests using the new configuration-based testing framework
"""

import subprocess
import sys
import os
from pathlib import Path

# Add the project root to the path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Try to load test configuration to verify setup
try:
    from config import Config
    test_config = Config('testing')
    print(f"✅ Test configuration loaded: {test_config.environment}")
    print(f"   Database: {test_config.database.name}")
    print(f"   Analytics Port: {test_config.get_test_analytics_port()}")
    print(f"   ML Service Port: {test_config.get_test_ml_port()}")
except Exception as e:
    print(f"⚠️ Could not load test configuration: {e}")
    print("   Run './scripts/setup_test_env.sh' to set up the test environment")
    test_config = None

def run_unit_tests():
    """Run all unit tests using pytest"""
    print("🧪 Running Unit Tests...")

    try:
        # Run unit tests using pytest
        result = subprocess.run([
            sys.executable, '-m', 'pytest', 'tests/unit/', '-v', '--tb=short'
        ], capture_output=True, text=True, cwd=project_root)

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running unit tests: {e}")
        return False

def run_integration_tests():
    """Run all integration tests using pytest"""
    print("🔗 Running Integration Tests...")

    try:
        # Run integration tests using pytest
        result = subprocess.run([
            sys.executable, '-m', 'pytest', 'tests/integration/', '-v', '--tb=short'
        ], capture_output=True, text=True, cwd=project_root)

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running integration tests: {e}")
        return False


def run_config_test():
    """Run the configuration test to verify the new testing framework"""
    print("🧪 Running Configuration Test (New Framework)...")

    try:
        # Run configuration test using pytest
        result = subprocess.run([
            sys.executable, '-m', 'pytest', 'tests/simple_config_test.py', '-v', '--tb=short'
        ], capture_output=True, text=True, cwd=project_root)

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running configuration test: {e}")
        return False

def run_mql5_tests():
    """Run MQL5 tests (if MT5 terminal is available)"""
    print("📊 Running MQL5 Tests...")

    try:
        # Run MQL5 test runner
        result = subprocess.run([
            sys.executable, 'tests/mql5_test_runner.py'
        ], capture_output=True, text=True, cwd=project_root)

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running MQL5 tests: {e}")
        return False

def run_all_tests():
    """Run all tests"""
    print("🚀 Starting Test Suite...")
    print("=" * 50)

    # Run configuration test first to verify new framework
    config_success = run_config_test()

    print("\n" + "=" * 50)

    # Run unit tests
    unit_success = run_unit_tests()

    print("\n" + "=" * 50)

    # Run integration tests
    integration_success = run_integration_tests()

    print("\n" + "=" * 50)

    # Run MQL5 tests (optional)
    mql5_success = run_mql5_tests()

    print("\n" + "=" * 50)
    print("📊 Test Results Summary:")
    print(f"   Configuration Test (New Framework): {'✅ PASSED' if config_success else '❌ FAILED'}")
    print(f"   Unit Tests: {'✅ PASSED' if unit_success else '❌ FAILED'}")
    print(f"   Integration Tests: {'✅ PASSED' if integration_success else '❌ FAILED'}")
    print(f"   MQL5 Tests: {'✅ PASSED' if mql5_success else '⚠️  SKIPPED/FAILED'}")

    # MQL5 tests are optional, so don't fail the overall suite if they're skipped
    overall_success = config_success and unit_success and integration_success
    print(f"\nOverall Result: {'✅ ALL TESTS PASSED' if overall_success else '❌ SOME TESTS FAILED'}")

    return overall_success

def run_specific_test(test_path):
    """Run a specific test file or directory using pytest"""
    print(f"🎯 Running specific test: {test_path}")

    try:
        # Run specific test using pytest
        result = subprocess.run([
            sys.executable, '-m', 'pytest', test_path, '-v', '--tb=short'
        ], capture_output=True, text=True, cwd=project_root)

        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        return result.returncode == 0
    except Exception as e:
        print(f"❌ Error running specific test: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) > 1:
        # Run specific test
        test_path = sys.argv[1]
        success = run_specific_test(test_path)
        sys.exit(0 if success else 1)
    else:
        # Run all tests
        success = run_all_tests()
        sys.exit(0 if success else 1)
