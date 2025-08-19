"""
Database manager for BreakoutStrategy analytics
"""
import json
import logging
from datetime import datetime, date
from typing import Dict, List, Optional, Any
import pymysql
from pymysql.cursors import DictCursor

from .config import db_config

logger = logging.getLogger(__name__)

def validate_trade_id_data(data: Dict[str, Any], operation_name: str) -> None:
    """Validate trade_id in data for database operations"""
    if not data.get('trade_id'):
        raise ValueError(f"trade_id is required for {operation_name}")

    if data.get('trade_id') == 0 or data.get('trade_id') == '0' or data.get('trade_id') == '':
        raise ValueError(f"trade_id cannot be 0 or empty for {operation_name}")

class AnalyticsDatabase:
    """Database manager for analytics data"""

    def __init__(self):
        self.config = db_config
        self.connection = None
        self.last_connection_time = None
        self.connection_attempts = 0
        self.last_error_time = None
        self.max_connection_age = 3600  # 1 hour max connection age
        self.use_connection_pool = True  # Use fresh connections for each operation

    def connect(self):
        """Establish database connection"""
        try:
            connection_params = self.config.get_connection_params()
            # Add connection stability settings
            connection_params.update({
                'autocommit': True,  # Auto-commit to avoid transaction issues
                'charset': 'utf8mb4',
                'connect_timeout': 10,  # 10 second connection timeout
                'read_timeout': 30,     # 30 second read timeout
                'write_timeout': 30,    # 30 second write timeout
                'max_allowed_packet': 16777216,  # 16MB max packet size
                'sql_mode': 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO',
                'init_command': 'SET SESSION wait_timeout=28800,interactive_timeout=28800',
            })

            self.connection = pymysql.connect(
                **connection_params,
                cursorclass=DictCursor
            )
            self.last_connection_time = datetime.now()
            self.connection_attempts = 0
            logger.info("✅ Database connection established")
        except Exception as e:
            self.last_error_time = datetime.now()
            self.connection_attempts += 1
            logger.error(f"❌ Database connection failed: {e}")
            self.connection = None  # Ensure connection is None on failure
            raise

    def disconnect(self):
        """Close database connection"""
        if self.connection:
            try:
                self.connection.close()
                logger.info("🔌 Database connection closed")
            except Exception as e:
                logger.warning(f"⚠️ Error closing database connection: {e}")
            finally:
                self.connection = None

    def force_reconnect(self):
        """Force a clean reconnection by closing and re-establishing the connection"""
        logger.info("🔄 Forcing database reconnection...")
        try:
            self.disconnect()
            import time
            time.sleep(1)  # Brief delay to ensure cleanup
            self.connect()
            logger.info("✅ Force reconnection completed successfully")
        except Exception as e:
            logger.error(f"❌ Force reconnection failed: {e}")
            raise

    def _get_fresh_connection(self):
        """Create a completely fresh database connection for each operation"""
        try:
            connection_params = self.config.get_connection_params()
            # Add connection stability settings
            connection_params.update({
                'autocommit': True,  # Auto-commit to avoid transaction issues
                'charset': 'utf8mb4',
                'connect_timeout': 10,  # 10 second connection timeout
                'read_timeout': 30,     # 30 second read timeout
                'write_timeout': 30,    # 30 second write timeout
                'max_allowed_packet': 16777216,  # 16MB max packet size
                'sql_mode': 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO',
                'init_command': 'SET SESSION wait_timeout=28800,interactive_timeout=28800',
            })

            fresh_connection = pymysql.connect(
                **connection_params,
                cursorclass=DictCursor
            )

            # Test the fresh connection immediately
            with fresh_connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()

            logger.debug("✅ Fresh database connection created and tested successfully")
            return fresh_connection

        except Exception as e:
            logger.error(f"❌ Failed to create fresh database connection: {e}")
            return None

    def is_connected(self) -> bool:
        """Check if database connection is healthy"""
        try:
            if self.connection is None:
                return False

            # Test connection with a simple query
            with self.connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            return True
        except Exception as e:
            logger.debug(f"Database connection health check failed: {e}")
            return False

    def get_connection_status(self) -> Dict[str, Any]:
        """Get detailed connection status information"""
        status = {
            'connected': False,
            'connection_object': None,
            'error': None,
            'last_error_time': None
        }

        try:
            if self.connection is None:
                status['error'] = 'No connection object'
                return status

            # Test the connection
            with self.connection.cursor() as cursor:
                cursor.execute("SELECT 1 as test")
                result = cursor.fetchone()
                if result and result['test'] == 1:
                    status['connected'] = True
                    status['connection_object'] = f"<pymysql.Connection object at {id(self.connection)}>"
                else:
                    status['error'] = 'Connection test query failed'

        except Exception as e:
            status['error'] = str(e)
            status['last_error_time'] = datetime.now().isoformat()

        return status

    def _ensure_connection(self):
        """Ensure database connection is valid, reconnect if necessary"""
        # Check if connection is too old and needs refreshing
        if (self.connection and self.last_connection_time and
            (datetime.now() - self.last_connection_time).total_seconds() > self.max_connection_age):
            logger.info("🔄 Connection is too old, refreshing...")
            try:
                self.connection.close()
            except:
                pass
            self.connection = None

        max_retries = 3
        retry_count = 0

        while retry_count < max_retries:
            try:
                if self.connection is None:
                    logger.info("🔄 No database connection, establishing new connection...")
                    self.connect()
                    return

                # Test the connection with a simple query
                if hasattr(self.connection, 'ping'):
                    self.connection.ping(reconnect=False)
                else:
                    # Fallback: try a simple query to test connection
                    with self.connection.cursor() as cursor:
                        cursor.execute("SELECT 1")
                        cursor.fetchone()

                # If we get here, connection is healthy
                return

            except Exception as e:
                retry_count += 1
                logger.warning(f"⚠️ Database connection lost (attempt {retry_count}/{max_retries}), reconnecting... Error: {e}")

                # Clean up the corrupted connection
                try:
                    if self.connection:
                        self.connection.close()
                except Exception as cleanup_error:
                    logger.debug(f"Cleanup error (non-critical): {cleanup_error}")

                # Reset connection to None
                self.connection = None

                if retry_count >= max_retries:
                    logger.error(f"❌ Failed to establish database connection after {max_retries} attempts")
                    raise Exception(f"Database connection failed after {max_retries} retries: {e}")

                # Wait before retrying
                import time
                time.sleep(1)

                # Try to establish new connection
                try:
                    self.connect()
                except Exception as connect_error:
                    logger.error(f"❌ Connection attempt {retry_count} failed: {connect_error}")
                    if retry_count >= max_retries:
                        raise

    def _execute_with_retry(self, operation_name: str, operation_func, needs_rollback: bool = False, *args, **kwargs):
        """Generic retry wrapper for database operations"""
        max_retries = 3
        retry_count = 0

        while retry_count < max_retries:
            # Always use a fresh connection for each operation to avoid corruption
            fresh_connection = None
            try:
                # Create a completely fresh connection
                fresh_connection = self._get_fresh_connection()

                if fresh_connection is None:
                    raise Exception("Failed to create fresh database connection")

                # Execute the operation function with the fresh connection
                result = operation_func(fresh_connection, *args, **kwargs)
                return result

            except Exception as e:
                retry_count += 1
                logger.error(f"❌ {operation_name} failed (attempt {retry_count}/{max_retries}): {e}")

                # Clean up the fresh connection
                if fresh_connection:
                    try:
                        fresh_connection.close()
                    except:
                        pass

                if retry_count >= max_retries:
                    logger.error(f"❌ {operation_name} failed after {max_retries} attempts")
                    raise

                logger.info(f"🔄 Retrying {operation_name} (attempt {retry_count + 1}/{max_retries})...")
                import time
                time.sleep(1)  # Brief delay before retry

    def execute_query(self, query: str, params: tuple = None) -> List[Dict]:
        """Execute a SELECT query"""
        def _query_operation(connection):
            with connection.cursor() as cursor:
                cursor.execute(query, params)
                return cursor.fetchall()

        return self._execute_with_retry("Query execution", _query_operation, False)

    def execute_insert(self, query: str, params: tuple = None) -> int:
        """Execute an INSERT query and return the last insert ID"""
        # Log the SQL query and parameters for debugging
        logger.info(f"🔍 Executing SQL: {query}")
        logger.info(f"🔍 SQL parameters: {params}")

        def _insert_operation(connection):
            with connection.cursor() as cursor:
                cursor.execute(query, params)
                connection.commit()
                return cursor.lastrowid

        return self._execute_with_retry("Insert execution", _insert_operation, True)

    def execute_update(self, query: str, params: tuple = None) -> int:
        """Execute an UPDATE query and return affected rows"""
        def _update_operation(connection):
            with connection.cursor() as cursor:
                cursor.execute(query, params)
                connection.commit()
                return cursor.rowcount

        return self._execute_with_retry("Update execution", _update_operation, True)

    def insert_trade(self, trade_data: Dict[str, Any]) -> str:
        """Insert a new trade record with upsert logic to handle duplicates"""

        query = """
        INSERT INTO trades (
            trade_id, symbol, timeframe, direction, entry_price, exit_price,
            stop_loss, take_profit, lot_size, profit_loss, profit_loss_pips,
            entry_time, exit_time, duration_seconds, status, strategy_name,
            strategy_version, account_id
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
        ) ON DUPLICATE KEY UPDATE
            symbol = VALUES(symbol),
            timeframe = VALUES(timeframe),
            direction = VALUES(direction),
            entry_price = VALUES(entry_price),
            exit_price = COALESCE(VALUES(exit_price), exit_price),
            stop_loss = COALESCE(VALUES(stop_loss), stop_loss),
            take_profit = COALESCE(VALUES(take_profit), take_profit),
            lot_size = VALUES(lot_size),
            profit_loss = COALESCE(VALUES(profit_loss), profit_loss),
            profit_loss_pips = COALESCE(VALUES(profit_loss_pips), profit_loss_pips),
            entry_time = COALESCE(VALUES(entry_time), entry_time),
            exit_time = COALESCE(VALUES(exit_time), exit_time),
            duration_seconds = COALESCE(VALUES(duration_seconds), duration_seconds),
            status = VALUES(status),
            strategy_name = VALUES(strategy_name),
            strategy_version = VALUES(strategy_version),
            account_id = VALUES(account_id)
        """

        # Convert Unix timestamps to datetime format
        entry_time = datetime.fromtimestamp(trade_data['entry_time']) if isinstance(trade_data['entry_time'], (int, float)) else trade_data['entry_time']
        exit_time = None
        if trade_data.get('exit_time'):
            exit_time = datetime.fromtimestamp(trade_data['exit_time']) if isinstance(trade_data['exit_time'], (int, float)) else trade_data['exit_time']

        params = (
            trade_data['trade_id'],
            trade_data['symbol'],
            trade_data['timeframe'],
            trade_data['direction'],
            trade_data['entry_price'],
            trade_data.get('exit_price'),
            trade_data['stop_loss'],
            trade_data['take_profit'],
            trade_data['lot_size'],
            trade_data.get('profit_loss'),
            trade_data.get('profit_loss_pips'),
            entry_time,
            exit_time,
            trade_data.get('duration_seconds'),
            trade_data['status'],
            trade_data['strategy_name'],
            trade_data['strategy_version'],
            trade_data['account_id']
        )

        logger.info(f"📝 SQL Query: {query}")
        logger.info(f"📝 Parameters: {params}")

        try:
            result = self.execute_insert(query, params)
            logger.info(f"✅ Trade insert/update successful, result: {result}")
            return trade_data['trade_id']
        except Exception as e:
            logger.error(f"❌ Trade insert failed: {e}")
            logger.error(f"   Exception type: {type(e).__name__}")
            import traceback
            logger.error(f"   Traceback: {traceback.format_exc()}")
            raise

    def insert_ml_trade_log(self, trade_log_data: Dict[str, Any]) -> int:
        """Insert ML trade log data for retraining"""

        # Validate trade_id
        validate_trade_id_data(trade_log_data, "ML trade log insert")

        logger.info(f"📊 Inserting ML trade log for trade_id: {trade_log_data['trade_id']}")

        # Create placeholder trade if it doesn't exist
        trade_id = trade_log_data['trade_id']
        if trade_id != "0" and not self._trade_exists(trade_id):
            logger.info(f"📝 Creating placeholder trade for ML trade log: {trade_id}")
            self._create_placeholder_trade(trade_log_data)

        query = """
        INSERT INTO ml_trade_logs (
            trade_id, strategy, symbol, timeframe, direction, entry_price,
            stop_loss, take_profit, lot_size, ml_prediction, ml_confidence,
            ml_model_type, ml_model_key, trade_time, features_json, status,
            profit_loss, close_price, close_time, exit_reason, timestamp
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
        )
        """

        # Extract features as JSON - features are now at top level
        features_dict = {}
        feature_keys = ['rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
                       'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum',
                       'force_index', 'volume_ratio', 'price_change', 'volatility',
                       'spread', 'session_hour', 'is_news_time', 'day_of_week', 'month']

        for key in feature_keys:
            if key in trade_log_data:
                features_dict[key] = trade_log_data[key]

        features_json = json.dumps(features_dict)

        params = (
            trade_log_data['trade_id'],
            trade_log_data['strategy'],
            trade_log_data['symbol'],
            trade_log_data['timeframe'],
            trade_log_data['direction'],
            trade_log_data['entry_price'],
            trade_log_data['stop_loss'],
            trade_log_data['take_profit'],
            trade_log_data['lot_size'],
            trade_log_data['ml_prediction'],
            trade_log_data['ml_confidence'],
            trade_log_data['ml_model_type'],
            trade_log_data['ml_model_key'],
            trade_log_data['trade_time'],
            features_json,
            trade_log_data['status'],
            trade_log_data.get('profit_loss', 0.0),
            trade_log_data.get('close_price', 0.0),
            trade_log_data.get('close_time', 0),
            trade_log_data.get('exit_reason', ''),
            trade_log_data['timestamp']
        )

        return self.execute_insert(query, params)

    def insert_ml_trade_close(self, trade_close_data: Dict[str, Any]) -> int:
        """Update ML trade log with close data for retraining"""

        # Validate trade_id
        validate_trade_id_data(trade_close_data, "ML trade close update")

        logger.info(f"📊 Updating ML trade close for trade_id: {trade_close_data['trade_id']}")

        # First, update the existing record in ml_trade_logs
        update_query = """
        UPDATE ml_trade_logs
        SET status = %s,
            profit_loss = %s,
            close_price = %s,
            close_time = %s,
            exit_reason = %s
        WHERE trade_id = %s
        """

        update_params = (
            trade_close_data['status'],
            trade_close_data['profit_loss'],
            trade_close_data['close_price'],
            trade_close_data['close_time'],
            trade_close_data['exit_reason'],
            trade_close_data['trade_id']
        )

        updated_rows = self.execute_update(update_query, update_params)

        if updated_rows == 0:
            logger.warning(f"⚠️ No existing trade found to update for trade_id: {trade_close_data['trade_id']}")
            return 0

        # Also update the trades table if it exists
        try:
            # Get the original trade time from ml_trade_logs
            trade_time_query = "SELECT trade_time FROM ml_trade_logs WHERE trade_id = %s"
            trade_time_result = self.execute_query(trade_time_query, (trade_close_data['trade_id'],))

            # Calculate duration in seconds
            duration_seconds = None
            if trade_close_data.get('close_time') and trade_time_result:
                original_trade_time = trade_time_result[0]['trade_time']
                duration_seconds = int(trade_close_data['close_time']) - int(original_trade_time)

            trades_update_query = """
            UPDATE trades SET
                exit_price = %s,
                profit_loss = %s,
                profit_loss_pips = %s,
                exit_time = %s,
                duration_seconds = %s,
                status = %s
            WHERE trade_id = %s
            """

            # Convert Unix timestamp to datetime format
            exit_time = datetime.fromtimestamp(trade_close_data['close_time']) if isinstance(trade_close_data['close_time'], (int, float)) else trade_close_data['close_time']

            trades_update_params = (
                trade_close_data['close_price'],
                trade_close_data['profit_loss'],
                trade_close_data.get('profit_loss_pips', 0.0),
                exit_time,
                duration_seconds,
                trade_close_data['status'],
                trade_close_data['trade_id']
            )

            trades_updated = self.execute_update(trades_update_query, trades_update_params)
            if trades_updated > 0:
                logger.info(f"✅ Updated trades table for {trade_close_data['trade_id']}")
            else:
                logger.info(f"ℹ️ No matching record in trades table for {trade_close_data['trade_id']}")
        except Exception as e:
            logger.warning(f"⚠️ Could not update trades table: {e}")

        # Also insert into ml_trade_closes for historical tracking
        insert_query = """
        INSERT INTO ml_trade_closes (
            trade_id, strategy, symbol, timeframe, close_price, profit_loss,
            profit_loss_pips, close_time, exit_reason, status, success, timestamp
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
        )
        """

        insert_params = (
            trade_close_data['trade_id'],
            trade_close_data['strategy'],
            trade_close_data['symbol'],
            trade_close_data['timeframe'],
            trade_close_data['close_price'],
            trade_close_data['profit_loss'],
            trade_close_data['profit_loss_pips'],
            trade_close_data['close_time'],
            trade_close_data['exit_reason'],
            trade_close_data['status'],
            trade_close_data['success'],
            trade_close_data['timestamp']
        )

        self.execute_insert(insert_query, insert_params)

        logger.info(f"✅ Updated trade {trade_close_data['trade_id']} with close data")
        return updated_rows

    def insert_ml_prediction(self, prediction_data: Dict[str, Any]) -> int:
        """Insert ML prediction data"""
        # Log the data being inserted for debugging
        logger.info(f"🔍 Inserting ML prediction - model_type: '{prediction_data.get('model_type')}' (length: {len(str(prediction_data.get('model_type', '')))})")
        logger.info(f"🔍 Full prediction data: {prediction_data}")

        # Check if trade exists, create placeholder if not (for testing scenarios)
        trade_id = prediction_data['trade_id']

        # Skip placeholder creation for trade_id = "0" (general predictions)
        if trade_id != "0" and not self._trade_exists(trade_id):
            logger.info(f"📝 Creating placeholder trade for ML prediction: {trade_id}")
            self._create_placeholder_trade(prediction_data)

        query = """
        INSERT INTO ml_predictions (
            trade_id, model_name, model_type, prediction_probability,
            confidence_score, features_json, symbol, timeframe, strategy_name, strategy_version
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """

        # Handle features_json - it can be either a string (from EA) or dict (from tests)
        features_json = prediction_data.get('features_json', '{}')
        if isinstance(features_json, dict):
            features_json = json.dumps(features_json)
        elif not isinstance(features_json, str):
            features_json = '{}'

        params = (
            prediction_data['trade_id'],
            prediction_data['model_name'],
            prediction_data['model_type'],
            prediction_data['prediction_probability'],
            prediction_data['confidence_score'],
            features_json,
            prediction_data.get('symbol'),
            prediction_data.get('timeframe'),
            prediction_data.get('strategy_name'),
            prediction_data.get('strategy_version')
        )

        return self.execute_insert(query, params)

    def insert_market_conditions(self, conditions_data: Dict[str, Any]) -> int:
        """Insert market conditions data"""
        # Check if trade exists, create placeholder if not (for testing scenarios)
        trade_id = conditions_data['trade_id']

        # Skip placeholder creation for trade_id = "0" (general market conditions)
        if trade_id != "0" and not self._trade_exists(trade_id):
            logger.info(f"📝 Creating placeholder trade for market conditions: {trade_id}")
            self._create_placeholder_trade(conditions_data)

        query = """
        INSERT INTO market_conditions (
            trade_id, symbol, timeframe, rsi, stoch_main, stoch_signal,
            macd_main, macd_signal, bb_upper, bb_lower, cci, momentum,
            williams_r, force_index, volume_ratio, price_change, volatility, spread, session_hour,
            day_of_week, month
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
            %s, %s, %s, %s, %s
        )
        """

        params = (
            conditions_data['trade_id'],
            conditions_data['symbol'],
            conditions_data['timeframe'],
            conditions_data.get('rsi'),
            conditions_data.get('stoch_main'),
            conditions_data.get('stoch_signal'),
            conditions_data.get('macd_main'),
            conditions_data.get('macd_signal'),
            conditions_data.get('bb_upper'),
            conditions_data.get('bb_lower'),
            conditions_data.get('cci'),
            conditions_data.get('momentum'),
            conditions_data.get('williams_r'),
            conditions_data.get('force_index'),
            conditions_data.get('volume_ratio'),
            conditions_data.get('price_change'),
            conditions_data.get('volatility'),
            conditions_data.get('spread'),
            conditions_data.get('session_hour'),
            conditions_data.get('day_of_week'),
            conditions_data.get('month')
        )

        return self.execute_insert(query, params)

    def _trade_exists(self, trade_id: str) -> bool:
        """Check if a trade exists in the database"""
        query = "SELECT COUNT(*) as count FROM trades WHERE trade_id = %s"
        result = self.execute_query(query, (trade_id,))
        return result[0]['count'] > 0 if result else False

    def _create_placeholder_trade(self, data: Dict[str, Any]) -> str:
        """Create a placeholder trade record for testing scenarios"""
        from datetime import datetime

        # Extract trade_id and basic info from the data
        trade_id = data['trade_id']

        # Prevent creating placeholder trades with trade_id = "0"
        if trade_id == "0":
            logger.warning("⚠️ Skipping placeholder trade creation for trade_id = '0'")
            return "0"

        # Extract data with fallbacks
        symbol = data.get('symbol', 'UNKNOWN')
        timeframe = data.get('timeframe', 'H1')
        strategy_name = data.get('strategy', data.get('strategy_name', 'ML_Testing_EA'))
        strategy_version = data.get('strategy_version', '1.00')
        direction = data.get('direction', 'TEST')
        entry_price = data.get('entry_price', 0.0)
        stop_loss = data.get('stop_loss', 0.0)
        take_profit = data.get('take_profit', 0.0)
        lot_size = data.get('lot_size', 0.0)
        status = data.get('status', 'OPEN')

        # Convert trade_time to entry_time if available
        entry_time = None
        if 'trade_time' in data:
            try:
                # Convert Unix timestamp to datetime
                entry_time = datetime.fromtimestamp(int(data['trade_time'])).isoformat()
            except (ValueError, TypeError):
                entry_time = datetime.now().isoformat()
        else:
            entry_time = datetime.now().isoformat()

        # Create trade data using actual values when available
        trade_data = {
            'trade_id': trade_id,
            'symbol': symbol,
            'timeframe': timeframe,
            'direction': direction,
            'entry_price': entry_price,
            'exit_price': None,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'lot_size': lot_size,
            'profit_loss': None,
            'profit_loss_pips': None,
            'entry_time': entry_time,
            'exit_time': None,
            'duration_seconds': None,
            'status': status,
            'strategy_name': strategy_name,
            'strategy_version': strategy_version,
            'account_id': 'TEST_ACCOUNT'
        }

        # Insert the trade
        return self.insert_trade(trade_data)

    def update_trade_exit(self, trade_id: str, exit_data: Dict[str, Any]) -> int:
        """Update trade with exit information"""
        # First, get the stop loss and take profit from ml_trade_logs if available
        stop_loss = None
        take_profit = None

        try:
            ml_log_query = "SELECT stop_loss, take_profit FROM ml_trade_logs WHERE trade_id = %s LIMIT 1"
            ml_log_result = self.execute_query(ml_log_query, (trade_id,))
            if ml_log_result:
                stop_loss = ml_log_result[0]['stop_loss']
                take_profit = ml_log_result[0]['take_profit']
        except Exception as e:
            logger.warning(f"⚠️ Could not fetch SL/TP from ml_trade_logs for {trade_id}: {e}")

        # Calculate duration in seconds if not provided
        duration_seconds = exit_data.get('duration_seconds')
        if duration_seconds is None and exit_data.get('exit_time'):
            try:
                # Get the original trade time from ml_trade_logs
                trade_time_query = "SELECT trade_time FROM ml_trade_logs WHERE trade_id = %s"
                trade_time_result = self.execute_query(trade_time_query, (trade_id,))

                if trade_time_result:
                    original_trade_time = trade_time_result[0]['trade_time']
                    exit_time_unix = exit_data['exit_time']
                    if isinstance(exit_time_unix, (int, float)) and isinstance(original_trade_time, (int, float)):
                        duration_seconds = int(exit_time_unix) - int(original_trade_time)
                        logger.info(f"✅ Calculated duration for trade {trade_id}: {duration_seconds} seconds")
            except Exception as e:
                logger.warning(f"⚠️ Could not calculate duration for trade {trade_id}: {e}")

        query = """
        UPDATE trades SET
            exit_price = %s,
            profit_loss = %s,
            profit_loss_pips = %s,
            exit_time = %s,
            duration_seconds = %s,
            status = %s,
            stop_loss = COALESCE(%s, stop_loss),
            take_profit = COALESCE(%s, take_profit)
        WHERE trade_id = %s
        """

        # Convert Unix timestamp to datetime format
        exit_time = datetime.fromtimestamp(exit_data['exit_time']) if isinstance(exit_data['exit_time'], (int, float)) else exit_data['exit_time']

        params = (
            exit_data['exit_price'],
            exit_data['profit_loss'],
            exit_data.get('profit_loss_pips'),
            exit_time,
            duration_seconds,
            exit_data['status'],
            stop_loss,
            take_profit,
            trade_id
        )

        return self.execute_update(query, params)

    def get_trade_performance(self, strategy_name: str, strategy_version: str,
                            symbol: str, timeframe: str,
                            start_date: date, end_date: date) -> Dict[str, Any]:
        """Get performance statistics for a strategy"""
        query = """
        SELECT
            COUNT(*) as total_trades,
            SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
            SUM(CASE WHEN profit_loss < 0 THEN 1 ELSE 0 END) as losing_trades,
            SUM(CASE WHEN profit_loss > 0 THEN profit_loss ELSE 0 END) as total_profit,
            SUM(CASE WHEN profit_loss < 0 THEN ABS(profit_loss) ELSE 0 END) as total_loss,
            SUM(profit_loss) as net_profit,
            AVG(CASE WHEN profit_loss > 0 THEN profit_loss ELSE NULL END) as avg_win,
            AVG(CASE WHEN profit_loss < 0 THEN profit_loss ELSE NULL END) as avg_loss,
            MAX(profit_loss) as largest_win,
            MIN(profit_loss) as largest_loss
        FROM trades
        WHERE strategy_name = %s
        AND strategy_version = %s
        AND symbol = %s
        AND timeframe = %s
        AND entry_time >= %s
        AND entry_time <= %s
        AND status = 'CLOSED'
        """

        result = self.execute_query(query, (strategy_name, strategy_version,
                                           symbol, timeframe, start_date, end_date))

        if result and result[0]['total_trades'] > 0:
            data = result[0]
            data['win_rate'] = (data['winning_trades'] / data['total_trades']) * 100
            data['profit_factor'] = (data['total_profit'] / data['total_loss']) if data['total_loss'] > 0 else 0
            return data

        return {
            'total_trades': 0,
            'winning_trades': 0,
            'losing_trades': 0,
            'total_profit': 0,
            'total_loss': 0,
            'net_profit': 0,
            'win_rate': 0,
            'profit_factor': 0,
            'avg_win': 0,
            'avg_loss': 0,
            'largest_win': 0,
            'largest_loss': 0
        }

    def get_ml_model_performance(self, model_name: str, model_type: str,
                               symbol: str, timeframe: str,
                               start_date: date, end_date: date) -> Dict[str, Any]:
        """Get ML model performance statistics"""
        query = """
        SELECT
            COUNT(*) as total_predictions,
            AVG(prediction_probability) as avg_prediction_probability,
            AVG(confidence_score) as avg_confidence_score
        FROM ml_predictions mp
        JOIN trades t ON mp.trade_id = t.trade_id
        WHERE mp.model_name = %s
        AND mp.model_type = %s
        AND t.symbol = %s
        AND t.timeframe = %s
        AND t.entry_time >= %s
        AND t.entry_time <= %s
        AND t.status = 'CLOSED'
        """

        result = self.execute_query(query, (model_name, model_type, symbol,
                                           timeframe, start_date, end_date))

        if result and result[0]['total_predictions'] > 0:
            return result[0]

        return {
            'total_predictions': 0,
            'avg_prediction_probability': 0,
            'avg_confidence_score': 0
        }

# Global database instance
analytics_db = AnalyticsDatabase()
