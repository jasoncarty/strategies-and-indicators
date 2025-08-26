#!/usr/bin/env python3
"""
Analytics Database Migration Script
Migrates analytics data between different database containers

Usage:
    python migrate_analytics_db.py --from-container SOURCE_CONTAINER --to-container TARGET_CONTAINER [options]

Examples:
    # Test migration to test container
    python migrate_analytics_db.py --from-container legacy_analytics --to-container trading_test_analytics --dry-run

    # Production migration
    python migrate_analytics_db.py --from-container legacy_analytics --to-container trading_dev_analytics --backup
"""

import argparse
import logging
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
import pymysql
from pymysql.cursors import DictCursor
import json

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

from analytics.database.config import DatabaseConfig

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/migration.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DatabaseMigrator:
    """Handles migration between different database containers"""

    def __init__(self, source_config: Dict[str, Any], target_config: Dict[str, Any]):
        self.source_config = source_config
        self.target_config = target_config
        self.source_conn = None
        self.target_conn = None

    def connect_source(self):
        """Connect to source database"""
        try:
            logger.info(f"🔌 Connecting to source database: {self.source_config['host']}:{self.source_config['port']}")
            self.source_conn = pymysql.connect(
                **self.source_config,
                cursorclass=DictCursor,
                autocommit=True
            )
            logger.info("✅ Source database connected successfully")
        except Exception as e:
            logger.error(f"❌ Failed to connect to source database: {e}")
            raise

    def connect_target(self):
        """Connect to target database"""
        try:
            logger.info(f"🔌 Connecting to target database: {self.target_config['host']}:{self.target_config['port']}")
            self.target_conn = pymysql.connect(
                **self.target_config,
                cursorclass=DictCursor,
                autocommit=True
            )
            logger.info("✅ Target database connected successfully")
        except Exception as e:
            logger.error(f"❌ Failed to connect to target database: {e}")
            raise

    def disconnect(self):
        """Close all database connections"""
        if self.source_conn:
            try:
                self.source_conn.close()
                logger.info("🔌 Source database connection closed")
            except Exception as e:
                logger.warning(f"⚠️ Error closing source connection: {e}")

        if self.target_conn:
            try:
                self.target_conn.close()
                logger.info("🔌 Target database connection closed")
            except Exception as e:
                logger.warning(f"⚠️ Error closing target connection: {e}")

    def get_table_schema(self, table_name: str, connection) -> Dict[str, Any]:
        """Get table schema information"""
        try:
            with connection.cursor() as cursor:
                cursor.execute(f"DESCRIBE {table_name}")
                columns = cursor.fetchall()

                schema = {
                    'table_name': table_name,
                    'columns': [],
                    'primary_key': None,
                    'indexes': []
                }

                for col in columns:
                    column_info = {
                        'name': col['Field'],
                        'type': col['Type'],
                        'null': col['Null'] == 'YES',
                        'key': col['Key'],
                        'default': col['Default'],
                        'extra': col['Extra']
                    }
                    schema['columns'].append(column_info)

                    if col['Key'] == 'PRI':
                        schema['primary_key'] = col['Field']

                # Get indexes
                cursor.execute(f"SHOW INDEX FROM {table_name}")
                indexes = cursor.fetchall()
                for idx in indexes:
                    if idx['Key_name'] != 'PRIMARY':
                        schema['indexes'].append({
                            'name': idx['Key_name'],
                            'column': idx['Column_name'],
                            'non_unique': idx['Non_unique'] == 1
                        })

                return schema

        except Exception as e:
            logger.error(f"❌ Failed to get schema for table {table_name}: {e}")
            raise

    def compare_schemas(self, source_schema: Dict, target_schema: Dict) -> List[str]:
        """Compare source and target table schemas"""
        differences = []

        # Compare columns
        source_cols = {col['name']: col for col in source_schema['columns']}
        target_cols = {col['name']: col for col in target_schema['columns']}

        # Check for missing columns in target
        for col_name, col_info in source_cols.items():
            if col_name not in target_cols:
                differences.append(f"Missing column in target: {col_name} ({col_info['type']})")
            else:
                # Check for type differences
                if col_info['type'] != target_cols[col_name]['type']:
                    differences.append(f"Column type mismatch for {col_name}: source={col_info['type']}, target={target_cols[col_name]['type']}")

        # Check for extra columns in target
        for col_name in target_cols:
            if col_name not in source_cols:
                differences.append(f"Extra column in target: {col_name}")

        return differences

    def get_table_list(self, connection) -> List[str]:
        """Get list of tables in database"""
        try:
            with connection.cursor() as cursor:
                cursor.execute("SHOW TABLES")
                tables = cursor.fetchall()
                return [list(table.values())[0] for table in tables]
        except Exception as e:
            logger.error(f"❌ Failed to get table list: {e}")
            raise

    def get_table_row_count(self, table_name: str, connection) -> int:
        """Get row count for a table"""
        try:
            with connection.cursor() as cursor:
                cursor.execute(f"SELECT COUNT(*) as count FROM {table_name}")
                result = cursor.fetchone()
                return result['count'] if result else 0
        except Exception as e:
            logger.error(f"❌ Failed to get row count for {table_name}: {e}")
            return 0

    def migrate_table(self, table_name: str, batch_size: int = 1000, dry_run: bool = False) -> Dict[str, Any]:
        """Migrate a single table"""
        migration_stats = {
            'table_name': table_name,
            'source_rows': 0,
            'target_rows_before': 0,
            'target_rows_after': 0,
            'migrated_rows': 0,
            'errors': []
        }

        try:
            # Get row counts
            migration_stats['source_rows'] = self.get_table_row_count(table_name, self.source_conn)
            migration_stats['target_rows_before'] = self.get_table_row_count(table_name, self.target_conn)

            if migration_stats['source_rows'] == 0:
                logger.info(f"📊 Table {table_name}: No data to migrate")
                return migration_stats

            logger.info(f"📊 Migrating table {table_name}: {migration_stats['source_rows']} rows")

            if dry_run:
                logger.info(f"🔍 DRY RUN: Would migrate {migration_stats['source_rows']} rows to {table_name}")
                return migration_stats

            # Clear target table first - disable foreign key checks temporarily
            with self.target_conn.cursor() as cursor:
                cursor.execute("SET FOREIGN_KEY_CHECKS = 0")
                cursor.execute(f"TRUNCATE TABLE {table_name}")
                cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
                logger.info(f"🧹 Cleared target table {table_name}")

            # Migrate data in batches
            offset = 0
            while offset < migration_stats['source_rows']:
                try:
                    with self.source_conn.cursor() as cursor:
                        cursor.execute(f"SELECT * FROM {table_name} LIMIT {batch_size} OFFSET {offset}")
                        batch = cursor.fetchall()

                        if not batch:
                            break

                        # Insert batch into target
                        if batch:
                            with self.target_conn.cursor() as target_cursor:
                                # Build INSERT statement dynamically
                                columns = list(batch[0].keys())
                                placeholders = ', '.join(['%s'] * len(columns))
                                insert_sql = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"

                                # Prepare batch data
                                batch_data = []
                                for row in batch:
                                    row_values = [row[col] for col in columns]
                                    batch_data.append(row_values)

                                target_cursor.executemany(insert_sql, batch_data)
                                self.target_conn.commit()

                                migration_stats['migrated_rows'] += len(batch)
                                logger.info(f"📦 Migrated batch: {len(batch)} rows (total: {migration_stats['migrated_rows']})")

                        offset += batch_size

                except Exception as e:
                    error_msg = f"Batch migration error at offset {offset}: {e}"
                    migration_stats['errors'].append(error_msg)
                    logger.error(f"❌ {error_msg}")
                    break

            # Get final row count
            migration_stats['target_rows_after'] = self.get_table_row_count(table_name, self.target_conn)

            if migration_stats['migrated_rows'] == migration_stats['source_rows']:
                logger.info(f"✅ Successfully migrated table {table_name}: {migration_stats['migrated_rows']} rows")
            else:
                logger.warning(f"⚠️ Partial migration for table {table_name}: {migration_stats['migrated_rows']}/{migration_stats['source_rows']} rows")

            return migration_stats

        except Exception as e:
            error_msg = f"Table migration failed: {e}"
            migration_stats['errors'].append(error_msg)
            logger.error(f"❌ {error_msg}")
            return migration_stats

    def create_backup(self, backup_path: str) -> bool:
        """Create backup of target database before migration"""
        try:
            logger.info(f"💾 Creating backup at: {backup_path}")

            # Use mysqldump if available
            import subprocess

            backup_cmd = [
                'mysqldump',
                f'--host={self.target_config["host"]}',
                f'--port={self.target_config["port"]}',
                f'--user={self.target_config["user"]}',
                f'--password={self.target_config["password"]}',
                '--protocol=TCP',  # Force TCP connection instead of socket
                '--single-transaction',
                '--routines',
                '--triggers',
                self.target_config['database']
            ]

            with open(backup_path, 'w') as backup_file:
                result = subprocess.run(backup_cmd, stdout=backup_file, stderr=subprocess.PIPE, text=True)

                if result.returncode == 0:
                    logger.info("✅ Backup created successfully")
                    return True
                else:
                    logger.error(f"❌ Backup failed: {result.stderr}")
                    return False

        except Exception as e:
            logger.error(f"❌ Backup creation failed: {e}")
            return False

    def run_migration(self, tables: List[str] = None, batch_size: int = 1000,
                     dry_run: bool = False, create_backup: bool = False) -> Dict[str, Any]:
        """Run the complete migration process"""
        migration_summary = {
            'start_time': datetime.now().isoformat(),
            'end_time': None,
            'tables_migrated': 0,
            'total_rows_migrated': 0,
            'errors': [],
            'table_results': []
        }

        try:
            # Create backup if requested
            if create_backup and not dry_run:
                backup_path = f"backups/analytics_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
                Path("backups").mkdir(exist_ok=True)
                if not self.create_backup(backup_path):
                    migration_summary['errors'].append("Backup creation failed")
                    return migration_summary

            # Get table list if not specified
            if not tables:
                tables = self.get_table_list(self.source_conn)
                logger.info(f"📋 Found {len(tables)} tables to migrate: {', '.join(tables)}")

            # Define migration order to respect foreign key constraints
            # Parent tables first, then child tables
            migration_order = [
                'trades',                    # Parent table
                'migration_log',            # Independent table
                'strategy_performance',     # Independent table
                'daily_statistics',         # Independent table
                'ml_model_performance',     # Independent table
                'market_conditions',        # References trades.trade_id
                'ml_predictions',           # References trades.trade_id
                'ml_trade_logs',            # References trades.trade_id
                'ml_trade_closes'           # References trades.trade_id
            ]

            # Filter tables to only include those that exist in source
            available_tables = [table for table in migration_order if table in tables]
            logger.info(f"📋 Migrating tables in dependency order: {', '.join(available_tables)}")

            # Migrate each table in the correct order
            for table_name in available_tables:
                try:
                    # Check if table exists in target
                    target_tables = self.get_table_list(self.target_conn)
                    if table_name not in target_tables:
                        logger.warning(f"⚠️ Table {table_name} not found in target database, skipping")
                        continue

                    # Compare schemas
                    source_schema = self.get_table_schema(table_name, self.source_conn)
                    target_schema = self.get_table_schema(table_name, self.target_conn)
                    schema_differences = self.compare_schemas(source_schema, target_schema)

                    if schema_differences:
                        logger.warning(f"⚠️ Schema differences found for table {table_name}:")
                        for diff in schema_differences:
                            logger.warning(f"   - {diff}")

                    # Migrate table
                    table_result = self.migrate_table(table_name, batch_size, dry_run)
                    migration_summary['table_results'].append(table_result)

                    if table_result['migrated_rows'] > 0:
                        migration_summary['tables_migrated'] += 1
                        migration_summary['total_rows_migrated'] += table_result['migrated_rows']

                    if table_result['errors']:
                        migration_summary['errors'].extend(table_result['errors'])

                except Exception as e:
                    error_msg = f"Failed to migrate table {table_name}: {e}"
                    migration_summary['errors'].append(error_msg)
                    logger.error(f"❌ {error_msg}")

            migration_summary['end_time'] = datetime.now().isoformat()

            # Log summary
            logger.info("=" * 60)
            logger.info("📊 MIGRATION SUMMARY")
            logger.info("=" * 60)
            logger.info(f"Tables migrated: {migration_summary['tables_migrated']}")
            logger.info(f"Total rows migrated: {migration_summary['total_rows_migrated']}")
            logger.info(f"Errors: {len(migration_summary['errors'])}")

            if migration_summary['errors']:
                logger.error("❌ Migration completed with errors:")
                for error in migration_summary['errors']:
                    logger.error(f"   - {error}")
            else:
                logger.info("✅ Migration completed successfully!")

            return migration_summary

        except Exception as e:
            error_msg = f"Migration process failed: {e}"
            migration_summary['errors'].append(error_msg)
            logger.error(f"❌ {error_msg}")
            return migration_summary

