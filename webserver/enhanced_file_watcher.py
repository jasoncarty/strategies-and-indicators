#!/usr/bin/env python3
"""
Enhanced File Watcher for MT5 Strategy Tester Web Server

This script provides two main functionalities:
1. Watches for new JSON files from MT5 and sends them to the web server
2. Watches for changes in Python and HTML files and automatically restarts the server

Usage:
    python enhanced_file_watcher.py [--server-only] [--mt5-only] [--both]

Options:
    --server-only: Only watch server files and restart on changes
    --mt5-only: Only watch MT5 JSON files
    --both: Watch both (default)
"""

import time
import json
import os
import sys
import signal
import subprocess
import requests
import argparse
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from typing import Optional, List

# --- Configuration ---
# MT5 Files directory
MT5_WATCH_PATH = '/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files'

# Web server files to watch
SERVER_WATCH_PATH = os.path.dirname(os.path.abspath(__file__))  # Current directory
SERVER_URL = "http://127.0.0.1:5000/api/test"

# Files to watch for server restarts
SERVER_FILES = [
    'app.py'
    # Removed 'file_watcher.py' and 'enhanced_file_watcher.py' to prevent restart loops
]

# Directories to watch for server restarts
SERVER_DIRS = [
    'templates'
    # Removed 'static' since it doesn't exist yet
]

# File extensions to watch for server restarts
SERVER_EXTENSIONS = ['.py', '.html', '.css', '.js']

# Files to ignore (to prevent restart loops)
IGNORE_FILES = [
    'enhanced_file_watcher.py',
    'file_watcher.py',
    'start_server.py',
    '__pycache__',
    '.pyc',
    '.pyo',
    '.pyd',
    '.git',
    '.DS_Store'
]

# Server restart configuration
RESTART_DELAY = 2  # seconds to wait before restarting
MAX_RESTART_ATTEMPTS = 3
# --- End Configuration ---


class MT5FileHandler(FileSystemEventHandler):
    """Handles events for new .json files from MT5."""

    def __init__(self):
        self.last_processed = set()

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            file_path = event.src_path
            if file_path not in self.last_processed:
                print(f"✅ New MT5 result file detected: {os.path.basename(file_path)}")
                self.last_processed.add(file_path)
                # Wait a bit to ensure the file is fully written by MT5
                time.sleep(1)
                self.process_file(file_path)
                # Remove from processed set after a delay to allow for potential re-processing
                time.sleep(5)
                self.last_processed.discard(file_path)

    def process_file(self, file_path):
        """Reads a JSON file, sends its content to the web server, and deletes it."""
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

        except json.JSONDecodeError:
            print(f"   - ❌ ERROR: Could not decode JSON from file: {os.path.basename(file_path)}")
        except requests.exceptions.RequestException as e:
            print(f"   - ❌ ERROR: Could not connect to the web server: {e}")
        except Exception as e:
            print(f"   - ❌ An unexpected error occurred: {e}")
        finally:
            # Delete the file after processing to avoid duplicates
            try:
                os.remove(file_path)
                print(f"   - 🗑️ Deleted processed file: {os.path.basename(file_path)}")
            except OSError as e:
                print(f"   - ❌ ERROR deleting file: {e}")


class ServerFileHandler(FileSystemEventHandler):
    """Handles events for server file changes and restarts the server."""

    def __init__(self, server_manager):
        self.server_manager = server_manager
        self.last_restart_time = 0
        self.restart_cooldown = 5  # seconds between restarts
        self.startup_time = time.time()  # Track when we started
        self.startup_grace_period = 10  # seconds grace period after startup

    def on_modified(self, event):
        if event.is_directory:
            return

        # Don't restart during startup grace period
        if time.time() - self.startup_time < self.startup_grace_period:
            return

        file_path = event.src_path
        file_name = os.path.basename(file_path)

        # Check if this is a file we should watch
        if self.should_watch_file(file_path):
            current_time = time.time()
            if current_time - self.last_restart_time > self.restart_cooldown:
                print(f"🔄 Server file changed: {file_name}")
                print(f"   - File path: {file_path}")
                self.last_restart_time = current_time
                self.server_manager.restart_server()
        else:
            # Debug: log ignored files (but only occasionally to avoid spam)
            if hasattr(self, 'debug_counter'):
                self.debug_counter += 1
            else:
                self.debug_counter = 0

            if self.debug_counter % 10 == 0:  # Only log every 10th ignored file
                print(f"👁️  Ignored file change: {file_name}")

    def should_watch_file(self, file_path):
        """Check if a file should trigger a server restart."""
        file_name = os.path.basename(file_path)
        file_ext = os.path.splitext(file_path)[1].lower()

        # Check ignore list first
        for ignore_item in IGNORE_FILES:
            if ignore_item in file_path or file_name == ignore_item:
                return False

        # Additional ignore patterns
        ignore_patterns = [
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
            '.log',
            'enhanced_file_watcher.py',
            'file_watcher.py',
            'start_server.py',
            'start_dev.sh',
            'start_watcher.sh'
        ]

        for pattern in ignore_patterns:
            if pattern in file_path:
                return False

        # Check specific files
        if file_name in SERVER_FILES:
            return True

        # Check file extensions
        if file_ext in SERVER_EXTENSIONS:
            return True

        # Check if file is in watched directories
        for dir_name in SERVER_DIRS:
            if dir_name in file_path:
                return True

        return False


