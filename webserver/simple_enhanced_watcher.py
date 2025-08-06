#!/usr/bin/env python3
"""
Simple Enhanced File Watcher for MT5 Strategy Tester
This version focuses on reliability and prevents restart loops.
"""

import time
import json
import os
import sys
import signal
import subprocess
import requests
import argparse
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
MT5_WATCH_PATH = '/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files'
SERVER_URL = "http://127.0.0.1:5000/api/test"
SERVER_SCRIPT = "app.py"

# Files that should trigger server restart
WATCHED_FILES = ['app.py']
WATCHED_EXTENSIONS = ['.html']
WATCHED_DIRS = ['templates']

# Files to ignore (prevents restart loops)
IGNORED_FILES = [
    'enhanced_file_watcher.py',
    'simple_enhanced_watcher.py',
    'file_watcher.py',
    'start_server.py',
    'start_dev.sh',
    'start_watcher.sh',
    '__pycache__',
    '.pyc',
    '.pyo',
    '.pyd',
    '.git',
    '.DS_Store',
    'venv',
    'instance',
    '.db',
    '.sqlite',
    '.log'
]

class MT5FileHandler(FileSystemEventHandler):
    def _extract_symbol_from_path(self, file_path: Path) -> str:
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

    """Handles MT5 JSON files."""

    def __init__(self):
        self.last_processed = set()

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            file_path = event.src_path
            if file_path not in self.last_processed:
                print(f"✅ New MT5 result file detected: {os.path.basename(file_path)}")
                self.last_processed.add(file_path)
                time.sleep(1)  # Wait for file to be fully written
                self.process_file(file_path)
                time.sleep(5)
                self.last_processed.discard(file_path)

    def process_file(self, file_path):
        """Process MT5 JSON file."""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)

            print(f"   - Read {len(data.get('trades', []))} trades from file.")

            response = requests.post(SERVER_URL, json=data, timeout=30)

            if response.status_code == 201:
                test_id = response.json().get('test_id', 'N/A')
                print(f"   - ✔️ Successfully sent to server. New Test ID: {test_id}")
            else:
                print(f"   - ❌ ERROR sending to server. Status: {response.status_code}")
                print(f"   - Server Response: {response.text}")

        except Exception as e:
            print(f"   - ❌ Error processing file: {e}")
        finally:
            try:
                os.remove(file_path)
                print(f"   - 🗑️ Deleted processed file: {os.path.basename(file_path)}")
            except OSError as e:
                print(f"   - ❌ ERROR deleting file: {e}")


class SimpleServerFileHandler(FileSystemEventHandler):
    """Simple server file handler with restart protection."""

    def __init__(self, server_manager):
        self.server_manager = server_manager
        self.last_restart_time = 0
        self.restart_cooldown = 10  # Increased cooldown
        self.startup_time = time.time()
        self.startup_grace_period = 15  # Longer grace period

    def on_modified(self, event):
        if event.is_directory:
            return

        # Don't restart during startup grace period
        if time.time() - self.startup_time < self.startup_grace_period:
            return

        file_path = event.src_path
        file_name = os.path.basename(file_path)

        # Check if we should ignore this file
        for ignored in IGNORED_FILES:
            if ignored in file_path:
                return

        # Check if this is a file we should watch
        should_watch = False

        if file_name in WATCHED_FILES:
            should_watch = True
        elif any(file_path.endswith(ext) for ext in WATCHED_EXTENSIONS):
            should_watch = True
        elif any(dir_name in file_path for dir_name in WATCHED_DIRS):
            should_watch = True

        if should_watch:
            current_time = time.time()
            if current_time - self.last_restart_time > self.restart_cooldown:
                print(f"🔄 Server file changed: {file_name}")
                self.last_restart_time = current_time
                self.server_manager.restart_server()


