#!/usr/bin/env python3
"""
Test script to verify the virtual environment setup
"""

import sys
from pathlib import Path

def test_imports():
    """Test that all required packages can be imported"""
    print("🧪 Testing package imports...")

    packages = [
        'flask',
        'pymysql',
        'numpy',
        'pandas',
        'sklearn',
        'scipy',
        'joblib',
        'matplotlib',
        'seaborn',
        'watchdog',
        'requests',
        'pytest'
    ]

    failed_imports = []

    for package in packages:
        try:
            __import__(package)
            print(f"✅ {package}")
        except ImportError as e:
            print(f"❌ {package}: {e}")
            failed_imports.append(package)

    if failed_imports:
        print(f"\n❌ Failed to import: {', '.join(failed_imports)}")
        return False
    else:
        print("\n✅ All packages imported successfully!")
        return True

def test_virtual_environment():
    """Test that we're running in the virtual environment"""
    print("\n🔍 Checking virtual environment...")

    if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
        print(f"✅ Running in virtual environment: {sys.prefix}")
        return True
    else:
        print("❌ Not running in virtual environment")
        return False

def test_project_structure():
    """Test that the project structure is correct"""
    print("\n📁 Checking project structure...")

    required_files = [
        'requirements.txt',
        'setup_environment.py',
        'start_all_servers.py',
        'activate_and_start.sh'
    ]

    required_dirs = [
        'analytics',
        'ML_Webserver',
        'webserver',
        'tests'
    ]

    missing_files = []
    missing_dirs = []

    for file in required_files:
        if not Path(file).exists():
            missing_files.append(file)
        else:
            print(f"✅ {file}")

    for dir in required_dirs:
        if not Path(dir).exists():
            missing_dirs.append(dir)
        else:
            print(f"✅ {dir}/")

    if missing_files or missing_dirs:
        print(f"\n❌ Missing files: {', '.join(missing_files)}")
        print(f"❌ Missing directories: {', '.join(missing_dirs)}")
        return False
    else:
        print("\n✅ Project structure is correct!")
        return True

def main():
    """Run all tests"""
    print("🚀 Testing Virtual Environment Setup")
    print("=" * 50)

    tests = [
        test_virtual_environment,
        test_project_structure,
        test_imports
    ]

    results = []
    for test in tests:
        results.append(test())

    print("\n" + "=" * 50)
    if all(results):
        print("🎉 All tests passed! Your environment is ready.")
        print("\nTo start the servers:")
        print("   ./activate_and_start.sh")
        print("   or")
        print("   source venv/bin/activate && python start_all_servers.py")
    else:
        print("❌ Some tests failed. Please check the setup.")
        print("\nTo fix issues:")
        print("   python3 setup_environment.py")

if __name__ == "__main__":
    main()
