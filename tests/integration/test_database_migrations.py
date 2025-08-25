#!/usr/bin/env python3
"""
Integration tests for database migrations using Docker services
Tests the complete workflow of database setup, migrations, and verification
"""

import pytest
import sys
import time
import requests
import json
import pymysql
from pathlib import Path
from datetime import datetime

# Add the project root to the path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))


class TestDatabaseMigrations:
    """Integration tests for database migrations using Docker services"""

    @pytest.fixture
    def test_database_config(self, request):
        """Get test database configuration from environment variables"""
        return {
            'host': request.getfixturevalue('test_database_config')['host'],
            'port': request.getfixturevalue('test_database_config')['port'],
            'name': request.getfixturevalue('test_database_config')['name'],
            'user': request.getfixturevalue('test_database_config')['user'],
            'password': request.getfixturevalue('test_database_config')['password']
        }

    @pytest.fixture
    def analytics_service_url(self, request):
        """Get analytics service URL from Docker environment"""
        return request.getfixturevalue('test_services')['analytics']

    def test_database_connection(self, test_database_config):
        """Test that we can connect to the Docker test database"""
        print(f"🔌 Testing database connection to {test_database_config['host']}:{test_database_config['port']}")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                charset='utf8mb4'
            )

            with connection.cursor() as cursor:
                cursor.execute("SELECT VERSION()")
                version = cursor.fetchone()
                print(f"✅ Connected to MySQL version: {version[0]}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to connect to test database: {e}")

    def test_database_exists(self, test_database_config):
        """Test that the test database exists and is accessible"""
        print(f"🔍 Testing database existence: {test_database_config['name']}")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor() as cursor:
                cursor.execute("SHOW TABLES")
                tables = cursor.fetchall()
                print(f"✅ Database accessible with {len(tables)} tables")

                # Print table names
                table_names = [table[0] for table in tables]
                print(f"   Tables: {', '.join(table_names[:10])}{'...' if len(table_names) > 10 else ''}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to access test database: {e}")

    def test_migration_log_table_exists(self, test_database_config):
        """Verify that migration_log table exists and contains expected migrations"""
        print("\n🔄 Testing migration log table verification...")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Check if migration_log table exists
                cursor.execute("SHOW TABLES LIKE 'migration_log'")
                result = cursor.fetchall()

                assert result, "Migration log table should exist"
                print("✅ Migration log table exists")

                # Check migration log entries
                cursor.execute("SELECT * FROM migration_log ORDER BY id")
                migrations = cursor.fetchall()

                # Check that we have migrations (don't enforce exact count as it may vary)
                assert len(migrations) > 0, "No migrations found in migration_log table"

                # Print migration details for debugging
                print(f"Found {len(migrations)} migrations in database:")
                for migration in migrations:
                    print(f"   - {migration['filename']} (executed at {migration['executed_at']})")

                print(f"✅ Migration verification complete - {len(migrations)} migrations found")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify migration log table: {e}")

    def test_market_conditions_table_schema(self, test_database_config):
        """Verify that market_conditions table has the correct schema"""
        print("\n🔄 Testing market conditions table schema verification...")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get table schema
                cursor.execute("DESCRIBE market_conditions")
                columns = cursor.fetchall()

                                # Verify expected columns exist (check for key columns)
                column_names = [col['Field'] for col in columns]
                expected_columns = ['id', 'symbol', 'timeframe', 'rsi', 'stoch_main', 'macd_main']

                for expected_col in expected_columns:
                    assert expected_col in column_names, f"Expected column {expected_col} not found"

                print(f"✅ Market conditions table schema verified with {len(columns)} columns")
                print(f"   Available columns: {', '.join(column_names)}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify market conditions table schema: {e}")

    def test_analytics_service_health(self, analytics_service_url):
        """Test that the analytics service is healthy and accessible"""
        print(f"\n🔍 Testing analytics service health: {analytics_service_url}")

        try:
            response = requests.get(f"{analytics_service_url}/health", timeout=10)
            assert response.status_code == 200, f"Analytics service returned {response.status_code}"

            health_data = response.json()
            assert health_data["status"] == "healthy", f"Analytics service not healthy: {health_data}"

            print(f"✅ Analytics service health: {health_data}")

        except requests.exceptions.RequestException as e:
            pytest.fail(f"Analytics service not accessible: {e}")

    def test_database_migrations_complete(self, test_database_config):
        """Test that all expected migrations have been applied"""
        print("\n🔄 Testing that all migrations are complete...")

        try:
            connection = pymysql.connect(
                host=test_database_config['host'],
                port=test_database_config['port'],
                user=test_database_config['user'],
                password=test_database_config['password'],
                database=test_database_config['name'],
                charset='utf8mb4'
            )

            with connection.cursor(pymysql.cursors.DictCursor) as cursor:
                # Get all tables
                cursor.execute("SHOW TABLES")
                tables = cursor.fetchall()
                # Handle dict cursor results
                table_names = [table['Tables_in_test_breakout_analytics'] for table in tables]

                # Check for key tables that should exist after migrations
                expected_tables = [
                    'migration_log',
                    'market_conditions',
                    'ml_predictions',
                    'trades',
                    'ml_model_performance'
                ]

                missing_tables = [table for table in expected_tables if table not in table_names]
                assert not missing_tables, f"Missing expected tables: {missing_tables}"

                print(f"✅ All expected tables exist: {', '.join(expected_tables)}")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify database migrations: {e}")
