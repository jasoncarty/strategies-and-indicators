#!/usr/bin/env python3
"""
Start all servers script
Activates the centralized virtual environment and starts all services
"""

import os
import sys
import subprocess
import time
import signal
import threading
from pathlib import Path

class ServerManager:
    def __init__(self):
        self.processes = []
        self.running = True

    def start_server(self, name, command, cwd=None):
        """Start a server in a subprocess"""
        print(f"🚀 Starting {name}...")
        print(f"   Command: {command}")
        print(f"   Directory: {cwd or 'current'}")

        try:
            process = subprocess.Popen(
                command,
                shell=True,
                cwd=cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )

            self.processes.append((name, process))

            # Start a thread to monitor the output
            def monitor_output():
                for line in iter(process.stdout.readline, ''):
                    if line:
                        print(f"[{name}] {line.rstrip()}")

            thread = threading.Thread(target=monitor_output, daemon=True)
            thread.start()

            print(f"✅ {name} started (PID: {process.pid})")
            return process

        except Exception as e:
            print(f"❌ Failed to start {name}: {e}")
            return None

    def stop_all(self):
        """Stop all running processes"""
        print("\n🛑 Stopping all servers...")
        self.running = False

        for name, process in self.processes:
            try:
                print(f"   Stopping {name} (PID: {process.pid})...")
                process.terminate()
                process.wait(timeout=5)
                print(f"✅ {name} stopped")
            except subprocess.TimeoutExpired:
                print(f"⚠️  {name} didn't stop gracefully, killing...")
                process.kill()
            except Exception as e:
                print(f"❌ Error stopping {name}: {e}")

        self.processes.clear()

    def signal_handler(self, signum, frame):
        """Handle interrupt signals"""
        print(f"\n📡 Received signal {signum}")
        self.stop_all()
        sys.exit(0)

def main():
    """Start all servers"""
    print("🚀 Starting All Trading Strategy Servers")
    print("=" * 50)

    # Check if we're in the right directory
    project_root = Path.cwd()
    if not (project_root / "requirements.txt").exists():
        print("❌ requirements.txt not found in current directory")
        print("   Please run this script from the project root")
        return

    # Check if virtual environment exists
    venv_path = project_root / "venv"
    if not venv_path.exists():
        print("❌ Virtual environment not found")
        print("   Please run setup_environment.py first")
        return

    # Determine the python path
    if sys.platform == "win32":
        python_path = venv_path / "Scripts" / "python"
    else:
        python_path = venv_path / "bin" / "python"

    if not python_path.exists():
        print(f"❌ Python not found at {python_path}")
        print("   Please run setup_environment.py first")
        return

    # Create server manager
    manager = ServerManager()

    # Set up signal handlers
    signal.signal(signal.SIGINT, manager.signal_handler)
    signal.signal(signal.SIGTERM, manager.signal_handler)

    try:
        # Start analytics server
        analytics_cmd = f'"{python_path}" app.py'
        manager.start_server("Analytics Server", analytics_cmd, cwd=project_root / "analytics")

        # Give analytics server time to start
        time.sleep(2)

        # Start ML prediction service
        ml_cmd = f'"{python_path}" start_ml_service.py'
        manager.start_server("ML Prediction Service", ml_cmd, cwd=project_root / "ML_Webserver")

        # Give ML service time to start
        time.sleep(2)

        # Start live retraining service
        retraining_cmd = f'"{python_path}" live_retraining_service.py'
        manager.start_server("Live Retraining Service", retraining_cmd, cwd=project_root / "ML_Webserver")

        print("\n🎉 All servers started!")
        print("=" * 50)
        print("Services running:")
        print("   📊 Analytics Server: http://localhost:5001")
        print("   🤖 ML Prediction Service: http://localhost:5002")
        print("   🔄 Live Retraining Service: monitoring for updates")
        print("\nPress Ctrl+C to stop all servers")

        # Keep the main thread alive
        while manager.running:
            time.sleep(1)

            # Check if any processes have died
            for name, process in manager.processes[:]:
                if process.poll() is not None:
                    print(f"⚠️  {name} has stopped unexpectedly")
                    manager.processes.remove((name, process))

            if not manager.processes:
                print("❌ All servers have stopped")
                break

    except KeyboardInterrupt:
        print("\n📡 Received interrupt signal")
    finally:
        manager.stop_all()
        print("👋 Goodbye!")

if __name__ == "__main__":
    main()
