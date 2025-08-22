#!/usr/bin/env python3
"""
CI Test Runner for GitHub Actions
Handles running tests in the CI environment with proper service management
"""

import os
import sys
import time
import subprocess
import signal
import requests
import glob
from pathlib import Path

def discover_test_files():
    """Dynamically discover test files in the tests directory"""
    tests_dir = Path(__file__).parent

    test_files = {
        'unit': [],
        'integration': [],
        'special': []  # For tests that need special handling
    }

    # Discover unit tests
    unit_dir = tests_dir / "unit"
    if unit_dir.exists():
        for test_file in unit_dir.rglob("test_*.py"):
            test_files['unit'].append(str(test_file.relative_to(tests_dir)))

    # Discover integration tests
    integration_dir = tests_dir / "integration"
    if integration_dir.exists():
        for test_file in integration_dir.glob("test_*.py"):
            test_files['integration'].append(str(test_file.relative_to(tests_dir)))

    # Special tests that need custom execution
    test_files['special'] = [
        'integration/test_feature_engineering_integration.py',
        'integration/test_enhanced_ml_prediction_integration.py',
        'integration/test_dashboard_endpoints_integration.py'
    ]

    return test_files

def wait_for_service(url: str, timeout: int = 30) -> bool:
    """Wait for a service to be ready"""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"✅ Service ready: {url}")
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(2)
    print(f"❌ Service not ready after {timeout}s: {url}")
    return False

def start_services():
    """Start Flask services for CI testing"""
    print("🚀 Starting Flask services for CI testing...")

    # Start analytics service
    print("📊 Starting analytics service...")
    analytics_process = subprocess.Popen([
        sys.executable, "analytics/app.py"
    ],
    env=os.environ.copy(),
    cwd=Path(__file__).parent.parent,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
    )

    # Start ML service
    print("🤖 Starting ML service...")
    ml_process = subprocess.Popen([
        sys.executable, "ML_Webserver/ml_prediction_service.py"
    ],
    env=os.environ.copy(),
    cwd=Path(__file__).parent.parent,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
    )

    # Wait for services to start
    print("⏳ Waiting for services to start...")
    time.sleep(10)

    # Check if services are ready
    analytics_ready = wait_for_service("http://127.0.0.1:5001/health")
    ml_ready = wait_for_service("http://127.0.0.1:5003/health")

    if not analytics_ready:
        print("❌ Analytics service failed to start")
        stdout, stderr = analytics_process.communicate()
        print(f"Analytics stdout: {stdout}")
        print(f"Analytics stderr: {stderr}")
        return False, None, None

    if not ml_ready:
        print("❌ ML service failed to start")
        stdout, stderr = ml_process.communicate()
        print(f"ML stdout: {stdout}")
        print(f"ML stderr: {stderr}")
        return False, None, None

    print("✅ All services started successfully")
    return True, analytics_process, ml_process

def stop_services(analytics_process, ml_process):
    """Stop Flask services"""
    print("🛑 Stopping Flask services...")

    if analytics_process:
        analytics_process.terminate()
        try:
            analytics_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            analytics_process.kill()

    if ml_process:
        ml_process.terminate()
        try:
            ml_process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            ml_process.kill()

    print("✅ Services stopped")

def run_tests():
    """Run all tests in CI environment using dynamic test discovery"""
    print("🧪 Running tests in CI environment...")

    # Start services
    success, analytics_process, ml_process = start_services()
    if not success:
        return False

    try:
        # Discover test files dynamically
        test_files = discover_test_files()
        print(f"\n📋 Discovered test files:")
        print(f"   Unit tests: {len(test_files['unit'])}")
        print(f"   Integration tests: {len(test_files['integration'])}")
        print(f"   Special tests: {len(test_files['special'])}")

        test_results = []

        # Run unit tests
        print("\n📋 Running unit tests...")
        if test_files['unit']:
            result = subprocess.run([
                sys.executable, "-m", "pytest", "tests/unit/", "-v", "--tb=short"
            ], capture_output=True, text=True)
            test_results.append(("unit", result.returncode == 0))
            print(result.stdout)
            if result.stderr:
                print("STDERR:", result.stderr)
        else:
            print("⚠️  No unit tests found")
            test_results.append(("unit", True))

        # Run integration tests
        print("\n🔄 Running integration tests...")
        if test_files['integration']:
            result = subprocess.run([
                sys.executable, "-m", "pytest", "tests/integration/", "-v", "--tb=short"
            ], capture_output=True, text=True)
            test_results.append(("integration", result.returncode == 0))
            print(result.stdout)
            if result.stderr:
                print("STDERR:", result.stderr)
        else:
            print("⚠️  No integration tests found")
            test_results.append(("integration", True))

        # Run special tests that need custom execution
        print("\n🔧 Running special tests...")
        for special_test in test_files['special']:
            test_name = Path(special_test).stem
            print(f"   Running {test_name}...")

            if special_test == 'integration/test_feature_engineering_integration.py':
                result = subprocess.run([
                    sys.executable, "-c", """
import sys
sys.path.insert(0, 'ML_Webserver')
sys.path.insert(0, '.')
from tests.integration.test_feature_engineering_integration import run_feature_engineering_integration_tests
success = run_feature_engineering_integration_tests()
exit(0 if success else 1)
                    """
                ], capture_output=True, text=True)
            elif special_test == 'integration/test_enhanced_ml_prediction_integration.py':
                result = subprocess.run([
                    sys.executable, "-c", """
import sys
sys.path.insert(0, 'ML_Webserver')
sys.path.insert(0, '.')
from tests.integration.test_enhanced_ml_prediction_integration import run_enhanced_ml_prediction_integration_tests
success = run_enhanced_ml_prediction_integration_tests()
exit(0 if success else 1)
                    """
                ], capture_output=True, text=True)
            elif special_test == 'integration/test_dashboard_endpoints_integration.py':
                result = subprocess.run([
                    sys.executable, "-c", """
import sys
sys.path.insert(0, 'ML_Webserver')
sys.path.insert(0, '.')
from tests.integration.test_dashboard_endpoints_integration import run_dashboard_endpoints_integration_tests
success = run_dashboard_endpoints_integration_tests()
exit(0 if success else 1)
                    """
                ], capture_output=True, text=True)
            else:
                # Default pytest execution for other special tests
                result = subprocess.run([
                    sys.executable, "-m", "pytest", f"tests/{special_test}", "-v", "--tb=short"
                ], capture_output=True, text=True)

            test_results.append((test_name, result.returncode == 0))
            print(result.stdout)
            if result.stderr:
                print("STDERR:", result.stderr)

        # Print summary
        print("\n" + "="*60)
        print("📊 Test Results Summary:")
        all_passed = True
        for test_name, passed in test_results:
            status = "✅ PASSED" if passed else "❌ FAILED"
            print(f"   {test_name}: {status}")
            if not passed:
                all_passed = False

        print(f"\nOverall Result: {'✅ ALL TESTS PASSED' if all_passed else '❌ SOME TESTS FAILED'}")
        return all_passed

    finally:
        # Always stop services
        stop_services(analytics_process, ml_process)

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