class ServerManager:
    """Manages the Flask server process."""

    def __init__(self):
        self.server_process: Optional[subprocess.Popen] = None
        self.restart_count = 0
        self.server_script = os.path.join(SERVER_WATCH_PATH, 'app.py')

    def start_server(self):
        """Start the Flask server."""
        if self.server_process and self.server_process.poll() is None:
            print("⚠️  Server is already running")
            return

        try:
            print("🚀 Starting Flask server...")
            self.server_process = subprocess.Popen(
                [sys.executable, self.server_script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            # Wait a moment to see if the server starts successfully
            time.sleep(3)

            if self.server_process.poll() is None:
                print("✅ Server started successfully")
                self.restart_count = 0
            else:
                print("❌ Server failed to start")
                self.print_server_output()

        except Exception as e:
            print(f"❌ Error starting server: {e}")

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
        if self.restart_count >= MAX_RESTART_ATTEMPTS:
            print(f"❌ Maximum restart attempts ({MAX_RESTART_ATTEMPTS}) reached. Manual intervention required.")
            return

        self.restart_count += 1
        print(f"🔄 Restarting server (attempt {self.restart_count}/{MAX_RESTART_ATTEMPTS})...")

        # Check if server is actually running before restarting
        if self.server_process and self.server_process.poll() is None:
            print("   - Server is running, stopping it first...")
            self.stop_server()
            time.sleep(RESTART_DELAY)
        else:
            print("   - Server is not running, starting fresh...")

        self.start_server()

        # Reset restart count if server starts successfully
        if self.server_process and self.server_process.poll() is None:
            print("   - Server restarted successfully, resetting restart count")
            self.restart_count = 0

    def print_server_output(self):
        """Print server output for debugging."""
        if self.server_process:
            try:
                stdout, stderr = self.server_process.communicate(timeout=1)
                if stdout:
                    print("Server stdout:", stdout)
                if stderr:
                    print("Server stderr:", stderr)
            except subprocess.TimeoutExpired:
                pass

    def is_server_running(self):
        """Check if the server is running."""
        if not self.server_process:
            return False
        return self.server_process.poll() is None

    def cleanup(self):
        """Clean up resources."""
        self.stop_server()


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    print("\n🛑 Shutdown signal received. Cleaning up...")
    global server_manager
    if server_manager is not None:
        server_manager.cleanup()
    sys.exit(0)


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Enhanced File Watcher for MT5 Strategy Tester')
    parser.add_argument('--server-only', action='store_true', help='Only watch server files and restart on changes')
    parser.add_argument('--mt5-only', action='store_true', help='Only watch MT5 JSON files')
    parser.add_argument('--both', action='store_true', help='Watch both MT5 and server files (default)')

    args = parser.parse_args()

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("--- Enhanced MT5 Strategy Result File Watcher ---")

    # Determine what to watch
    watch_mt5 = not args.server_only
    watch_server = not args.mt5_only

    if args.server_only:
        print("👀 Server-only mode: Watching server files for changes")
    elif args.mt5_only:
        print("👀 MT5-only mode: Watching MT5 JSON files")
    else:
        print("👀 Full mode: Watching both MT5 and server files")

    # Initialize server manager if needed
    global server_manager
    server_manager = None
    if watch_server:
        server_manager = ServerManager()
        server_manager.start_server()

    # Set up observers
    observers = []

    # MT5 file watcher
    if watch_mt5:
        if not os.path.exists(MT5_WATCH_PATH):
            print(f"❌ ERROR: The MT5 path '{MT5_WATCH_PATH}' does not exist.")
            print("   - Please verify the path from 'Open Data Folder' in MT5.")
            return

        print(f"👀 Watching for new .json files in: {MT5_WATCH_PATH}")
        mt5_handler = MT5FileHandler()
        mt5_observer = Observer()
        mt5_observer.schedule(mt5_handler, MT5_WATCH_PATH, recursive=False)
        mt5_observer.start()
        observers.append(mt5_observer)

    # Server file watcher
    if watch_server:
        print(f"👀 Watching server files in: {SERVER_WATCH_PATH}")
        server_handler = ServerFileHandler(server_manager)
        server_observer = Observer()
        server_observer.schedule(server_handler, SERVER_WATCH_PATH, recursive=True)
        server_observer.start()
        observers.append(server_observer)

    print("🚀 File watcher started. Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)
            # Check if server is still running (if we're managing it)
            if watch_server and server_manager and not server_manager.is_server_running():
                print("⚠️  Server stopped unexpectedly. Restarting...")
                server_manager.start_server()

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
