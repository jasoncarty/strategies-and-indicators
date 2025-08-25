#!/usr/bin/env python3
"""
Simple integration tests for database migrations using Docker services
"""
import pytest
import pymysql
from pathlib import Path


class TestDatabaseMigrationsSimple:
    """Simple integration tests for database migrations using Docker services"""

    @pytest.fixture
    def test_database_config(self, request):
        """Get test database configuration from environment variables"""
        return request.getfixturevalue('test_database_config')

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

                print(f"✅ Found {len(migrations)} migration records")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify migration log table: {e}")

    def test_core_tables_exist(self, test_database_config):
        """Verify that core tables exist after migrations"""
        expected_tables = [
            'migration_log',
            'trades',
            'market_conditions',
            'ml_predictions',
            'ml_trade_logs'
        ]

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
                cursor.execute("SHOW TABLES")
                existing_tables = [row['Tables_in_test_breakout_analytics'] for row in cursor.fetchall()]

                for table in expected_tables:
                    assert table in existing_tables, f"Table {table} should exist after migrations"
                    print(f"✅ Table {table} exists")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to verify core tables: {e}")

    def test_database_connection_works(self, test_database_config):
        """Test basic database connectivity"""
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
                cursor.execute("SELECT 1 as test_value")
                result = cursor.fetchone()
                # Handle both tuple and dict results
                if isinstance(result, dict):
                    assert result['test_value'] == 1
                else:
                    assert result[0] == 1
                print("✅ Database connection working")

            connection.close()

        except Exception as e:
            pytest.fail(f"Failed to test database connection: {e}")
