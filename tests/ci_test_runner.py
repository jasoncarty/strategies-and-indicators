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
from pathlib import Path

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
    """Run all tests in CI environment"""
    print("🧪 Running tests in CI environment...")

    # Start services
    success, analytics_process, ml_process = start_services()
    if not success:
        return False

    try:
        # Run tests
        test_results = []

        # Run unit tests
        print("\n📋 Running unit tests...")
        result = subprocess.run([
            sys.executable, "-m", "pytest", "tests/unit/", "-v", "--tb=short"
        ], capture_output=True, text=True)
        test_results.append(("unit", result.returncode == 0))
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        # Run feature engineering tests
        print("\n🔧 Running feature engineering tests...")
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
        test_results.append(("feature_engineering", result.returncode == 0))
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        # Run database tests
        print("\n🗄️ Running database tests...")
        for test_file in ["test_database_migrations.py", "test_database_scenarios.py", "test_database_verification.py"]:
            result = subprocess.run([
                sys.executable, "-m", "pytest", f"tests/integration/{test_file}", "-v", "--tb=short"
            ], capture_output=True, text=True)
            test_results.append((test_file, result.returncode == 0))
            print(result.stdout)
            if result.stderr:
                print("STDERR:", result.stderr)

        # Run end-to-end tests
        print("\n🔄 Running end-to-end tests...")
        result = subprocess.run([
            sys.executable, "-m", "pytest", "tests/integration/test_end_to_end_workflow.py", "-v", "--tb=short"
        ], capture_output=True, text=True)
        test_results.append(("end_to_end", result.returncode == 0))
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)

        # Run ML retraining tests
        print("\n🤖 Running ML retraining tests...")
        result = subprocess.run([
            sys.executable, "-m", "pytest", "tests/integration/test_ml_retraining_integration.py", "-v", "--tb=short"
        ], capture_output=True, text=True)
        test_results.append(("ml_retraining", result.returncode == 0))
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
