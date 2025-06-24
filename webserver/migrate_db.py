#!/usr/bin/env python3
"""
Database migration script to add strategy_version column and unique constraint
"""

import sqlite3
import os
from datetime import datetime

def migrate_database():
    """Migrate the database to add strategy_version column and unique constraint"""

    db_path = 'instance/strategy_tester.db'

    # Check if database exists
    if not os.path.exists(db_path):
        print(f"Database not found at {db_path}. Creating new database...")
        return

    print(f"Migrating database at {db_path}...")

    # Connect to the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        # Check if strategy_version column already exists
        cursor.execute("PRAGMA table_info(strategy_test)")
        columns = [column[1] for column in cursor.fetchall()]

        if 'strategy_version' not in columns:
            print("Adding strategy_version column...")
            cursor.execute("ALTER TABLE strategy_test ADD COLUMN strategy_version TEXT DEFAULT '1.00'")

            # Update existing records with a default version
            cursor.execute("UPDATE strategy_test SET strategy_version = '1.00' WHERE strategy_version IS NULL")
            print("Updated existing records with default version '1.00'")
        else:
            print("strategy_version column already exists")

        # Check for duplicate entries and handle them
        print("Checking for duplicate entries...")
        cursor.execute("""
            SELECT strategy_name, strategy_version, timeframe, start_date, end_date, parameters, COUNT(*) as count
            FROM strategy_test
            GROUP BY strategy_name, strategy_version, timeframe, start_date, end_date, parameters
            HAVING COUNT(*) > 1
        """)
        duplicates = cursor.fetchall()

        if duplicates:
            print(f"Found {len(duplicates)} duplicate groups. Handling duplicates...")

            for duplicate in duplicates:
                strategy_name, strategy_version, timeframe, start_date, end_date, parameters, count = duplicate

                # Get all IDs for this duplicate group
                cursor.execute("""
                    SELECT id FROM strategy_test
                    WHERE strategy_name = ? AND strategy_version = ? AND timeframe = ?
                    AND start_date = ? AND end_date = ? AND parameters = ?
                    ORDER BY id
                """, (strategy_name, strategy_version, timeframe, start_date, end_date, parameters))

                ids = [row[0] for row in cursor.fetchall()]

                # Keep the first one, update the rest to make them unique
                for i, test_id in enumerate(ids[1:], 1):
                    # Add a suffix to make the strategy name unique
                    new_strategy_name = f"{strategy_name}_duplicate_{i}"
                    cursor.execute("""
                        UPDATE strategy_test
                        SET strategy_name = ?
                        WHERE id = ?
                    """, (new_strategy_name, test_id))
                    print(f"  Updated duplicate ID {test_id} to strategy_name: {new_strategy_name}")

        # Check if unique constraint already exists
        cursor.execute("PRAGMA index_list(strategy_test)")
        indexes = [index[1] for index in cursor.fetchall()]

        if 'uq_strategy_test_run' not in indexes:
            print("Adding unique constraint...")
            # Create the unique constraint
            cursor.execute("""
                CREATE UNIQUE INDEX uq_strategy_test_run
                ON strategy_test (strategy_name, strategy_version, timeframe, start_date, end_date, parameters)
            """)
            print("Added unique constraint")
        else:
            print("Unique constraint already exists")

        # Create index for better performance
        if 'idx_strategy_test_unique' not in indexes:
            print("Adding performance index...")
            cursor.execute("""
                CREATE INDEX idx_strategy_test_unique
                ON strategy_test (strategy_name, strategy_version, timeframe, start_date, end_date, parameters)
            """)
            print("Added performance index")
        else:
            print("Performance index already exists")

        # Commit changes
        conn.commit()
        print("Migration completed successfully!")

        # Show current table structure
        print("\nCurrent table structure:")
        cursor.execute("PRAGMA table_info(strategy_test)")
        for column in cursor.fetchall():
            print(f"  {column[1]} ({column[2]})")

        # Show indexes
        print("\nCurrent indexes:")
        cursor.execute("PRAGMA index_list(strategy_test)")
        for index in cursor.fetchall():
            print(f"  {index[1]} ({index[2]})")

    except Exception as e:
        print(f"Error during migration: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    migrate_database()