class SimpleServerManager:
    """Simple server manager."""

    def __init__(self):
        self.server_process = None
        self.restart_count = 0
        self.max_restarts = 3
        self.last_health_check: float = 0.0  # Initialize the health check timer

    def start_server(self):
        """Start the Flask server."""
        if self.server_process and self.server_process.poll() is None:
            print("⚠️  Server is already running")
            return

        try:
            print("🚀 Starting Flask server...")
            self.server_process = subprocess.Popen(
                [sys.executable, SERVER_SCRIPT]
            )

            # Wait a bit longer and check if server started successfully
            time.sleep(5)

            if self.server_process.poll() is None:
                print("✅ Server started successfully")
                self.restart_count = 0
            else:
                # Server failed to start, get error output
                stdout, stderr = self.server_process.communicate()
                print("❌ Server failed to start")
                print(f"STDOUT: {stdout}")
                print(f"STDERR: {stderr}")
                self.restart_count += 1

        except Exception as e:
            print(f"❌ Error starting server: {e}")
            self.restart_count += 1

    def stop_server(self):
        """Stop the Flask server."""
        if self.server_process and self.server_process.poll() is None:
            print("🛑 Stopping server...")
            try:
                self.server_process.terminate()
                self.server_process.wait(timeout=5)
                print("✅ Server stopped")
            except subprocess.TimeoutExpired:
                print("⚠️  Server didn't stop gracefully, forcing...")
                self.server_process.kill()
            except Exception as e:
                print(f"❌ Error stopping server: {e}")

    def restart_server(self):
        """Restart the Flask server."""
        if self.restart_count >= self.max_restarts:
            print(f"❌ Maximum restart attempts ({self.max_restarts}) reached.")
            print("   - Please restart manually or check for errors")
            return

        self.restart_count += 1
        print(f"🔄 Restarting server (attempt {self.restart_count}/{self.max_restarts})...")

        self.stop_server()
        time.sleep(3)  # Longer delay
        self.start_server()

    def is_server_running(self):
        """Check if server is running."""
        if not self.server_process:
            return False
        return self.server_process.poll() is None

    def check_server_health(self):
        """Check if server is responding to requests."""
        try:
            response = requests.get("http://127.0.0.1:5000/api", timeout=5)
            return response.status_code == 200
        except:
            return False

    def cleanup(self):
        """Clean up resources."""
        self.stop_server()


def signal_handler(signum, frame):
    """Handle shutdown signals."""
    print("\n🛑 Shutdown signal received. Cleaning up...")
    global server_manager
    if server_manager is not None:
        server_manager.cleanup()
    sys.exit(0)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Simple Enhanced File Watcher')
    parser.add_argument('--server-only', action='store_true', help='Only watch server files')
    parser.add_argument('--mt5-only', action='store_true', help='Only watch MT5 files')
    parser.add_argument('--both', action='store_true', help='Watch both (default)')

    args = parser.parse_args()

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("--- Simple Enhanced MT5 Strategy File Watcher ---")

    # Determine what to watch
    watch_mt5 = not args.server_only
    watch_server = not args.mt5_only

    if args.server_only:
        print("👀 Server-only mode")
    elif args.mt5_only:
        print("👀 MT5-only mode")
    else:
        print("👀 Full mode: Watching both MT5 and server files")

    # Initialize server manager
    global server_manager
    server_manager = None
    if watch_server:
        server_manager = SimpleServerManager()
        server_manager.start_server()

    # Set up observers
    observers = []

    # MT5 file watcher
    if watch_mt5:
        if not os.path.exists(MT5_WATCH_PATH):
            print(f"❌ ERROR: MT5 path '{MT5_WATCH_PATH}' does not exist.")
            return

        print(f"👀 Watching MT5 files in: {MT5_WATCH_PATH}")
        mt5_handler = MT5FileHandler()
        mt5_observer = Observer()
        mt5_observer.schedule(mt5_handler, MT5_WATCH_PATH, recursive=False)
        mt5_observer.start()
        observers.append(mt5_observer)

    # Server file watcher
    if watch_server:
        print(f"👀 Watching server files in: {os.getcwd()}")
        server_handler = SimpleServerFileHandler(server_manager)
        server_observer = Observer()
        server_observer.schedule(server_handler, '.', recursive=True)
        server_observer.start()
        observers.append(server_observer)

    print("🚀 File watcher started. Press Ctrl+C to stop.")

    # Give server time to start up before health checks
    if watch_server and server_manager:
        print("⏳ Waiting for server to fully start up...")
        time.sleep(10)

    try:
        while True:
            time.sleep(1)
            # Check if server is still running
            if watch_server and server_manager:
                if not server_manager.is_server_running():
                    print("⚠️  Server stopped unexpectedly. Restarting...")
                    server_manager.start_server()
                else:
                    # Only do health check every 30 seconds instead of every second
                    current_time = time.time()
                    if current_time - server_manager.last_health_check > 30:  # Check every 30 seconds
                        server_manager.last_health_check = current_time
                        if not server_manager.check_server_health():
                            print("⚠️  Server not responding. Restarting...")
                            server_manager.restart_server()

                # If we've had too many failed restarts, stop trying
                if server_manager.restart_count >= server_manager.max_restarts:
                    print(f"❌ Maximum restart attempts ({server_manager.max_restarts}) reached.")
                    print("   - Server is consistently failing to start.")
                    print("   - Please check for errors and restart manually.")
                    break

    except KeyboardInterrupt:
        print("\n🛑 Watcher stopped by user.")
    finally:
        # Clean up
        for observer in observers:
            observer.stop()
            observer.join()

        if server_manager:
            server_manager.cleanup()

        print("✅ Cleanup complete.")


if __name__ == "__main__":
    main()
