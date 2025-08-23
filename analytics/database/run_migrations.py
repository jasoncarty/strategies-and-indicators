#!/usr/bin/env python3
"""
Database migration runner for BreakoutStrategy analytics
"""
import os
import sys
import logging
from pathlib import Path
import pymysql

# Add the project root to the path for config access
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from analytics.database.config import DatabaseConfig
db_config = DatabaseConfig()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def run_migrations():
    """Run all database migrations"""
    try:
        # Connect to database
        connection = pymysql.connect(
            host=db_config.host,
            port=db_config.port,
            user=db_config.user,
            password=db_config.password,
            charset=db_config.charset
        )

        # Create database if it doesn't exist
        with connection.cursor() as cursor:
            cursor.execute(f"CREATE DATABASE IF NOT EXISTS {db_config.database}")
            logger.info(f"✅ Database '{db_config.database}' ready")

        # Connect to the specific database
        connection.select_db(db_config.database)

        # Get migration files
        migrations_dir = Path(__file__).parent / "migrations"
        migration_files = sorted([f for f in migrations_dir.glob("*.sql")])

        if not migration_files:
            logger.warning("⚠️ No migration files found")
            return

        logger.info(f"📁 Found {len(migration_files)} migration files")

        # Check if migration_log table exists
        with connection.cursor() as cursor:
            cursor.execute("SHOW TABLES LIKE 'migration_log'")
            migration_log_exists = cursor.fetchone() is not None

        if not migration_log_exists:
            logger.info("📋 Migration log table not found - creating it...")
            # Create migration log table manually
            create_migration_log_sql = """
            CREATE TABLE IF NOT EXISTS migration_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                filename VARCHAR(255) NOT NULL,
                executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                status ENUM('SUCCESS', 'FAILED') DEFAULT 'SUCCESS',
                error_message TEXT NULL,

                UNIQUE KEY unique_migration (filename),
                INDEX idx_executed_at (executed_at)
            ) COMMENT = 'Tracks which database migrations have been executed'
            """
            with connection.cursor() as cursor:
                cursor.execute(create_migration_log_sql)
            connection.commit()
            logger.info("✅ Migration log table created")

        # Run each migration
        for migration_file in migration_files:
            migration_filename = migration_file.name

            # Check if migration has already been run
            with connection.cursor() as cursor:
                cursor.execute("SELECT id FROM migration_log WHERE filename = %s", (migration_filename,))
                already_run = cursor.fetchone() is not None

            if already_run:
                logger.info(f"⏭️ Migration already run: {migration_filename}")
                continue

            logger.info(f"🔄 Running migration: {migration_filename}")

            try:
                with open(migration_file, 'r') as f:
                    migration_sql = f.read()

                # Split by semicolon to handle multiple statements
                statements = [stmt.strip() for stmt in migration_sql.split(';') if stmt.strip()]

                with connection.cursor() as cursor:
                    for statement in statements:
                        if statement:
                            cursor.execute(statement)
                            logger.info(f"   ✅ Executed: {statement[:50]}...")

                # Log successful migration
                with connection.cursor() as cursor:
                    cursor.execute(
                        "INSERT INTO migration_log (filename, status) VALUES (%s, 'SUCCESS')",
                        (migration_filename,)
                    )

                connection.commit()
                logger.info(f"✅ Migration completed: {migration_filename}")

            except Exception as e:
                # Log failed migration
                with connection.cursor() as cursor:
                    cursor.execute(
                        "INSERT INTO migration_log (filename, status, error_message) VALUES (%s, 'FAILED', %s)",
                        (migration_filename, str(e))
                    )
                connection.commit()
                logger.error(f"❌ Migration failed: {migration_filename} - {e}")
                raise

        logger.info("🎉 All migrations completed successfully!")

    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        raise
    finally:
        if 'connection' in locals():
            connection.close()

def create_database_user():
    """Create a dedicated database user for the application"""
    try:
        # Connect as root
        connection = pymysql.connect(
            host=db_config.host,
            port=db_config.port,
            user=db_config.user,
            password=db_config.password,
            charset=db_config.charset
        )

        app_user = "breakout_user"
        app_password = "breakout_password_2024"  # Change this in production

        with connection.cursor() as cursor:
            # Create user if it doesn't exist
            cursor.execute(f"CREATE USER IF NOT EXISTS '{app_user}'@'%' IDENTIFIED BY '{app_password}'")

            # Grant permissions
            cursor.execute(f"GRANT ALL PRIVILEGES ON {db_config.database}.* TO '{app_user}'@'%'")
            cursor.execute("FLUSH PRIVILEGES")

            logger.info(f"✅ Created database user: {app_user}")
            logger.info(f"📝 Update your .env file with:")
            logger.info(f"   DB_USER={app_user}")
            logger.info(f"   DB_PASSWORD={app_password}")

    except Exception as e:
        logger.error(f"❌ Failed to create database user: {e}")
        raise
    finally:
        if 'connection' in locals():
            connection.close()

if __name__ == "__main__":
    print("🚀 BreakoutStrategy Analytics Database Setup")
    print("=" * 50)

    # Check if we should create a user
    if len(sys.argv) > 1 and sys.argv[1] == "--create-user":
        create_database_user()
    else:
        run_migrations()

    print("\n📊 Database setup complete!")
    print("You can now run your BreakoutStrategy EA with analytics enabled.")
