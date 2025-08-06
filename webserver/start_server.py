#!/usr/bin/env python3
"""
MT5 Strategy Tester Web Server Startup Script
"""

import os
import sys
import subprocess
import time
import threading
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

def check_python_version():
    """Check if Python version is compatible"""
    if sys.version_info < (3, 7):
        print("Error: Python 3.7 or higher is required")
        sys.exit(1)

def install_requirements():
    """Install required packages"""
    print("Installing required packages...")
    try:
        # Use the python executable from the venv
        venv_python = os.path.join("venv", "bin", "python")
        if os.name == 'nt': # Windows
             venv_python = os.path.join("venv", "Scripts", "python.exe")

        subprocess.check_call([venv_python, "-m", "pip", "install", "-r", "requirements.txt"])
        print("✓ Packages installed successfully")
    except subprocess.CalledProcessError:
        print("✗ Failed to install packages")
        sys.exit(1)

class SimpleServerFileHandler(FileSystemEventHandler):
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

    """Simple file handler that just prints when server files change"""

    def __init__(self):
        self.last_restart_time = 0
        self.restart_cooldown = 5  # seconds between restarts

    def on_modified(self, event):
        if event.is_directory:
            return

        file_path = event.src_path
        file_name = os.path.basename(file_path)

        # Only watch specific files that should trigger restarts
        watched_files = ['app.py']
        watched_extensions = ['.html']
        watched_dirs = ['templates']

        # Check if this is a file we should watch
        should_watch = False

        if file_name in watched_files:
            should_watch = True
        elif any(file_path.endswith(ext) for ext in watched_extensions):
            should_watch = True
        elif any(dir_name in file_path for dir_name in watched_dirs):
            should_watch = True

        # Ignore files that would cause loops
        ignore_files = ['enhanced_file_watcher.py', 'file_watcher.py', 'start_server.py']
        if file_name in ignore_files:
            should_watch = False

        if should_watch:
            current_time = time.time()
            if current_time - self.last_restart_time > self.restart_cooldown:
                print(f"🔄 Server file changed: {file_name}")
                print("   - Please restart the server manually (Ctrl+C, then run again)")
                print("   - Or use the enhanced_file_watcher.py for automatic restarts")
                self.last_restart_time = current_time

def start_file_watcher():
    """Start a simple file watcher that just notifies of changes"""
    print("👀 Starting simple file watcher (notifications only)...")

    event_handler = SimpleServerFileHandler()
    observer = Observer()
    observer.schedule(event_handler, '.', recursive=True)
    observer.start()

    return observer

def start_services():
    """Start the Flask web server and the file watcher"""
    print("--- Starting All Services ---")

    # --- 1. Initialize Database and Get App ---
    from app import app, db
    with app.app_context():
        print("Initializing database...")
        db.create_all()
        print("✓ Database initialized.")

    # --- 2. Start Simple File Watcher ---
    file_observer = start_file_watcher()

    # --- 3. Start MT5 File Watcher in Background ---
    venv_python = os.path.join("venv", "bin", "python")
    if os.name == 'nt': # Windows
        venv_python = os.path.join("venv", "Scripts", "python.exe")

    try:
        print("🚀 Launching MT5 file watcher in the background...")
        mt5_watcher_process = subprocess.Popen([venv_python, "file_watcher.py"])
        print("✓ MT5 file watcher is running.")
    except Exception as e:
        print(f"❌ Failed to start MT5 file watcher: {e}")
        mt5_watcher_process = None

    # --- 4. Start Web Server in the Foreground ---
    try:
        print("🚀 Launching web server...")
        print("   - Server will be available at: http://127.0.0.1:5001")
        print("   - Press Ctrl+C to stop ALL services.")
        print("   - For automatic server restarts, use: python enhanced_file_watcher.py --server-only")
        print("-" * 50)
        app.run(debug=False, host='0.0.0.0', port=5001) # debug=False for cleaner logs

    finally:
        # This block will run when you press Ctrl+C
        print("\n--- Stopping All Services ---")

        # Stop file observer
        print("🛑 Stopping file observer...")
        file_observer.stop()
        file_observer.join()
        print("✓ File observer stopped.")

        # Stop MT5 watcher
        if mt5_watcher_process:
            print("🛑 Stopping MT5 file watcher...")
            mt5_watcher_process.terminate()
            mt5_watcher_process.wait()
            print("✓ MT5 file watcher stopped.")

        print("🛑 Web server stopped.")

def main():
    """Main function"""
    print("MT5 Strategy Tester Web Server & Watcher")
    print("=" * 40)

    check_python_version()

    # Create and activate virtual environment if it doesn't exist
    if not os.path.exists("venv"):
        print("Creating virtual environment...")
        subprocess.check_call([sys.executable, "-m", "venv", "venv"])

    install_requirements()

    # Start all services
    start_services()

if __name__ == "__main__":
    main()
