#!/usr/bin/env python3
"""
Test Database Manager
Handles creation, migration, and cleanup of test databases
"""

import os
import sys
import tempfile
import subprocess
import time
import pymysql
from pathlib import Path
from typing import Optional

# Add the analytics directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent / 'analytics'))

from database.config import get_database_config

def load_test_env():
    """Load test environment variables from .env.test file"""
    env_file = Path(__file__).parent.parent / '.env.test'
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
        print(f"✅ Loaded test environment from {env_file}")
    else:
        print(f"⚠️ Test environment file not found: {env_file}")

# Load test environment variables
load_test_env()

class TestDatabaseManager:
    """Manages test database lifecycle"""

    def __init__(self, test_db_name: str = "test_breakout_analytics"):
        self.test_db_name = test_db_name
        self.original_config = None
        self.test_config = None
        self.mysql_connection = None
        self.test_session_id = None

    def setup_test_database(self) -> bool:
        """Create test database and run migrations"""
        try:
            print(f"🔧 Setting up test database: {self.test_db_name}")

            # Get original database config
            self.original_config = get_database_config()

            # Check if we have test database credentials
            test_db_user = os.getenv('TEST_DB_USER')
            test_db_password = os.getenv('TEST_DB_PASSWORD')
            test_db_host = os.getenv('TEST_DB_HOST', self.original_config['host'])
            test_db_port = int(os.getenv('TEST_DB_PORT', self.original_config['port']))

            if test_db_user and test_db_password:
                # We have test database credentials - create a real test database
                print("🔧 Using test database user - creating real test database")

                # Generate unique test session ID for this test run
                import time
                self.test_session_id = int(time.time())
                print(f"📋 Test session ID: {self.test_session_id}")

                # Connect to MySQL server (without specifying database)
                self.mysql_connection = pymysql.connect(
                    host=test_db_host,
                    port=test_db_port,
                    user=test_db_user,
                    password=test_db_password,
                    charset='utf8mb4'
                )

                # Drop existing test database if it exists
                with self.mysql_connection.cursor() as cursor:
                    cursor.execute(f"DROP DATABASE IF EXISTS `{self.test_db_name}`")
                    print(f"🗑️ Dropped existing test database: {self.test_db_name}")

                # Create fresh test database
                with self.mysql_connection.cursor() as cursor:
                    cursor.execute(f"CREATE DATABASE `{self.test_db_name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci")
                    print(f"✅ Created fresh test database: {self.test_db_name}")

                # Create test database config
                self.test_config = {
                    'host': test_db_host,
                    'port': test_db_port,
                    'user': test_db_user,
                    'password': test_db_password,
                    'database': self.test_db_name,  # Use the consistent test database name
                    'charset': 'utf8mb4'
                }

            else:
                # Fallback to using existing database with test tables
                print("⚠️ No test database credentials - using existing database with test tables")

                import time
                self.test_session_id = int(time.time())
                print(f"📋 Test session ID: {self.test_session_id}")

                # Create test database config using existing database
                self.test_config = {
                    'host': self.original_config['host'],
                    'port': self.original_config['port'],
                    'user': self.original_config['user'],
                    'password': self.original_config['password'],
                    'database': self.original_config['database'],  # Use existing database
                    'charset': 'utf8mb4'
                }

                # Connect to existing database
                self.mysql_connection = pymysql.connect(
                    host=self.test_config['host'],
                    port=self.test_config['port'],
                    user=self.test_config['user'],
                    password=self.test_config['password'],
                    database=self.test_config['database'],
                    charset='utf8mb4'
                )

                print(f"✅ Using existing database: {self.test_config['database']}")

            print(f"📋 Test session ID: {self.test_db_name}")

            # Run migrations on test database
            self._run_migrations()

            return True

        except Exception as e:
            print(f"❌ Failed to setup test database: {e}")
            return False

    def _run_migrations(self):
        """Run database migrations on test database"""
        try:
            print("📦 Running migrations on test database...")

            # Set environment variable for test database
            os.environ['TEST_DATABASE'] = self.test_db_name

            # Check if we're using a real test database or existing database
            if self.test_config and self.test_config.get('database') != self.original_config.get('database'):
                # We have a real test database - run actual migrations
                print("🔄 Running actual migrations on test database")

                # Run migration script
                migrations_dir = Path(__file__).parent.parent / 'analytics' / 'database'
                run_migrations_script = migrations_dir / 'run_migrations.py'

                if run_migrations_script.exists():
                    result = subprocess.run([
                        sys.executable, str(run_migrations_script)
                    ], capture_output=True, text=True, cwd=str(migrations_dir.parent))

                    if result.returncode == 0:
                        print("✅ Migrations completed successfully")
                    else:
                        print(f"⚠️ Migration output: {result.stdout}")
                        print(f"⚠️ Migration errors: {result.stderr}")
                        # Fall back to creating basic tables
                        self._create_basic_tables()
                else:
                    print("⚠️ Migration script not found, creating basic tables...")
                    self._create_basic_tables()
            else:
                # Using existing database - create basic tables directly
                print("🔄 Using direct table creation for existing database")
                self._create_basic_tables()

        except Exception as e:
            print(f"❌ Failed to run migrations: {e}")
            self._create_basic_tables()

    def _create_basic_tables(self):
        """Create basic tables if migration script is not available"""
        try:
            # Connect to test database
            test_db = pymysql.connect(**self.test_config)

            # Determine if we're using test tables (existing database) or regular tables (separate database)
            using_test_tables = self.test_config.get('database') == self.original_config.get('database')
            table_prefix = "test_" if using_test_tables else ""

            with test_db.cursor() as cursor:
                # Create basic tables structure
                cursor.execute(f"""
                    CREATE TABLE IF NOT EXISTS {table_prefix}trades (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        trade_id VARCHAR(50) UNIQUE,
                        strategy VARCHAR(100),
                        symbol VARCHAR(20),
                        timeframe VARCHAR(10),
                        direction ENUM('buy', 'sell'),
                        entry_price DECIMAL(10,5),
                        stop_loss DECIMAL(10,5),
                        take_profit DECIMAL(10,5),
                        lot_size DECIMAL(10,2),
                        timestamp DATETIME,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                cursor.execute(f"""
                    CREATE TABLE IF NOT EXISTS {table_prefix}market_conditions (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        trade_id VARCHAR(50),
                        symbol VARCHAR(20),
                        timeframe VARCHAR(10),
                        rsi DECIMAL(10,4),
                        stoch_main DECIMAL(10,4),
                        stoch_signal DECIMAL(10,4),
                        macd_main DECIMAL(10,4),
                        macd_signal DECIMAL(10,4),
                        bb_upper DECIMAL(10,4),
                        bb_lower DECIMAL(10,4),
                        cci DECIMAL(10,4),
                        momentum DECIMAL(10,4),
                        volume_ratio DECIMAL(10,4),
                        price_change DECIMAL(10,4),
                        volatility DECIMAL(10,4),
                        spread DECIMAL(10,4),
                        session_hour INT,
                        day_of_week INT,
                        month INT,
                        timestamp DATETIME,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

                cursor.execute(f"""
                    CREATE TABLE IF NOT EXISTS {table_prefix}ml_predictions (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        trade_id VARCHAR(50),
                        model_name VARCHAR(100),
                        model_type VARCHAR(20),
                        prediction_probability DECIMAL(10,4),
                        confidence_score DECIMAL(10,4),
                        features_json TEXT,
                        timestamp DATETIME,
                        symbol VARCHAR(20),
                        timeframe VARCHAR(10),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)

            test_db.commit()
            test_db.close()
            print(f"✅ Created basic tables in {'test database' if not using_test_tables else 'existing database with test prefix'}")

        except Exception as e:
            print(f"❌ Failed to create basic tables: {e}")

    def get_test_config(self) -> dict:
        """Get test database configuration"""
        return self.test_config.copy() if self.test_config else None

    def cleanup_test_database(self, destroy_database: bool = True):
        """Clean up test database and optionally destroy it"""
        try:
            if self.mysql_connection:
                # Check if we're using a separate test database or existing database
                if self.test_config and self.test_config.get('database') != self.original_config.get('database'):
                    if destroy_database:
                        # We have a separate test database, drop it
                        try:
                            with self.mysql_connection.cursor() as cursor:
                                cursor.execute(f"DROP DATABASE IF EXISTS `{self.test_db_name}`")
                                print(f"🗑️ Dropped test database: {self.test_db_name}")
                        except Exception as drop_error:
                            print(f"⚠️ Could not drop test database: {drop_error}")
                    else:
                        print(f"ℹ️ Keeping test database: {self.test_db_name} (destroy_database=False)")
                else:
                    # We're using existing database, clean up test tables
                    try:
                        with self.mysql_connection.cursor() as cursor:
                            # Drop test tables if they exist
                            test_tables = ['test_trades', 'test_market_conditions', 'test_ml_predictions']
                            for table in test_tables:
                                cursor.execute(f"DROP TABLE IF EXISTS `{table}`")
                            print(f"🗑️ Cleaned up test tables in existing database")
                    except Exception as cleanup_error:
                        print(f"⚠️ Could not cleanup test tables: {cleanup_error}")

                self.mysql_connection.close()
                self.mysql_connection = None

            # Clear environment variable
            if 'TEST_DATABASE' in os.environ:
                del os.environ['TEST_DATABASE']

        except Exception as e:
            print(f"❌ Failed to cleanup test database: {e}")

    def __enter__(self):
        """Context manager entry"""
        if not self.setup_test_database():
            raise Exception("Failed to setup test database")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        # Don't automatically destroy the database - let the caller decide
        self.cleanup_test_database(destroy_database=False)


def create_test_database_manager(test_db_name: str = "test_breakout_analytics") -> TestDatabaseManager:
    """Factory function to create test database manager"""
    return TestDatabaseManager(test_db_name)