def get_container_db_config(container_name: str) -> Dict[str, Any]:
    """Get database configuration for a specific container"""
    # This would need to be customized based on your container setup
    # For now, using environment variables and common patterns

    if 'test' in container_name.lower():
        # Test container configuration
        return {
            'host': 'localhost',
            'port': 3308,  # Test port from docker.test.env
            'database': 'test_breakout_analytics',
            'user': 'test_user',
            'password': 'test_password_2024',
            'charset': 'utf8mb4'
        }
    elif 'dev' in container_name.lower():
        # Development container configuration
        return {
            'host': 'localhost',
            'port': 3307,  # Dev port from docker.dev.env
            'database': 'breakout_analytics',
            'user': 'breakout_user',
            'password': 'breakout_password_2024',
            'charset': 'utf8mb4'
        }

    elif 'legacy' in container_name.lower():
        # Legacy analytics database configuration
        return {
            'host': 'localhost',
            'port': 3306,  # Legacy database port
            'database': 'breakout_analytics',
            'user': 'breakout_user',
            'password': 'breakout_password_2024',
            'charset': 'utf8mb4'
        }

    elif 'prod' in container_name.lower():
        # Development container configuration
        return {
            'host': 'localhost',
            'port': 3310,  # Dev port from docker.dev.env
            'database': 'breakout_analytics',
            'user': 'breakout_user',
            'password': 'breakout_password_2024',
            'charset': 'utf8mb4'
        }

    else:
        # Legacy/other container - you'll need to customize this
        raise ValueError(f"Unknown container type: {container_name}. Please specify database connection details.")

