#!/usr/bin/env python3
"""
Setup script for the trading strategies project
Creates a centralized virtual environment and installs all dependencies
"""

import os
import sys
import subprocess
import venv
from pathlib import Path

def run_command(command, cwd=None, check=True):
    """Run a shell command and return the result"""
    print(f"Running: {command}")
    result = subprocess.run(
        command,
        shell=True,
        cwd=cwd,
        capture_output=True,
        text=True
    )

    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)

    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, command)

    return result

def main():
    """Set up the centralized virtual environment"""
    print("🚀 Setting up centralized virtual environment")
    print("=" * 50)

    # Check if we're in the right directory
    project_root = Path.cwd()
    if not (project_root / "requirements.txt").exists():
        print("❌ requirements.txt not found in current directory")
        print("   Please run this script from the project root")
        return

    venv_path = project_root / "venv"

    # Remove existing venv if it exists
    if venv_path.exists():
        print(f"🗑️  Removing existing virtual environment at {venv_path}")
        import shutil
        shutil.rmtree(venv_path)

    # Create new virtual environment
    print(f"📦 Creating virtual environment at {venv_path}")
    venv.create(venv_path, with_pip=True)

    # Determine the pip path
    if sys.platform == "win32":
        pip_path = venv_path / "Scripts" / "pip"
        python_path = venv_path / "Scripts" / "python"
    else:
        pip_path = venv_path / "bin" / "pip"
        python_path = venv_path / "bin" / "python"

    # Upgrade pip
    print("⬆️  Upgrading pip...")
    run_command(f'"{pip_path}" install --upgrade pip')

    # Install requirements
    print("📥 Installing dependencies...")
    run_command(f'"{pip_path}" install -r requirements.txt')

    # Verify installation
    print("✅ Verifying installation...")
    try:
        result = run_command(f'"{python_path}" -c "import flask, pymysql, numpy, pandas, sklearn; print(\"All key packages imported successfully\")"')
        print("✅ All dependencies installed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"❌ Verification failed: {e}")
        return

    print("\n🎉 Setup complete!")
    print("=" * 50)
    print("To activate the virtual environment:")
    if sys.platform == "win32":
        print(f"   {venv_path}\\Scripts\\activate")
    else:
        print(f"   source {venv_path}/bin/activate")
    print("\nTo start the servers:")
    print("   1. Analytics server: python analytics/app.py")
    print("   2. ML service: python ML_Webserver/start_ml_service.py")
    print("   3. Live retraining: python ML_Webserver/live_retraining_service.py")

if __name__ == "__main__":
    main()
