#!/usr/bin/env python3
"""
Integration tests for database migrations using the new pytest framework
"""
import pytest
import pymysql
from pathlib import Path

def test_migration_log_table_exists(test_db_connection):
    """Verify that migration_log table exists and contains expected migrations"""
    print("\n🔄 Testing migration log table verification...")

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
        # Handle both tuple and dict results
        if isinstance(result, dict):
            assert result['test_value'] == 1
        else:
            assert result[0] == 1
        print("✅ Database connection working")

def test_migration_log_structure(test_db_connection):
    """Test migration_log table structure"""
    with test_db_connection.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute("DESCRIBE migration_log")
        columns = cursor.fetchall()

        expected_columns = ['id', 'filename', 'executed_at', 'status']
        column_names = [col['Field'] for col in columns]

        for expected_col in expected_columns:
            assert expected_col in column_names, f"Column {expected_col} should exist in migration_log"

        print("✅ Migration log table structure is correct")

def test_migration_execution_order(test_db_connection):
    """Test that migrations were executed in the correct order"""
    with test_db_connection.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute("SELECT filename, executed_at FROM migration_log ORDER BY id")
        migrations = cursor.fetchall()

        # Check that we have at least some migrations
        assert len(migrations) > 0, "Should have at least one migration"

        # Check that migrations are executed in chronological order
        for i in range(1, len(migrations)):
            prev_time = migrations[i-1]['executed_at']
            curr_time = migrations[i]['executed_at']
            assert prev_time <= curr_time, f"Migration {i} executed before {i-1}"

        print("✅ Migrations executed in correct order")