def main():
    """Main migration function"""
    parser = argparse.ArgumentParser(description='Migrate analytics database between containers')
    parser.add_argument('--from-container', required=True, help='Source container name')
    parser.add_argument('--to-container', required=True, help='Target container name')
    parser.add_argument('--tables', nargs='+', help='Specific tables to migrate (default: all)')
    parser.add_argument('--batch-size', type=int, default=1000, help='Batch size for migration (default: 1000)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be migrated without actually doing it')
    parser.add_argument('--backup', action='store_true', help='Create backup before migration')
    parser.add_argument('--source-host', help='Source database host (overrides container config)')
    parser.add_argument('--source-port', type=int, help='Source database port (overrides container config)')
    parser.add_argument('--source-db', help='Source database name (overrides container config)')
    parser.add_argument('--source-user', help='Source database user (overrides container config)')
    parser.add_argument('--source-password', help='Source database password (overrides container config)')

    args = parser.parse_args()

    try:
        # Create logs directory
        Path('logs').mkdir(exist_ok=True)

        logger.info("🚀 Starting Analytics Database Migration")
        logger.info("=" * 60)
        logger.info(f"Source: {args.from_container}")
        logger.info(f"Target: {args.to_container}")
        logger.info(f"Dry run: {args.dry_run}")
        logger.info(f"Backup: {args.backup}")
        logger.info("=" * 60)

        # Get database configurations
        try:
            source_config = get_container_db_config(args.from_container)
            target_config = get_container_db_config(args.to_container)
        except ValueError as e:
            logger.error(f"❌ {e}")
            logger.info("💡 Use --source-host, --source-port, etc. to specify custom connection details")
            return 1

        # Override with custom parameters if provided
        if args.source_host:
            source_config['host'] = args.source_host
        if args.source_port:
            source_config['port'] = args.source_port
        if args.source_db:
            source_config['database'] = args.source_db
        if args.source_user:
            source_config['user'] = args.source_user
        if args.source_password:
            source_config['password'] = args.source_password

        # Create migrator and run migration
        migrator = DatabaseMigrator(source_config, target_config)

        try:
            migrator.connect_source()
            migrator.connect_target()

            migration_result = migrator.run_migration(
                tables=args.tables,
                batch_size=args.batch_size,
                dry_run=args.dry_run,
                create_backup=args.backup
            )

            # Save migration report
            report_path = f"logs/migration_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(report_path, 'w') as f:
                json.dump(migration_result, f, indent=2, default=str)

            logger.info(f"📄 Migration report saved to: {report_path}")

            return 0 if not migration_result['errors'] else 1

        finally:
            migrator.disconnect()

    except KeyboardInterrupt:
        logger.info("\n🛑 Migration interrupted by user")
        return 1
    except Exception as e:
        logger.error(f"❌ Migration failed: {e}")
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
