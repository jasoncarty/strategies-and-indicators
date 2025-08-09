#!/usr/bin/env python3
"""
Test Webserver Manager
Handles isolated webserver instances for testing
"""

import os
import sys
import time
import subprocess
import signal
import threading
from pathlib import Path
from typing import Dict, Optional, List
import requests

class TestWebserverManager:
    """Manages isolated webserver instances for testing"""

    def __init__(self):
        self.processes: Dict[str, subprocess.Popen] = {}
        self.ports: Dict[str, int] = {
            'analytics': 5002,  # Different from production 5001
            'ml_service': 5004  # Different from production 5003
        }
        self.base_urls: Dict[str, str] = {}

    def start_analytics_service(self, test_db_config: dict) -> bool:
        """Start analytics service with test database"""
        try:
            print(f"🚀 Starting analytics service on port {self.ports['analytics']}")

            # Set environment variables for test database
            env = os.environ.copy()
            env['TEST_DATABASE'] = test_db_config['database']
            env['TEST_DB_HOST'] = test_db_config['host']
            env['TEST_DB_PORT'] = str(test_db_config['port'])
            env['TEST_DB_USER'] = test_db_config['user']
            env['TEST_DB_PASSWORD'] = test_db_config['password']
            env['FLASK_ENV'] = 'testing'
            env['FLASK_DEBUG'] = '0'
            env['FLASK_RUN_PORT'] = str(self.ports['analytics'])

            # Start analytics service
            analytics_dir = Path(__file__).parent.parent / 'analytics'
            app_script = analytics_dir / 'app.py'

            if app_script.exists():
                process = subprocess.Popen([
                    sys.executable, str(app_script)
                ],
                env=env,
                cwd=str(analytics_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
                )

                self.processes['analytics'] = process
                self.base_urls['analytics'] = f"http://127.0.0.1:{self.ports['analytics']}"

                # Wait for service to start
                if self._wait_for_service('analytics', '/health'):
                    print(f"✅ Analytics service started on {self.base_urls['analytics']}")
                    return True
                else:
                    print("❌ Analytics service failed to start")
                    # Check if process is still running and get error output
                    if process.poll() is not None:
                        stdout, stderr = process.communicate()
                        print(f"❌ Analytics service process exited with code {process.returncode}")
                        if stderr:
                            print(f"❌ Analytics service error output: {stderr}")
                        if stdout:
                            print(f"📄 Analytics service output: {stdout}")
                    return False
            else:
                print(f"❌ Analytics app script not found: {app_script}")
                return False

        except Exception as e:
            print(f"❌ Failed to start analytics service: {e}")
            return False

    def start_ml_service(self, test_models_dir: str = None) -> bool:
        """Start ML prediction service"""
        try:
            print(f"🚀 Starting ML service on port {self.ports['ml_service']}")

            # Set environment variables
            env = os.environ.copy()
            env['ML_SERVICE_PORT'] = str(self.ports['ml_service'])
            env['FLASK_ENV'] = 'testing'
            env['FLASK_DEBUG'] = '0'

            # Set models directory if provided
            if test_models_dir:
                env['ML_MODELS_DIR'] = test_models_dir
                print(f"📁 Using test models directory: {test_models_dir}")

            # Start ML service
            ml_dir = Path(__file__).parent.parent / 'ML_Webserver'
            ml_script = ml_dir / 'ml_prediction_service.py'

            if ml_script.exists():
                process = subprocess.Popen([
                    sys.executable, str(ml_script)
                ],
                env=env,
                cwd=str(ml_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
                )

                self.processes['ml_service'] = process
                self.base_urls['ml_service'] = f"http://127.0.0.1:{self.ports['ml_service']}"

                # Wait for service to start
                if self._wait_for_service('ml_service', '/health'):
                    print(f"✅ ML service started on {self.base_urls['ml_service']}")
                    return True
                else:
                    print("❌ ML service failed to start")
                    # Check if process is still running and get error output
                    if process.poll() is not None:
                        stdout, stderr = process.communicate()
                        print(f"❌ ML service process exited with code {process.returncode}")
                        if stderr:
                            print(f"❌ ML service error output: {stderr}")
                        if stdout:
                            print(f"📄 ML service output: {stdout}")
                    return False
            else:
                print(f"❌ ML service script not found: {ml_script}")
                return False

        except Exception as e:
            print(f"❌ Failed to start ML service: {e}")
            return False

    def _wait_for_service(self, service_name: str, health_endpoint: str, timeout: int = 30) -> bool:
        """Wait for service to be ready"""
        base_url = self.base_urls[service_name]
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                response = requests.get(f"{base_url}{health_endpoint}", timeout=2)
                if response.status_code == 200:
                    return True
            except requests.exceptions.RequestException:
                pass

            time.sleep(1)

        return False

    def stop_service(self, service_name: str):
        """Stop a specific service"""
        if service_name in self.processes:
            process = self.processes[service_name]
            try:
                process.terminate()
                process.wait(timeout=5)
                print(f"✅ Stopped {service_name}")
            except subprocess.TimeoutExpired:
                process.kill()
                print(f"⚠️ Force killed {service_name}")
            except Exception as e:
                print(f"❌ Error stopping {service_name}: {e}")

            del self.processes[service_name]

    def stop_all_services(self):
        """Stop all running services"""
        print("🛑 Stopping all test services...")

        for service_name in list(self.processes.keys()):
            self.stop_service(service_name)

        self.processes.clear()
        self.base_urls.clear()

    def get_service_url(self, service_name: str) -> Optional[str]:
        """Get base URL for a service"""
        return self.base_urls.get(service_name)

    def get_all_urls(self) -> Dict[str, str]:
        """Get all service URLs"""
        return self.base_urls.copy()

    def __enter__(self):
        """Context manager entry"""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.stop_all_services()


def create_test_webserver_manager() -> TestWebserverManager:
    """Factory function to create test webserver manager"""
    return TestWebserverManager()
