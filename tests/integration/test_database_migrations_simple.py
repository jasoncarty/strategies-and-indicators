#!/usr/bin/env python3
"""
Simplified integration test for database migrations using the new testing framework
"""
import pytest
import pymysql
from pathlib import Path

def test_migration_log_table_exists(test_db_connection):
    """Verify that migration_log table exists and contains expected migrations"""
    with test_db_connection.cursor(pymysql.cursors.DictCursor) as cursor:
        # Check if migration_log table exists
        cursor.execute("SHOW TABLES LIKE 'migration_log'")
        result = cursor.fetchall()

        assert result, "Migration log table should exist"
        print("✅ Migration log table exists")

        # Check migration log entries
        cursor.execute("SELECT * FROM migration_log ORDER BY id")
        migrations = cursor.fetchall()

        # Dynamically count migration files from filesystem
        migrations_dir = Path(__file__).parent.parent.parent / 'analytics' / 'database' / 'migrations'
        migration_files = sorted([f.name for f in migrations_dir.glob("*.sql")])
        expected_migrations = len(migration_files)

        assert len(migrations) == expected_migrations, \
            f"Expected {expected_migrations} migrations, found {len(migrations)}"

        # Verify all migration files from filesystem have been executed
        executed_filenames = [migration['filename'] for migration in migrations]
        for migration_file in migration_files:
            assert migration_file in executed_filenames, \
                f"Migration file {migration_file} has not been executed"

        print(f"✅ Found {len(migrations)} migration records")
        for migration in migrations:
            print(f"   - {migration['filename']} (executed at {migration['executed_at']})")

def test_core_tables_exist(test_db_connection):
    """Verify that core tables exist after migrations"""
    expected_tables = [
        'migration_log',
        'trades',
        'market_conditions',
        'ml_predictions',
        'ml_trade_logs'
    ]

    with test_db_connection.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute("SHOW TABLES")
        existing_tables = [row['Tables_in_test_breakout_analytics'] for row in cursor.fetchall()]

        for table in expected_tables:
            assert table in existing_tables, f"Table {table} should exist after migrations"
            print(f"✅ Table {table} exists")

def test_database_connection_works(test_db_connection):
    """Test basic database connectivity"""
    with test_db_connection.cursor() as cursor:
        cursor.execute("SELECT 1 as test_value")
        result = cursor.fetchone()
        assert result['test_value'] == 1
        print("✅ Database connection working")
