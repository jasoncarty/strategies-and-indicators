#!/usr/bin/env python3
"""
MT5 Strategy Tester Web Server Startup Script
"""

import os
import sys
import subprocess
import time

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

def start_services():
    """Start the Flask web server and the file watcher"""
    print("--- Starting All Services ---")

    # --- 1. Initialize Database and Get App ---
    from app import app, db
    with app.app_context():
        print("Initializing database...")
        db.create_all()
        print("✓ Database initialized.")

    # --- 2. Start File Watcher as a Background Process ---
    venv_python = os.path.join("venv", "bin", "python")
    if os.name == 'nt': # Windows
        venv_python = os.path.join("venv", "Scripts", "python.exe")

    try:
        print("🚀 Launching file watcher in the background...")
        watcher_process = subprocess.Popen([venv_python, "file_watcher.py"])
        print("✓ File watcher is running.")
    except Exception as e:
        print(f"❌ Failed to start file watcher: {e}")
        return

    # --- 3. Start Web Server in the Foreground ---
    try:
        print("🚀 Launching web server...")
        print("   - Server will be available at: http://127.0.0.1:5000")
        print("   - Press Ctrl+C to stop ALL services.")
        print("-" * 50)
        app.run(debug=False, host='0.0.0.0', port=5000) # debug=False for cleaner logs

    finally:
        # This block will run when you press Ctrl+C
        print("\n--- Stopping All Services ---")
        print("🛑 Stopping file watcher...")
        watcher_process.terminate() # Terminate the background process
        watcher_process.wait()
        print("✓ File watcher stopped.")
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
