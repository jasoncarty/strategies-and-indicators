#!/usr/bin/env python3
"""
Flask web server for receiving analytics data from MT5 EA
"""
import os
from flask import Flask, request, jsonify
from flask_cors import CORS
import logging
import json
from datetime import datetime
from pathlib import Path
from database.manager import analytics_db

# Setup logging
import logging.handlers
from pathlib import Path

# Create logs directory if it doesn't exist
logs_dir = Path(__file__).parent / 'logs'
logs_dir.mkdir(exist_ok=True)

# Setup file handler for app.log
file_handler = logging.handlers.RotatingFileHandler(
    logs_dir / 'app.log',
    maxBytes=10*1024*1024,  # 10MB
    backupCount=5
)
file_handler.setLevel(logging.INFO)
file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))

# Setup console handler
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))

# Setup logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logger.addHandler(file_handler)
logger.addHandler(console_handler)

# Prevent duplicate logs
logger.propagate = False

app = Flask(__name__)

dashboard_url = os.getenv('DASHBOARD_EXTERNAL_URL', "http://localhost:3000")
# Enable CORS for React dashboard
CORS(app, origins=[dashboard_url])

# Initialize database connection on startup
def initialize_database():
    """Initialize database connection and run migrations if needed"""
    # Skip initialization if in testing mode
    if os.getenv('TESTING') or os.getenv('SKIP_DB_INIT'):
        logger.info("ℹ️ Database initialization skipped (testing mode)")
        return

    try:
        analytics_db.connect()
        logger.info("✅ Database connection initialized on startup")

        # Run migrations if needed
        run_migrations_on_startup()

    except Exception as e:
        logger.warning(f"⚠️ Database initialization failed: {e}")
        logger.info("ℹ️ Database will be initialized on first request")
        # Don't retry or sleep - just log and continue

def run_migrations_on_startup():
    """Run database migrations on startup if needed"""
    try:
        logger.info("🔄 Checking if migrations need to be run...")

        # Check if migration_log table exists
        result = analytics_db.execute_query("SHOW TABLES LIKE 'migration_log'")
        if not result:
            logger.info("📦 Migration log table not found - running all migrations...")
            run_all_migrations()
            return

        # Get all migration files from filesystem
        migrations_dir = Path(__file__).parent / 'database' / 'migrations'
        migration_files = sorted([f.name for f in migrations_dir.glob("*.sql")])

        if not migration_files:
            logger.info("✅ No migration files found - nothing to run")
            return

        logger.info(f"📁 Found {len(migration_files)} migration files: {migration_files}")

        # Get all executed migrations from database
        executed_migrations = analytics_db.execute_query(
            "SELECT filename FROM migration_log WHERE status = 'SUCCESS' ORDER BY filename"
        )
        executed_filenames = [row['filename'] for row in executed_migrations] if executed_migrations else []

        logger.info(f"📋 Found {len(executed_filenames)} executed migrations: {executed_filenames}")

        # Find missing migrations
        missing_migrations = [f for f in migration_files if f not in executed_filenames]

        if missing_migrations:
            logger.info(f"🔄 Found {len(missing_migrations)} missing migrations: {missing_migrations}")
            logger.info("🚀 Running missing migrations...")
            run_all_migrations()
        else:
            logger.info("✅ All migrations are up to date")

    except Exception as e:
        logger.error(f"❌ Failed to check/run migrations: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")

def run_all_migrations():
    """Run all database migrations"""
    try:
        import subprocess
        import sys
        from pathlib import Path

        # Get the path to the migrations directory
        migrations_dir = Path(__file__).parent / 'database'
        run_migrations_script = migrations_dir / 'run_migrations.py'

        if run_migrations_script.exists():
            logger.info(f"🚀 Running migrations from: {run_migrations_script}")

            result = subprocess.run([
                sys.executable, str(run_migrations_script)
            ], capture_output=True, text=True, cwd=str(migrations_dir))

            if result.returncode == 0:
                logger.info("✅ All migrations completed successfully")
            else:
                logger.error(f"❌ Migration failed with return code: {result.returncode}")
                logger.error(f"Migration stdout: {result.stdout}")
                logger.error(f"Migration stderr: {result.stderr}")
        else:
            logger.error(f"❌ Migration script not found: {run_migrations_script}")

    except Exception as e:
        logger.error(f"❌ Failed to run migrations: {e}")

def validate_trade_id(data, endpoint_name):
    """Validate trade_id in request data"""
    if not data.get('trade_id'):
        logger.error(f"❌ Missing trade_id in {endpoint_name}")
        return False, "trade_id is required"

    if data['trade_id'] == 0 or data['trade_id'] == '0' or data['trade_id'] == '':
        logger.error(f"❌ Invalid trade_id in {endpoint_name}: {data['trade_id']}")
        return False, "trade_id cannot be 0 or empty"

    return True, None

def validate_required_fields(data, required_fields, endpoint_name):
    """Validate required fields in request data"""
    missing_fields = [field for field in required_fields if field not in data or data[field] is None]
    if missing_fields:
        logger.error(f"❌ Missing required fields in {endpoint_name}: {missing_fields}")
        return False, f"Missing required fields: {missing_fields}"

    return True, None

# Initialize database when app starts (only when not in testing mode)
if not os.getenv('TESTING') and not os.getenv('SKIP_DB_INIT'):
    try:
        initialize_database()
    except Exception as e:
        logger.warning(f"⚠️ Database initialization skipped: {e}")
        logger.info("ℹ️ Database will be initialized on first request")
else:
    logger.info("ℹ️ Database initialization skipped (testing mode or SKIP_DB_INIT set)")

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    logger.info(f"🏥 Health check request from {request.remote_addr}")
    logger.info(f"   Method: {request.method}")
    logger.info(f"   Headers: {dict(request.headers)}")

    # Test database connection
    db_status = "unknown"
    try:
        if analytics_db.is_connected():
            db_status = "connected"
        else:
            logger.warning("⚠️ Database connection unhealthy during health check")
            # Attempt to reconnect or initialize if not in testing mode
            if not os.getenv('TESTING') and not os.getenv('SKIP_DB_INIT'):
                try:
                    analytics_db._ensure_connection()
                    if analytics_db.is_connected():
                        db_status = "connected"
                        logger.info("✅ Database connection restored during health check")
                    else:
                        db_status = "disconnected"
                        logger.error("❌ Failed to restore database connection")
                except Exception as e:
                    logger.error(f"❌ Failed to restore database connection: {e}")
                    db_status = "error"
            else:
                db_status = "testing_mode"
                logger.info("ℹ️ Database connection check skipped (testing mode)")
    except Exception as e:
        logger.error(f"❌ Database health check failed: {e}")
        db_status = "error"

    # Simple health check - service is running
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "database": db_status,
        "message": "Service is running"
    }), 200

@app.route('/analytics/trade', methods=['POST'])
def record_trade():
    """Record trade entry data"""

    try:
        logger.info(f"📥 Received trade request from {request.remote_addr}")
        logger.info(f"   Headers: {dict(request.headers)}")

        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in trade request")
            return jsonify({"error": "No data provided"}), 400

        logger.info(f"📊 Trade data received: {json.dumps(data, indent=2)}")

        # Insert trade data
        logger.info("💾 Attempting to insert trade data into database...")
        trade_id = analytics_db.insert_trade(data)
        logger.info(f"✅ Trade recorded successfully with ID: {trade_id}")

        return jsonify({
            "status": "success",
            "trade_id": trade_id,
            "message": "Trade recorded successfully"
        }), 201

    except Exception as e:
        logger.error(f"❌ Error recording trade: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        logger.error(f"   Request data: {request.get_data(as_text=True)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/ml_prediction', methods=['POST'])
def record_ml_prediction():
    """Record ML prediction data"""

    try:
        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in ML prediction request")
            return jsonify({"error": "No data provided"}), 400

        logger.info(f"🤖 Processing ML prediction: {data.get('model_name', 'unknown')}")

        # Insert ML prediction data
        prediction_id = analytics_db.insert_ml_prediction(data)
        logger.info(f"✅ ML prediction recorded successfully with ID: {prediction_id}")

        return jsonify({
            "status": "success",
            "prediction_id": prediction_id,
            "message": "ML prediction recorded successfully"
        }), 201

    except Exception as e:
        logger.error(f"❌ Error recording ML prediction: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/market_conditions', methods=['POST'])
def record_market_conditions():
    """Record market conditions data"""
    try:
        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in market conditions request")
            return jsonify({"error": "No data provided"}), 400

        logger.info(f"📈 Processing market conditions for: {data.get('symbol', 'unknown')}")

        # Insert market conditions data
        conditions_id = analytics_db.insert_market_conditions(data)
        logger.info(f"✅ Market conditions recorded successfully with ID: {conditions_id}")

        return jsonify({
            "status": "success",
            "conditions_id": conditions_id,
            "message": "Market conditions recorded successfully"
        }), 201

    except Exception as e:
        logger.error(f"❌ Error recording market conditions: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/trade_exit', methods=['POST'])
def record_trade_exit():
    try:
        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in trade exit request")
            return jsonify({"error": "No data provided"}), 400

        logger.info(f"📊 Processing trade exit: {data.get('trade_id', 'unknown')}")

        # Update trade with exit data
        updated_count = analytics_db.update_trade_exit(data['trade_id'], data)
        logger.info(f"✅ Trade exit recorded successfully, updated {updated_count} records")

        return jsonify({
            "status": "success",
            "updated_count": updated_count,
            "message": "Trade exit recorded successfully"
        }), 200

    except Exception as e:
        logger.error(f"❌ Error recording trade exit: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/batch', methods=['POST'])
def record_batch():
    """Record multiple analytics records in one request"""

    try:
        # Debug: Log the raw request data
        logger.info(f"🔍 Raw request data length: {len(request.get_data())}")
        logger.info(f"🔍 Request content type: {request.content_type}")

        # Get the raw data for debugging
        raw_data = request.get_data(as_text=True)
        logger.info(f"🔍 Raw request data (first 500 chars): {raw_data[:500]}")

        # Also log the end of the data to see ml_prediction records
        if len(raw_data) > 500:
            logger.info(f"🔍 Raw request data (last 500 chars): {raw_data[-500:]}")

        # Try to parse JSON with better error handling
        try:
            data = request.get_json()
        except Exception as json_error:
            logger.error(f"❌ JSON parsing failed: {json_error}")
            logger.error(f"🔍 Raw data (first 1000 chars): {raw_data[:1000]}")
            logger.error(f"🔍 Raw data length: {len(raw_data)}")
            # Try to find the problematic character
            if len(raw_data) > 183:
                logger.error(f"🔍 Character at position 183: '{raw_data[183]}' (ord: {ord(raw_data[183])})")
                logger.error(f"🔍 Characters around position 183: '{raw_data[180:190]}'")
            return jsonify({"error": f"Invalid JSON format: {json_error}"}), 400
        if not data or 'records' not in data:
            logger.error("❌ No records provided in batch request")
            return jsonify({"error": "No records provided"}), 400

        logger.info(f"📦 Processing batch of {len(data['records'])} records")

        results = []
        for i, record in enumerate(data['records']):
            try:
                record_type = record.get('type')
                record_data = record.get('data', {})

                logger.info(f"   Processing record {i+1}/{len(data['records'])}: {record_type}")

                if record_type == 'ml_prediction':
                    # Log the ml_prediction data for debugging
                    logger.info(f"     🔍 ML prediction data: {record_data}")
                    prediction_id = analytics_db.insert_ml_prediction(record_data)
                    results.append({"type": "ml_prediction", "id": prediction_id, "status": "success"})
                    logger.info(f"     ✅ ML prediction recorded with ID: {prediction_id}")
                elif record_type == 'market_conditions':
                    conditions_id = analytics_db.insert_market_conditions(record_data)
                    results.append({"type": "market_conditions", "id": conditions_id, "status": "success"})
                    logger.info(f"     ✅ Market conditions recorded with ID: {conditions_id}")
                else:
                    results.append({"type": record_type, "status": "error", "message": f"Unsupported record type: {record_type}. Only 'ml_prediction' and 'market_conditions' are supported in batch requests."})
                    logger.warning(f"     ⚠️ Unsupported record type in batch: {record_type}. Use dedicated endpoints for trade data.")

            except Exception as e:
                results.append({"type": record.get('type', 'unknown'), "status": "error", "message": str(e)})
                logger.error(f"     ❌ Error processing record {i+1}: {e}")

        logger.info(f"✅ Batch processing completed: {len(data['records'])} records processed")

        return jsonify({
            "status": "success",
            "processed": len(data['records']),
            "results": results
        }), 200

    except Exception as e:
        logger.error(f"❌ Error processing batch: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/ml_trade_log', methods=['POST'])
def record_ml_trade_log():
    """Record trade data for ML retraining"""
    try:
        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in ML trade log request")
            return jsonify({"error": "No data provided"}), 400

        # Validate required fields
        required_fields = ['trade_id', 'strategy', 'symbol', 'timeframe', 'direction',
                           'entry_price', 'stop_loss', 'take_profit', 'lot_size',
                           'ml_prediction', 'ml_confidence', 'ml_model_type',
                           'ml_model_key', 'trade_time', 'timestamp']

        is_valid, error_msg = validate_required_fields(data, required_fields, "ML trade log")
        if not is_valid:
            return jsonify({"error": error_msg}), 400

        # Validate trade_id
        is_valid, error_msg = validate_trade_id(data, "ML trade log")
        if not is_valid:
            return jsonify({"error": error_msg}), 400

        logger.info(f"📊 Processing ML trade log for trade_id: {data['trade_id']}, strategy: {data.get('strategy', 'unknown')}")

        # Insert ML trade log data
        trade_log_id = analytics_db.insert_ml_trade_log(data)
        logger.info(f"✅ ML trade log recorded successfully with ID: {trade_log_id}")

        return jsonify({
            "status": "success",
            "trade_log_id": trade_log_id,
            "message": "ML trade log recorded successfully"
        }), 201

    except Exception as e:
        logger.error(f"❌ Error recording ML trade log: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/ml_trade_close', methods=['POST'])
def record_ml_trade_close():
    """Record trade close data for ML retraining"""
    try:
        data = request.get_json()
        if not data:
            logger.error("❌ No JSON data provided in ML trade close request")
            return jsonify({"error": "No data provided"}), 400

        # Validate required fields
        required_fields = ['trade_id', 'strategy', 'symbol', 'timeframe', 'close_price',
                           'profit_loss', 'profit_loss_pips', 'close_time', 'exit_reason',
                           'status', 'success', 'timestamp']

        is_valid, error_msg = validate_required_fields(data, required_fields, "ML trade close")
        if not is_valid:
            return jsonify({"error": error_msg}), 400

        # Validate trade_id
        is_valid, error_msg = validate_trade_id(data, "ML trade close")
        if not is_valid:
            return jsonify({"error": error_msg}), 400

        logger.info(f"📊 Processing ML trade close for trade_id: {data['trade_id']}, strategy: {data.get('strategy', 'unknown')}")

        # Insert ML trade close data
        trade_close_id = analytics_db.insert_ml_trade_close(data)
        logger.info(f"✅ ML trade close recorded successfully with ID: {trade_close_id}")

        return jsonify({
            "status": "success",
            "trade_close_id": trade_close_id,
            "message": "ML trade close recorded successfully"
        }), 201

    except Exception as e:
        logger.error(f"❌ Error recording ML trade close: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/trades', methods=['GET'])
def get_trades():
    """Get trade data for retraining"""
    try:
        # Get query parameters
        symbol = request.args.get('symbol')
        timeframe = request.args.get('timeframe')
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')

        if not all([symbol, timeframe, start_date, end_date]):
            return jsonify({"error": "Missing required parameters: symbol, timeframe, start_date, end_date"}), 400

        logger.info(f"📊 Retrieving trades for {symbol} {timeframe} from {start_date} to {end_date}")

        # Query database for trades
        analytics_db.connect()

        query = """
        SELECT ml.*
        FROM ml_trade_logs ml
        WHERE ml.symbol = %s
        AND ml.timeframe = %s
        AND ml.trade_time >= UNIX_TIMESTAMP(%s)
        AND ml.trade_time <= UNIX_TIMESTAMP(%s)
        AND ml.status = 'CLOSED'
        ORDER BY ml.trade_time DESC
        """

        # Add time to the end date to include the full day
        end_date_with_time = f"{end_date} 23:59:59"

        params = (symbol, timeframe, start_date, end_date_with_time)

        result = analytics_db.execute_query(query, params)

        if result:
            logger.info(f"✅ Retrieved {len(result)} trades")
            return jsonify(result), 200
        else:
            logger.info(f"📭 No trades found for {symbol} {timeframe}")
            return jsonify([]), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving trades: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/dashboard/trades', methods=['GET'])
def get_dashboard_trades():
    """Get trades for dashboard display - more flexible parameters"""
    try:
        # Get query parameters with defaults
        symbol = request.args.get('symbol')
        timeframe = request.args.get('timeframe')
        status = request.args.get('status', 'CLOSED')
        limit = int(request.args.get('limit', 100))
        offset = int(request.args.get('offset', 0))

        logger.info(f"📊 Retrieving dashboard trades - Symbol: {symbol}, Timeframe: {timeframe}, Status: {status}, Limit: {limit}")

        # Query database for trades
        analytics_db.connect()

        # Build dynamic query based on provided parameters
        query_parts = ["SELECT * FROM ml_trade_logs WHERE 1=1"]
        params = []

        # Exclude RANDOM_MODEL trades (test data) and invalid trade IDs
        query_parts.append("AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')")
        query_parts.append("AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL")
        query_parts.append("AND strategy != 'TestStrategy'")

        if symbol:
            query_parts.append("AND symbol = %s")
            params.append(symbol)

        if timeframe:
            query_parts.append("AND timeframe = %s")
            params.append(timeframe)

        if status:
            query_parts.append("AND status = %s")
            params.append(status)

        # Add ordering and pagination
        query_parts.append("ORDER BY close_time DESC")
        query_parts.append("LIMIT %s OFFSET %s")
        params.extend([limit, offset])

        query = " ".join(query_parts)
        logger.info(f"🔍 Query: {query}")
        logger.info(f"🔍 Params: {params}")
        result = analytics_db.execute_query(query, params)

        if result:
            # Transform the data to match dashboard expectations
            transformed_trades = []
            for row in result:
                # Convert Unix timestamp to datetime string
                entry_time = datetime.fromtimestamp(row['trade_time']).isoformat() if row['trade_time'] else None
                exit_time = datetime.fromtimestamp(row['close_time']).isoformat() if row['close_time'] else None

                # Calculate duration in seconds
                duration_seconds = None
                if entry_time and exit_time:
                    duration_seconds = int((datetime.fromtimestamp(row['close_time']) - datetime.fromtimestamp(row['trade_time'])).total_seconds())

                trade_data = {
                    'id': row['id'],
                    'trade_id': row['trade_id'],
                    'symbol': row['symbol'],
                    'timeframe': row['timeframe'],
                    'direction': row['direction'],
                    'entry_price': float(row['entry_price']),
                    'exit_price': float(row['close_price']) if row['close_price'] else None,
                    'stop_loss': float(row['stop_loss']),
                    'take_profit': float(row['take_profit']),
                    'lot_size': float(row['lot_size']),
                    'profit_loss': float(row['profit_loss']) if row['profit_loss'] else None,
                    'profit_loss_pips': float(row['profit_loss']) if row['profit_loss'] else None,  # Using profit_loss as pips for now
                    'entry_time': entry_time,
                    'exit_time': exit_time,
                    'duration_seconds': duration_seconds,
                    'status': row['status'],
                    'strategy_name': row['strategy'],
                    'strategy_version': '1.00',  # Default version
                    'account_id': 'ML_Testing_EA',  # Default account ID
                    'created_at': row['created_at'].isoformat() if row['created_at'] else None,
                    'updated_at': row['updated_at'].isoformat() if row['updated_at'] else None,
                }
                transformed_trades.append(trade_data)

            logger.info(f"✅ Retrieved and transformed {len(transformed_trades)} dashboard trades")
            return jsonify(transformed_trades), 200
        else:
            logger.info(f"📭 No dashboard trades found")
            return jsonify([]), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving dashboard trades: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/ml_training_data', methods=['GET'])
def get_ml_training_data():
    """Get combined trade and feature data for ML training"""
    try:
        # Get query parameters
        symbol = request.args.get('symbol')
        timeframe = request.args.get('timeframe')
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')

        if not all([symbol, timeframe, start_date, end_date]):
            return jsonify({"error": "Missing required parameters: symbol, timeframe, start_date, end_date"}), 400

        logger.info(f"🤖 Retrieving ML training data for {symbol} {timeframe} from {start_date} to {end_date}")

        # Query database for combined trade and feature data
        analytics_db.connect()

        query = """
        SELECT
            ml.trade_id,
            ml.symbol,
            ml.timeframe,
            ml.entry_price,
            ml.close_price as exit_price,
            ml.stop_loss,
            ml.take_profit,
            ml.lot_size,
            ml.profit_loss,
            ml.profit_loss as profit_loss_pips,
            ml.trade_time,
            ml.close_time,
            ml.status,
            ml.strategy as strategy_name,
            '1.00' as strategy_version,
            ml.features_json,
            ml.ml_prediction as prediction_probability,
            ml.ml_confidence as confidence_score
        FROM ml_trade_logs ml
        WHERE ml.symbol = %s
        AND ml.timeframe = %s
        AND ml.trade_time >= UNIX_TIMESTAMP(%s)
        AND ml.trade_time <= UNIX_TIMESTAMP(%s)
        AND ml.status = 'CLOSED'
        AND ml.features_json IS NOT NULL
        AND ml.features_json != ''
        AND ml.ml_model_key NOT IN ('test_model')
        AND ml.trade_id != '0' AND ml.trade_id != '' AND ml.trade_id IS NOT NULL
        AND ml.strategy != 'TestStrategy'
        ORDER BY ml.trade_time DESC
        """

        # Add time to the end date to include the full day
        end_date_with_time = f"{end_date} 23:59:59"

        params = (symbol, timeframe, start_date, end_date_with_time)

        result = analytics_db.execute_query(query, params)

        if result:
            # Process the results to extract features from JSON
            training_data = []
            for row in result:
                try:
                    # Parse features from JSON
                    import json
                    features_json = row.get('features_json', '{}')
                    if features_json and features_json != '{}':
                        features = json.loads(features_json)

                        # Create training data entry
                        training_entry = {
                            'trade_id': row['trade_id'],
                            'symbol': row['symbol'],
                            'timeframe': row['timeframe'],
                            'entry_price': float(row['entry_price']),
                            'exit_price': float(row['exit_price']) if row['exit_price'] else 0.0,
                            'stop_loss': float(row['stop_loss']) if row['stop_loss'] else 0.0,
                            'take_profit': float(row['take_profit']) if row['take_profit'] else 0.0,
                            'lot_size': float(row['lot_size']),
                            'profit_loss': float(row['profit_loss']) if row['profit_loss'] else 0.0,
                            'profit_loss_pips': float(row['profit_loss_pips']) if row['profit_loss_pips'] else 0.0,
                            'trade_time': int(row['trade_time']) if row['trade_time'] else 0,
                            'close_time': int(row['close_time']) if row['close_time'] else 0,
                            'status': row['status'],
                            'strategy_name': row['strategy_name'],
                            'strategy_version': row['strategy_version'],
                            'features': features,
                            'prediction_probability': float(row['prediction_probability']) if row['prediction_probability'] else 0.0,
                            'confidence_score': float(row['confidence_score']) if row['confidence_score'] else 0.0
                        }
                        training_data.append(training_entry)
                except Exception as e:
                    logger.warning(f"⚠️ Skipping trade {row.get('trade_id', 'unknown')} due to JSON parsing error: {e}")
                    continue

            logger.info(f"✅ Retrieved {len(training_data)} training data entries")
            return jsonify(training_data), 200
        else:
            logger.info(f"📭 No training data found for {symbol} {timeframe}")
            return jsonify([]), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving ML training data: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/summary', methods=['GET'])
def get_summary():
    try:
        analytics_db.connect()
        logger.info("   🔗 Connected to analytics database")

        # Get basic statistics
        logger.info("   📊 Executing summary query...")
        result = analytics_db.execute_query("""
            SELECT
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                SUM(CASE WHEN profit_loss < 0 THEN 1 ELSE 0 END) as losing_trades,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
        """)

        summary = {}
        if result:
            stats = result[0]
            summary = {
                "total_trades": stats['total_trades'],
                "winning_trades": stats['winning_trades'],
                "losing_trades": stats['losing_trades'],
                "win_rate": (stats['winning_trades'] / stats['total_trades'] * 100) if stats['total_trades'] > 0 else 0,
                "avg_profit_loss": float(stats['avg_profit_loss']) if stats['avg_profit_loss'] else 0,
                "total_profit_loss": float(stats['total_profit_loss']) if stats['total_profit_loss'] else 0
            }
            logger.info(f"   ✅ Summary generated: {summary}")
        else:
            logger.warning("   ⚠️ No summary data found")

        return jsonify(summary), 200

    except Exception as e:
        logger.error(f"❌ Error getting summary: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/ml_performance', methods=['GET'])
def get_ml_performance():
    """Get ML performance metrics for dashboard"""
    try:
        analytics_db.connect()
        logger.info("📊 Retrieving ML performance metrics")

        # Get ML performance summary
        result = analytics_db.execute_query("""
            SELECT
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                SUM(CASE WHEN profit_loss < 0 THEN 1 ELSE 0 END) as incorrect_predictions,
                AVG(ml_prediction) as avg_prediction_probability,
                AVG(ml_confidence) as avg_confidence_score,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                AVG(CASE WHEN profit_loss > 0 THEN profit_loss END) as avg_win,
                AVG(CASE WHEN profit_loss < 0 THEN profit_loss END) as avg_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
        """)

        # Get model performance breakdown
        model_performance = analytics_db.execute_query("""
            SELECT
                ml_model_key,
                ml_model_type,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(ml_prediction) as avg_prediction,
                AVG(ml_confidence) as avg_confidence,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY ml_model_key, ml_model_type
            ORDER BY total_trades DESC
        """)

        # Get confidence vs accuracy correlation
        confidence_accuracy = analytics_db.execute_query("""
            SELECT
                ROUND(ml_confidence * 10) / 10 as confidence_bucket,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(profit_loss) as avg_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY ROUND(ml_confidence * 10) / 10
            ORDER BY confidence_bucket
        """)

        ml_performance = {}
        if result and len(result) > 0:
            stats = result[0]

            total_predictions = int(stats.get('total_predictions', 0) or 0)
            correct_predictions = int(stats.get('correct_predictions', 0) or 0)
            incorrect_predictions = int(stats.get('incorrect_predictions', 0) or 0)

            ml_performance = {
                "total_predictions": total_predictions,
                "correct_predictions": correct_predictions,
                "incorrect_predictions": incorrect_predictions,
                "accuracy": (correct_predictions / total_predictions * 100) if total_predictions > 0 else 0,
                "avg_prediction_probability": float(stats.get('avg_prediction_probability', 0) or 0),
                "avg_confidence_score": float(stats.get('avg_confidence_score', 0) or 0),
                "avg_profit_loss": float(stats.get('avg_profit_loss', 0) or 0),
                "total_profit_loss": float(stats.get('total_profit_loss', 0) or 0),
                "avg_win": float(stats.get('avg_win', 0) or 0),
                "avg_loss": float(stats.get('avg_loss', 0) or 0),
                "model_performance": model_performance if model_performance else [],
                "confidence_accuracy": confidence_accuracy if confidence_accuracy else []
            }

            logger.info(f"✅ Retrieved ML performance metrics: {total_predictions} predictions, {correct_predictions} correct")
        else:
            ml_performance = {
                "total_predictions": 0,
                "correct_predictions": 0,
                "incorrect_predictions": 0,
                "accuracy": 0,
                "avg_prediction_probability": 0,
                "avg_confidence_score": 0,
                "avg_profit_loss": 0,
                "total_profit_loss": 0,
                "avg_win": 0,
                "avg_loss": 0,
                "model_performance": [],
                "confidence_accuracy": []
            }

            logger.warning("⚠️ No ML performance data found")

        return jsonify(ml_performance), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving ML performance: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/ml_predictions', methods=['GET'])
def get_ml_predictions():
    """Get detailed ML prediction metrics for dedicated analysis"""
    try:
        analytics_db.connect()
        logger.info("📊 Retrieving detailed ML prediction metrics")

        # Get prediction accuracy by model type (BUY/SELL)
        prediction_by_type = analytics_db.execute_query("""
            SELECT
                ml_model_type,
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                AVG(ml_prediction) as avg_prediction_probability,
                AVG(ml_confidence) as avg_confidence_score,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                AVG(CASE WHEN profit_loss > 0 THEN profit_loss END) as avg_win,
                AVG(CASE WHEN profit_loss < 0 THEN profit_loss END) as avg_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY ml_model_type
            ORDER BY total_predictions DESC
        """)

        # Get prediction accuracy by symbol
        prediction_by_symbol = analytics_db.execute_query("""
            SELECT
                symbol,
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                AVG(ml_prediction) as avg_prediction_probability,
                AVG(ml_confidence) as avg_confidence_score,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY symbol
            HAVING total_predictions >= 5
            ORDER BY total_predictions DESC
        """)

        # Get prediction accuracy by timeframe
        prediction_by_timeframe = analytics_db.execute_query("""
            SELECT
                timeframe,
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                AVG(ml_prediction) as avg_prediction_probability,
                AVG(ml_confidence) as avg_confidence_score,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY timeframe
            HAVING total_predictions >= 5
            ORDER BY total_predictions DESC
        """)

        # Get prediction accuracy by confidence buckets (more granular)
        confidence_buckets = analytics_db.execute_query("""
            SELECT
                CASE
                    WHEN ml_confidence < 0.3 THEN '0.0-0.3'
                    WHEN ml_confidence < 0.4 THEN '0.3-0.4'
                    WHEN ml_confidence < 0.5 THEN '0.4-0.5'
                    WHEN ml_confidence < 0.6 THEN '0.5-0.6'
                    WHEN ml_confidence < 0.7 THEN '0.6-0.7'
                    WHEN ml_confidence < 0.8 THEN '0.7-0.8'
                    WHEN ml_confidence < 0.9 THEN '0.8-0.9'
                    ELSE '0.9-1.0'
                END as confidence_range,
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                AVG(ml_confidence) as avg_confidence,
                AVG(ml_prediction) as avg_prediction,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY confidence_range
            HAVING total_predictions >= 3
            ORDER BY avg_confidence
        """)

        # Get recent prediction performance (last 100 trades)
        recent_performance = analytics_db.execute_query("""
            SELECT
                DATE(FROM_UNIXTIME(trade_time)) as trade_date,
                COUNT(*) as total_predictions,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as correct_predictions,
                AVG(ml_confidence) as avg_confidence,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY trade_date
            ORDER BY trade_date DESC
            LIMIT 30
        """)

        ml_predictions = {
            "prediction_by_type": prediction_by_type if prediction_by_type else [],
            "prediction_by_symbol": prediction_by_symbol if prediction_by_symbol else [],
            "prediction_by_timeframe": prediction_by_timeframe if prediction_by_timeframe else [],
            "confidence_buckets": confidence_buckets if confidence_buckets else [],
            "recent_performance": recent_performance if recent_performance else []
        }

        logger.info(f"✅ Retrieved detailed ML prediction metrics")
        return jsonify(ml_predictions), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving ML predictions: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model_health', methods=['GET'])
def get_model_health_overview():
    """Get comprehensive model health overview for all models"""
    try:
        analytics_db.connect()
        logger.info("🏥 Retrieving model health overview")

        # Get all unique models
        models = analytics_db.execute_query("""
            SELECT DISTINCT ml_model_key, ml_model_type, symbol, timeframe
            FROM ml_trade_logs
            WHERE ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            ORDER BY ml_model_key
        """)

        if not models:
            return jsonify({"models": [], "summary": "No models found"}), 200

        model_health = []
        total_models = len(models)
        healthy_models = 0
        warning_models = 0
        critical_models = 0

        for model in models:
            model_key = model['ml_model_key']

            # Get recent performance (last 30 days)
            recent_performance = analytics_db.execute_query("""
                SELECT
                    COUNT(*) as total_trades,
                    SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                    AVG(ml_confidence) as avg_confidence,
                    AVG(ml_prediction) as avg_prediction,
                    AVG(profit_loss) as avg_profit_loss,
                    SUM(profit_loss) as total_profit_loss,
                    STDDEV(profit_loss) as profit_loss_std
                FROM ml_trade_logs
                WHERE ml_model_key = %s
                AND status = 'CLOSED'
                AND profit_loss IS NOT NULL
                AND trade_time >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
            """, (model_key,))

            if not recent_performance or recent_performance[0]['total_trades'] == 0:
                model_health.append({
                    'model_key': model_key,
                    'model_type': model['ml_model_type'],
                    'symbol': model['symbol'],
                    'timeframe': model['timeframe'],
                    'status': 'no_data',
                    'total_trades': 0,
                    'win_rate': 0,
                    'avg_confidence': 0,
                    'avg_profit_loss': 0,
                    'total_profit_loss': 0,
                    'health_score': 0,
                    'issues': ['No recent trades']
                })
                continue

            perf = recent_performance[0]
            total_trades = perf['total_trades']
            winning_trades = perf['winning_trades']
            win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
            avg_confidence = float(perf['avg_confidence']) if perf['avg_confidence'] else 0
            avg_profit_loss = float(perf['avg_profit_loss']) if perf['avg_profit_loss'] else 0
            total_profit_loss = float(perf['total_profit_loss']) if perf['total_profit_loss'] else 0

            # Calculate health score (0-100)
            health_score = 0
            issues = []

            # Win rate component (40% of score)
            if win_rate >= 60:
                health_score += 40
            elif win_rate >= 50:
                health_score += 30
            elif win_rate >= 40:
                health_score += 20
            elif win_rate >= 30:
                health_score += 10
            else:
                issues.append(f"Low win rate: {win_rate:.1f}%")

            # Profit component (30% of score)
            if avg_profit_loss > 0:
                health_score += 30
            elif avg_profit_loss > -1:
                health_score += 20
            elif avg_profit_loss > -2:
                health_score += 10
            else:
                issues.append(f"High average loss: ${avg_profit_loss:.2f}")

            # Confidence correlation component (30% of score)
            # Check if higher confidence trades perform better
            confidence_analysis = analytics_db.execute_query("""
                SELECT
                    CASE
                        WHEN ml_confidence < 0.5 THEN 'low'
                        ELSE 'high'
                    END as confidence_level,
                    AVG(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as win_rate
                FROM ml_trade_logs
                WHERE ml_model_key = %s
                AND status = 'CLOSED'
                AND profit_loss IS NOT NULL
                AND trade_time >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
                GROUP BY confidence_level
                HAVING COUNT(*) >= 5
            """, (model_key,))

            if len(confidence_analysis) >= 2:
                low_conf = next((x for x in confidence_analysis if x['confidence_level'] == 'low'), None)
                high_conf = next((x for x in confidence_analysis if x['confidence_level'] == 'high'), None)

                if low_conf and high_conf:
                    low_win_rate = float(low_conf['win_rate']) * 100
                    high_win_rate = float(high_conf['win_rate']) * 100

                    if high_win_rate > low_win_rate:
                        health_score += 30
                    elif high_win_rate == low_win_rate:
                        health_score += 15
                    else:
                        health_score += 0
                        issues.append("Higher confidence trades perform worse")
                else:
                    health_score += 15
            else:
                health_score += 15

            # Determine status
            if health_score >= 80:
                status = 'healthy'
                healthy_models += 1
            elif health_score >= 60:
                status = 'warning'
                warning_models += 1
            else:
                status = 'critical'
                critical_models += 1

            model_health.append({
                'model_key': model_key,
                'model_type': model['ml_model_type'],
                'symbol': model['symbol'],
                'timeframe': model['timeframe'],
                'status': status,
                'total_trades': total_trades,
                'win_rate': win_rate,
                'avg_confidence': avg_confidence,
                'avg_profit_loss': avg_profit_loss,
                'total_profit_loss': total_profit_loss,
                'health_score': health_score,
                'issues': issues
            })

        # Sort by health score (worst first)
        model_health.sort(key=lambda x: x['health_score'])

        summary = {
            'total_models': total_models,
            'healthy_models': healthy_models,
            'warning_models': warning_models,
            'critical_models': critical_models,
            'overall_health': (healthy_models / total_models * 100) if total_models > 0 else 0
        }

        result = {
            'summary': summary,
            'models': model_health,
            'timestamp': datetime.now().isoformat()
        }

        logger.info(f"✅ Retrieved health overview for {total_models} models")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving model health: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model/<model_key>/calibration', methods=['GET'])
def get_model_calibration(model_key):
    """Get confidence calibration analysis for a specific model"""
    try:
        analytics_db.connect()
        logger.info(f"🎯 Retrieving confidence calibration for {model_key}")

        # Get query parameters
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')

        # Default to last 90 days if no dates provided
        if not start_date or not end_date:
            from datetime import datetime, timedelta
            end_date = datetime.now().date()
            start_date = end_date - timedelta(days=90)
        else:
            from datetime import datetime
            start_date = datetime.strptime(start_date, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date, '%Y-%m-%d').date()

        # Get confidence buckets with actual vs expected performance
        calibration_data = analytics_db.execute_query("""
            SELECT
                CASE
                    WHEN ml_confidence < 0.1 THEN '0.0-0.1'
                    WHEN ml_confidence < 0.2 THEN '0.1-0.2'
                    WHEN ml_confidence < 0.3 THEN '0.2-0.3'
                    WHEN ml_confidence < 0.4 THEN '0.3-0.4'
                    WHEN ml_confidence < 0.5 THEN '0.4-0.5'
                    WHEN ml_confidence < 0.6 THEN '0.5-0.6'
                    WHEN ml_confidence < 0.7 THEN '0.6-0.7'
                    WHEN ml_confidence < 0.8 THEN '0.7-0.8'
                    WHEN ml_confidence < 0.9 THEN '0.8-0.9'
                    ELSE '0.9-1.0'
                END as confidence_bucket,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(ml_confidence) as avg_confidence,
                AVG(ml_prediction) as avg_prediction,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                STDDEV(profit_loss) as profit_loss_std
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY confidence_bucket
            HAVING total_trades >= 3
            ORDER BY confidence_bucket
        """, (model_key, start_date, end_date))

        if not calibration_data:
            return jsonify({
                "error": "No calibration data available for this model",
                "model_key": model_key,
                "date_range": {"start": start_date.isoformat(), "end": end_date.isoformat()}
            }), 404

        # Calculate calibration metrics
        calibration_metrics = []
        total_trades = 0
        total_wins = 0

        for bucket in calibration_data:
            bucket_trades = int(bucket['total_trades'])
            bucket_wins = int(bucket['winning_trades'])
            avg_confidence = float(bucket['avg_confidence']) if bucket['avg_confidence'] else 0

            # Calculate actual win rate
            actual_win_rate = (bucket_wins / bucket_trades) if bucket_trades > 0 else 0

            # Expected win rate should be close to confidence if well-calibrated
            expected_win_rate = avg_confidence

            # Calibration error (difference between expected and actual)
            calibration_error = abs(expected_win_rate - actual_win_rate)

            # Determine if this bucket is well-calibrated
            if calibration_error < 0.1:
                calibration_status = 'well_calibrated'
            elif calibration_error < 0.2:
                calibration_status = 'moderately_calibrated'
            else:
                calibration_status = 'poorly_calibrated'

            total_trades += bucket_trades
            total_wins += bucket_wins

            calibration_metrics.append({
                'confidence_bucket': bucket['confidence_bucket'],
                'total_trades': bucket_trades,
                'winning_trades': bucket_wins,
                'actual_win_rate': actual_win_rate,
                'expected_win_rate': expected_win_rate,
                'calibration_error': calibration_error,
                'calibration_status': calibration_status,
                'avg_confidence': avg_confidence,
                'avg_prediction': float(bucket['avg_prediction']) if bucket['avg_prediction'] else 0,
                'avg_profit_loss': float(bucket['avg_profit_loss']) if bucket['avg_profit_loss'] else 0,
                'total_profit_loss': float(bucket['total_profit_loss']) if bucket['total_profit_loss'] else 0
            })

        # Calculate overall calibration score
        overall_win_rate = (total_wins / total_trades) if total_trades > 0 else 0

        # Calculate weighted average calibration error
        weighted_calibration_error = sum(
            bucket['calibration_error'] * bucket['total_trades']
            for bucket in calibration_metrics
        ) / total_trades if total_trades > 0 else 0

        # Overall calibration score (0-100, higher is better)
        overall_calibration_score = max(0, 100 - (weighted_calibration_error * 100))

        # Determine overall calibration status
        if overall_calibration_score >= 80:
            overall_status = 'well_calibrated'
        elif overall_calibration_score >= 60:
            overall_status = 'moderately_calibrated'
        else:
            overall_status = 'poorly_calibrated'

        # Check for confidence inversion (higher confidence = worse performance)
        confidence_performance_correlation = analytics_db.execute_query("""
            SELECT
                AVG(CASE WHEN ml_confidence < 0.5 THEN
                    CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END
                ELSE NULL END) as low_conf_win_rate,
                AVG(CASE WHEN ml_confidence >= 0.5 THEN
                    CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END
                ELSE NULL END) as high_conf_win_rate
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
        """, (model_key, start_date, end_date))

        confidence_inversion = False
        if confidence_performance_correlation and len(confidence_performance_correlation) > 0:
            low_conf_win_rate = float(confidence_performance_correlation[0]['low_conf_win_rate']) if confidence_performance_correlation[0]['low_conf_win_rate'] else 0
            high_conf_win_rate = float(confidence_performance_correlation[0]['high_conf_win_rate']) if confidence_performance_correlation[0]['high_conf_win_rate'] else 0

            # Check if higher confidence trades perform worse (inversion)
            if high_conf_win_rate < low_conf_win_rate:
                confidence_inversion = True

        result = {
            'model_key': model_key,
            'date_range': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'overall_metrics': {
                'total_trades': total_trades,
                'total_wins': total_wins,
                'overall_win_rate': overall_win_rate,
                'overall_calibration_score': overall_calibration_score,
                'overall_calibration_status': overall_status,
                'weighted_calibration_error': weighted_calibration_error,
                'confidence_inversion_detected': confidence_inversion
            },
            'calibration_buckets': calibration_metrics,
            'timestamp': datetime.now().isoformat()
        }

        logger.info(f"✅ Retrieved calibration data for {model_key}: {overall_calibration_score:.1f}% calibrated")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving calibration data for {model_key}: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model/<model_key>/diagnostics', methods=['GET'])
def get_model_diagnostics(model_key):
    """Get detailed diagnostics for a specific model to identify root causes"""
    try:
        analytics_db.connect()
        logger.info(f"🔍 Retrieving diagnostics for model: {model_key}")

        # Get query parameters
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')

        # Default to last 90 days if no dates provided
        if not start_date or not end_date:
            from datetime import datetime, timedelta
            end_date = datetime.now().date()
            start_date = end_date - timedelta(days=90)
        else:
            from datetime import datetime
            start_date = datetime.strptime(start_date, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date, '%Y-%m-%d').date()

        # 1. Performance by confidence levels
        confidence_analysis = analytics_db.execute_query("""
            SELECT
                CASE
                    WHEN ml_confidence < 0.3 THEN '0.0-0.3'
                    WHEN ml_confidence < 0.4 THEN '0.3-0.4'
                    WHEN ml_confidence < 0.5 THEN '0.4-0.5'
                    WHEN ml_confidence < 0.6 THEN '0.5-0.6'
                    WHEN ml_confidence < 0.7 THEN '0.6-0.7'
                    WHEN ml_confidence < 0.8 THEN '0.7-0.8'
                    WHEN ml_confidence < 0.9 THEN '0.8-0.9'
                    ELSE '0.9-1.0'
                END as confidence_bucket,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                MIN(profit_loss) as min_profit_loss,
                MAX(profit_loss) as max_profit_loss,
                STDDEV(profit_loss) as profit_loss_std
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY confidence_bucket
            ORDER BY confidence_bucket
        """, (model_key, start_date, end_date))

        # 2. Performance by prediction probability
        prediction_analysis = analytics_db.execute_query("""
            SELECT
                CASE
                    WHEN ml_prediction < 0.3 THEN '0.0-0.3'
                    WHEN ml_prediction < 0.4 THEN '0.3-0.4'
                    WHEN ml_prediction < 0.5 THEN '0.4-0.5'
                    WHEN ml_prediction < 0.6 THEN '0.5-0.6'
                    WHEN ml_prediction < 0.7 THEN '0.6-0.7'
                    WHEN ml_prediction < 0.8 THEN '0.7-0.8'
                    WHEN ml_prediction < 0.9 THEN '0.8-0.9'
                    ELSE '0.9-1.0'
                END as prediction_bucket,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY prediction_bucket
            ORDER BY prediction_bucket
        """, (model_key, start_date, end_date))

        # 3. Performance by market conditions (time-based)
        time_analysis = analytics_db.execute_query("""
            SELECT
                HOUR(FROM_UNIXTIME(trade_time)) as hour_of_day,
                DAYOFWEEK(FROM_UNIXTIME(trade_time)) as day_of_week,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY hour_of_day, day_of_week
            ORDER BY day_of_week, hour_of_day
        """, (model_key, start_date, end_date))

        # 4. Risk analysis - stop loss vs take profit effectiveness
        risk_analysis = analytics_db.execute_query("""
            SELECT
                CASE
                    WHEN profit_loss <= -ABS(stop_loss - entry_price) * lot_size * 100000 THEN 'Stop Loss Hit'
                    WHEN profit_loss >= ABS(take_profit - entry_price) * lot_size * 100000 THEN 'Take Profit Hit'
                    ELSE 'Other Exit'
                END as exit_type,
                COUNT(*) as total_trades,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY exit_type
        """, (model_key, start_date, end_date))

        # 5. Feature correlation analysis (extract from JSON)
        feature_analysis = analytics_db.execute_query("""
            SELECT
                JSON_EXTRACT(features_json, '$.rsi') as rsi,
                JSON_EXTRACT(features_json, '$.stoch_main') as stoch_main,
                JSON_EXTRACT(features_json, '$.macd_main') as macd_main,
                JSON_EXTRACT(features_json, '$.bb_upper') as bb_upper,
                JSON_EXTRACT(features_json, '$.bb_lower') as bb_lower,
                profit_loss,
                ml_confidence,
                ml_prediction
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            AND features_json IS NOT NULL
            AND features_json != ''
            LIMIT 1000
        """, (model_key, start_date, end_date))

        # 6. Performance degradation over time
        performance_trend = analytics_db.execute_query("""
            SELECT
                DATE(FROM_UNIXTIME(trade_time)) as trade_date,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(ml_confidence) as avg_confidence,
                AVG(ml_prediction) as avg_prediction,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY trade_date
            ORDER BY trade_date DESC
            LIMIT 30
        """, (model_key, start_date, end_date))

        result = {
            'model_key': model_key,
            'date_range': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat()
            },
            'confidence_analysis': confidence_analysis if confidence_analysis else [],
            'prediction_analysis': prediction_analysis if prediction_analysis else [],
            'time_analysis': time_analysis if time_analysis else [],
            'risk_analysis': risk_analysis if risk_analysis else [],
            'feature_analysis': feature_analysis if feature_analysis else [],
            'performance_trend': performance_trend if performance_trend else []
        }

        logger.info(f"✅ Retrieved diagnostics for {model_key}")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving model diagnostics: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model/<model_key>/performance', methods=['GET'])
def get_model_performance_over_time(model_key):
    """Get individual model performance over time"""
    try:
        analytics_db.connect()
        logger.info(f"📊 Retrieving performance over time for model: {model_key}")

        # Get query parameters
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')

        # Default to last 30 days if no dates provided
        if not start_date or not end_date:
            from datetime import datetime, timedelta
            end_date = datetime.now().date()
            start_date = end_date - timedelta(days=30)
        else:
            from datetime import datetime
            start_date = datetime.strptime(start_date, '%Y-%m-%d').date()
            end_date = datetime.strptime(end_date, '%Y-%m-%d').date()

        # Get daily performance for the specific model
        daily_performance = analytics_db.execute_query("""
            SELECT
                DATE(FROM_UNIXTIME(trade_time)) as trade_date,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(ml_prediction) as avg_prediction,
                AVG(ml_confidence) as avg_confidence,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                SUM(CASE WHEN profit_loss > 0 THEN profit_loss ELSE 0 END) as daily_profit,
                SUM(CASE WHEN profit_loss < 0 THEN ABS(profit_loss) ELSE 0 END) as daily_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(%s)
            AND trade_time <= UNIX_TIMESTAMP(%s)
            GROUP BY DATE(FROM_UNIXTIME(trade_time))
            ORDER BY trade_date ASC
        """, (model_key, start_date, end_date))

        # Get cumulative performance over time
        cumulative_data = []
        running_total = 0

        if daily_performance:
            for day in daily_performance:
                running_total += day['total_profit_loss']
                cumulative_data.append({
                    'date': day['trade_date'].isoformat() if hasattr(day['trade_date'], 'isoformat') else str(day['trade_date']),
                    'total_trades': day['total_trades'],
                    'winning_trades': day['winning_trades'],
                    'win_rate': (day['winning_trades'] / day['total_trades'] * 100) if day['total_trades'] > 0 else 0,
                    'avg_profit_loss': float(day['avg_profit_loss']) if day['avg_profit_loss'] else 0,
                    'daily_profit_loss': float(day['total_profit_loss']) if day['total_profit_loss'] else 0,
                    'cumulative_profit_loss': float(running_total),
                    'avg_prediction': float(day['avg_prediction']) if day['avg_prediction'] else 0,
                    'avg_confidence': float(day['avg_confidence']) if day['avg_confidence'] else 0
                })

        # Get model summary stats
        model_summary = analytics_db.execute_query("""
            SELECT
                ml_model_key,
                ml_model_type,
                symbol,
                timeframe,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(ml_prediction) as avg_prediction,
                AVG(ml_confidence) as avg_confidence,
                AVG(profit_loss) as avg_profit_loss,
                SUM(profit_loss) as total_profit_loss,
                MIN(profit_loss) as min_profit_loss,
                MAX(profit_loss) as max_profit_loss
            FROM ml_trade_logs
            WHERE ml_model_key = %s
            AND status = 'CLOSED'
            AND ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            AND profit_loss IS NOT NULL
            GROUP BY ml_model_key, ml_model_type, symbol, timeframe
        """, (model_key,))

        model_info = {}
        if model_summary:
            summary = model_summary[0]
            model_info = {
                'ml_model_key': summary['ml_model_key'],
                'ml_model_type': summary['ml_model_type'],
                'symbol': summary['symbol'],
                'timeframe': summary['timeframe'],
                'total_trades': summary['total_trades'],
                'winning_trades': summary['winning_trades'],
                'win_rate': (summary['winning_trades'] / summary['total_trades'] * 100) if summary['total_trades'] > 0 else 0,
                'avg_prediction': float(summary['avg_prediction']) if summary['avg_prediction'] else 0,
                'avg_confidence': float(summary['avg_confidence']) if summary['avg_confidence'] else 0,
                'avg_profit_loss': float(summary['avg_profit_loss']) if summary['avg_profit_loss'] else 0,
                'total_profit_loss': float(summary['total_profit_loss']) if summary['total_profit_loss'] else 0,
                'min_profit_loss': float(summary['min_profit_loss']) if summary['min_profit_loss'] else 0,
                'max_profit_loss': float(summary['max_profit_loss']) if summary['max_profit_loss'] else 0
            }

        result = {
            'model_info': model_info,
            'daily_performance': cumulative_data,
            'date_range': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat()
            }
        }

        logger.info(f"✅ Retrieved performance data for {model_key}: {len(cumulative_data)} days")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving model performance: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model_alerts', methods=['GET'])
def get_model_degradation_alerts():
    """Get automated alerts for model degradation and confidence issues"""
    try:
        analytics_db.connect()
        logger.info("🚨 Retrieving model degradation alerts")

        # Get all models with recent performance data
        models = analytics_db.execute_query("""
            SELECT DISTINCT ml_model_key, ml_model_type, symbol, timeframe
            FROM ml_trade_logs
            WHERE ml_model_key NOT IN ('RANDOM_MODEL','test_model')
            AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
            AND strategy != 'TestStrategy'
            ORDER BY ml_model_key
        """)

        if not models:
            return jsonify({"alerts": [], "summary": "No models found"}), 200

        alerts = []
        critical_alerts = 0
        warning_alerts = 0
        info_alerts = 0

        for model in models:
            model_key = model['ml_model_key']

            # Get recent performance (last 7 days for faster alerting)
            recent_performance = analytics_db.execute_query("""
                SELECT
                    COUNT(*) as total_trades,
                    SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                    AVG(ml_confidence) as avg_confidence,
                    AVG(ml_prediction) as avg_prediction,
                    AVG(profit_loss) as avg_profit_loss,
                    SUM(profit_loss) as total_profit_loss,
                    STDDEV(profit_loss) as profit_loss_std,
                    MIN(trade_time) as earliest_trade,
                    MAX(trade_time) as latest_trade
                FROM ml_trade_logs
                WHERE ml_model_key = %s
                AND status = 'CLOSED'
                AND profit_loss IS NOT NULL
                AND trade_time >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
            """, (model_key,))

            if not recent_performance or recent_performance[0]['total_trades'] == 0:
                continue

            perf = recent_performance[0]
            total_trades = perf['total_trades']
            winning_trades = perf['winning_trades']
            win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
            avg_confidence = float(perf['avg_confidence']) if perf['avg_confidence'] else 0
            avg_profit_loss = float(perf['avg_profit_loss']) if perf['avg_profit_loss'] else 0

            # Check for confidence inversion (higher confidence = worse performance)
            confidence_analysis = analytics_db.execute_query("""
                SELECT
                    CASE
                        WHEN ml_confidence < 0.5 THEN 'low'
                        ELSE 'high'
                    END as confidence_level,
                    AVG(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as win_rate,
                    COUNT(*) as trade_count
                FROM ml_trade_logs
                WHERE ml_model_key = %s
                AND status = 'CLOSED'
                AND profit_loss IS NOT NULL
                AND trade_time >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
                GROUP BY confidence_level
                HAVING trade_count >= 3
            """, (model_key,))

            model_alerts = []
            alert_level = 'info'

            # Alert 1: Confidence Inversion (Critical)
            if len(confidence_analysis) >= 2:
                low_conf = next((x for x in confidence_analysis if x['confidence_level'] == 'low'), None)
                high_conf = next((x for x in confidence_analysis if x['confidence_level'] == 'high'), None)

                if low_conf and high_conf:
                    low_win_rate = float(low_conf['win_rate']) * 100
                    high_win_rate = float(high_conf['win_rate']) * 100

                    if high_win_rate < low_win_rate:
                        model_alerts.append({
                            'type': 'confidence_inversion',
                            'level': 'critical',
                            'message': f'Confidence system broken: High confidence trades ({high_win_rate:.1f}% win rate) perform worse than low confidence trades ({low_win_rate:.1f}% win rate)',
                            'recommendation': 'Model confidence is unreliable - needs immediate retraining from scratch'
                        })
                        alert_level = 'critical'
                        critical_alerts += 1

            # Alert 2: Low Win Rate (Warning)
            if win_rate < 40:
                model_alerts.append({
                    'type': 'low_win_rate',
                    'level': 'warning',
                    'message': f'Low win rate: {win_rate:.1f}% (threshold: 40%)',
                    'recommendation': 'Consider retraining or adjusting strategy parameters'
                })
                if alert_level == 'info':
                    alert_level = 'warning'
                    warning_alerts += 1

            # Alert 3: High Average Loss (Warning)
            if avg_profit_loss < -2.0:
                model_alerts.append({
                    'type': 'high_average_loss',
                    'level': 'warning',
                    'message': f'High average loss: ${avg_profit_loss:.2f} (threshold: -$2.00)',
                    'recommendation': 'Review risk management and consider retraining'
                })
                if alert_level == 'info':
                    alert_level = 'warning'
                    warning_alerts += 1

            # Alert 4: Confidence Mismatch (Info)
            if avg_confidence > 0.7 and win_rate < 50:
                model_alerts.append({
                    'type': 'confidence_mismatch',
                    'level': 'info',
                    'message': f'High confidence ({avg_confidence:.1%}) but low performance ({win_rate:.1f}% win rate)',
                    'recommendation': 'Monitor closely - confidence may be overestimated'
                })
                if alert_level == 'info':
                    info_alerts += 1

            # Alert 5: Insufficient Recent Data (Info)
            if total_trades < 10:
                model_alerts.append({
                    'type': 'insufficient_data',
                    'level': 'info',
                    'message': f'Limited recent data: {total_trades} trades in last 7 days',
                    'recommendation': 'Wait for more data or check if model is still active'
                })
                if alert_level == 'info':
                    info_alerts += 1

            # Add model alerts if any exist
            if model_alerts:
                alerts.append({
                    'model_key': model_key,
                    'model_type': model['ml_model_type'],
                    'symbol': model['symbol'],
                    'timeframe': model['timeframe'],
                    'alert_level': alert_level,
                    'alerts': model_alerts,
                    'current_metrics': {
                        'total_trades': total_trades,
                        'win_rate': win_rate,
                        'avg_confidence': avg_confidence,
                        'avg_profit_loss': avg_profit_loss
                    }
                })

        # Sort alerts by severity (critical first)
        severity_order = {'critical': 0, 'warning': 1, 'info': 2}
        alerts.sort(key=lambda x: severity_order.get(x['alert_level'], 3))

        summary = {
            'total_models_checked': len(models),
            'models_with_alerts': len(alerts),
            'critical_alerts': critical_alerts,
            'warning_alerts': warning_alerts,
            'info_alerts': info_alerts,
            'requires_immediate_action': critical_alerts > 0
        }

        result = {
            'summary': summary,
            'alerts': alerts,
            'timestamp': datetime.now().isoformat()
        }

        logger.info(f"✅ Retrieved alerts for {len(models)} models: {critical_alerts} critical, {warning_alerts} warning, {info_alerts} info")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving model alerts: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500

@app.route('/analytics/model_discovery', methods=['GET'])
def get_model_discovery():
    """Discover symbols/timeframes that have training data but no models"""
    try:
        analytics_db.connect()
        logger.info("🔍 Discovering new models from available training data")

        # Find symbols/timeframes with recent training data but no existing models
        discovery_query = """
            SELECT
                symbol,
                timeframe,
                COUNT(*) as total_trades,
                SUM(CASE WHEN profit_loss > 0 THEN 1 ELSE 0 END) as winning_trades,
                AVG(profit_loss) as avg_profit_loss,
                MIN(trade_time) as earliest_trade,
                MAX(trade_time) as latest_trade
            FROM ml_trade_logs
            WHERE symbol NOT IN ('RANDOM_MODEL', 'test_symbol')
            AND status = 'CLOSED'
            AND profit_loss IS NOT NULL
            AND trade_time >= UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 7 DAY))
            AND ml_model_key IN ('RANDOM_MODEL', '')  -- Only trades without specific models
            GROUP BY symbol, timeframe
            HAVING total_trades >= 20  -- Minimum 20 trades for training
            ORDER BY total_trades DESC, symbol, timeframe
        """

        discovery_results = analytics_db.execute_query(discovery_query)

        if not discovery_results:
            logger.info("No new model opportunities discovered")
            return jsonify({"new_models": [], "summary": "No new models needed"}), 200

        new_models = []
        for result in discovery_results:
            symbol = result['symbol']
            timeframe = result['timeframe']
            total_trades = result['total_trades']
            winning_trades = result['winning_trades']
            win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0

            # Check if we already have models for this symbol/timeframe
            existing_models_query = """
                SELECT COUNT(*) as model_count
                FROM ml_trade_logs
                WHERE symbol = %s
                AND timeframe = %s
                AND ml_model_key NOT IN ('RANDOM_MODEL', '')
                AND ml_model_key IS NOT NULL
                LIMIT 1
            """

            existing_check = analytics_db.execute_query(existing_models_query, (symbol, timeframe))
            has_existing_models = existing_check and existing_check[0]['model_count'] > 0

            if not has_existing_models:
                # Determine direction based on performance
                # For now, create both buy and sell models
                for direction in ['buy', 'sell']:
                    new_models.append({
                        'symbol': symbol,
                        'timeframe': timeframe,
                        'direction': direction,
                        'total_trades': total_trades,
                        'winning_trades': winning_trades,
                        'win_rate': win_rate,
                        'avg_profit_loss': float(result['avg_profit_loss']) if result['avg_profit_loss'] else 0.0,
                        'earliest_trade': result['earliest_trade'],
                        'latest_trade': result['latest_trade'],
                        'training_opportunity': 'high' if total_trades >= 50 else 'medium'
                    })

        summary = {
            'total_opportunities': len(new_models),
            'symbols_discovered': len(set(m['symbol'] for m in new_models)),
            'timeframes_discovered': len(set(m['timeframe'] for m in new_models)),
            'high_opportunity': len([m for m in new_models if m['training_opportunity'] == 'high'])
        }

        result = {
            'new_models': new_models,
            'summary': summary,
            'timestamp': datetime.now().isoformat()
        }

        logger.info(f"✅ Discovered {len(new_models)} new model opportunities: {summary}")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error discovering new models: {e}")
        logger.error(f"   Exception type: {type(e).__name__}")
        logger.error(f"   Exception details: {str(e)}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        return jsonify({"error": str(e)}), 500
    finally:
        analytics_db.disconnect()
        logger.info("   🔌 Disconnected from analytics database")

@app.route('/analytics/model_retraining_status', methods=['GET'])
def get_model_retraining_status():
    """Get retraining status from metadata files"""
    try:
        import os
        import json
        from pathlib import Path

        logger.info("📁 Retrieving model retraining status from metadata files")

        # Look for metadata files in the ML_Webserver/ml_models directory
        ml_models_dir = os.getenv('ML_MODELS_DIR', "/app/ml_models")

        # Convert to Path object for file operations
        ml_models_path = Path(ml_models_dir)

        if not ml_models_path.exists():
            return jsonify({"models": [], "summary": "No ML models directory found"}), 200

        retraining_status = []

        # Find all metadata files
        for metadata_file in ml_models_path.glob("*_metadata_*.json"):
            try:
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)

                # Extract model information
                model_info = {
                    'model_key': f"{metadata.get('direction', 'buy')}_{metadata.get('symbol')}_PERIOD_{metadata.get('timeframe')}",
                    'symbol': metadata.get('symbol'),
                    'timeframe': metadata.get('timeframe'),
                    'direction': metadata.get('direction'),
                    'last_retrained': metadata.get('last_retrained'),
                    'training_date': metadata.get('training_date'),
                    'health_score': metadata.get('health_score'),
                    'cv_accuracy': metadata.get('cv_accuracy'),
                    'confidence_correlation': metadata.get('confidence_correlation'),
                    'training_samples': metadata.get('training_samples'),
                    'model_type': metadata.get('model_type'),
                    'retrained_by': metadata.get('retrained_by'),
                    'model_version': metadata.get('model_version', 1.0)
                }

                retraining_status.append(model_info)

            except Exception as e:
                logger.warning(f"⚠️ Failed to read metadata file {metadata_file}: {e}")
                continue

        # Sort by last retrained date (most recent first)
        retraining_status.sort(key=lambda x: x.get('last_retrained', ''), reverse=True)

        summary = {
            'total_retrained_models': len(retraining_status),
            'retrained_models': len([m for m in retraining_status if m.get('retrained_by')]),
            'avg_health_score': sum(m.get('health_score', 0) for m in retraining_status) / len(retraining_status) if retraining_status else 0
        }

        result = {
            'models': retraining_status,
            'summary': summary,
            'timestamp': datetime.now().isoformat()
        }

        logger.info(f"✅ Retrieved retraining status for {len(retraining_status)} models")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"❌ Error retrieving model retraining status: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/risk/positions', methods=['GET'])
def get_current_positions():
    """Get current open positions for risk management"""
    try:
        logger.info("📊 Retrieving current open positions for risk management")

        # Query for open positions
        query = """
        SELECT
            trade_id as ticket,
            symbol,
            direction,
            lot_size as volume,
            entry_price as open_price,
            entry_price as current_price,  -- Use entry price as current for now
            stop_loss,
            take_profit,
            0.0 as profit_loss,  -- Open positions have no P&L yet
            trade_time as open_time,
            strategy as comment
        FROM ml_trade_logs
        WHERE status = 'OPEN'
        AND ml_model_key NOT IN ('RANDOM_MODEL', 'test_model')
        AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
        AND strategy != 'TestStrategy'
        ORDER BY trade_time DESC
        """

        result = analytics_db.execute_query(query)

        if result:
            # Convert to expected format
            positions = []
            for row in result:
                position = {
                    'ticket': str(row['ticket']),
                    'symbol': row['symbol'],
                    'direction': row['direction'].lower(),
                    'volume': float(row['volume']),
                    'open_price': float(row['open_price']),
                    'current_price': float(row['current_price']),
                    'stop_loss': float(row['stop_loss']) if row['stop_loss'] else 0.0,
                    'take_profit': float(row['take_profit']) if row['take_profit'] else 0.0,
                    'profit_loss': float(row['profit_loss']),
                    'open_time': datetime.fromtimestamp(row['open_time']).isoformat() if row['open_time'] else '',
                    'comment': row['comment']
                }
                positions.append(position)

            logger.info(f"✅ Retrieved {len(positions)} open positions for risk management")
            return jsonify({
                'status': 'success',
                'positions': positions,
                'count': len(positions),
                'timestamp': datetime.now().isoformat()
            })
        else:
            logger.info("ℹ️ No open positions found for risk management")
            return jsonify({
                'status': 'success',
                'positions': [],
                'count': 0,
                'timestamp': datetime.now().isoformat()
            })

    except Exception as e:
        logger.error(f"❌ Error retrieving positions for risk management: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/risk/portfolio', methods=['GET'])
def get_portfolio_summary():
    """Get portfolio summary for risk management"""
    try:
        logger.info("📈 Retrieving portfolio summary for risk management")

        # Query for portfolio summary
        query = """
        SELECT
            COUNT(*) as total_positions,
            SUM(CASE WHEN UPPER(direction) = 'BUY' THEN 1 ELSE 0 END) as long_positions,
            SUM(CASE WHEN UPPER(direction) = 'SELL' THEN 1 ELSE 0 END) as short_positions,
            SUM(lot_size) as total_volume,
            AVG(lot_size) as avg_lot_size
        FROM ml_trade_logs
        WHERE status = 'OPEN'
        AND ml_model_key NOT IN ('RANDOM_MODEL', 'test_model')
        AND trade_id != '0' AND trade_id != '' AND trade_id IS NOT NULL
        AND strategy != 'TestStrategy'
        """

        result = analytics_db.execute_query(query)

        if result and result[0]:
            row = result[0]

            # Get account balance from environment or use default
            # Analytics service only provides position counts and volume data
            # Account balance and risk calculations are handled by the ML service
            portfolio_summary = {
                'total_positions': int(row['total_positions']) if row['total_positions'] is not None else 0,
                'long_positions': int(row['long_positions']) if row['long_positions'] is not None else 0,
                'short_positions': int(row['short_positions']) if row['short_positions'] is not None else 0,
                'total_volume': float(row['total_volume']) if row['total_volume'] is not None else 0.0,
                'avg_lot_size': float(row['avg_lot_size']) if row['avg_lot_size'] is not None else 0.0
            }

            logger.info(f"📊 Portfolio summary: {portfolio_summary['total_positions']} positions, {portfolio_summary['total_volume']:.2f} total volume")

            logger.info(f"✅ Retrieved portfolio summary for risk management: {portfolio_summary['total_positions']} positions")
            return jsonify({
                'status': 'success',
                'portfolio': portfolio_summary,
                'timestamp': datetime.now().isoformat()
            })
        else:
            logger.info("ℹ️ No portfolio data found for risk management")
            default_portfolio = {
                'equity': 10000.0,
                'balance': 10000.0,
                'margin': 0.0,
                'free_margin': 10000.0,
                'total_positions': 0,
                'long_positions': 0,
                'short_positions': 0,
                'total_volume': 0.0,
                'avg_lot_size': 0.0
            }
            return jsonify({
                'status': 'success',
                'portfolio': default_portfolio,
                'timestamp': datetime.now().isoformat()
            })

    except Exception as e:
        logger.error(f"❌ Error retrieving portfolio for risk management: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    # Initialize database connection
    try:
        analytics_db.connect()
        logger.info("✅ Connected to analytics database")
    except Exception as e:
        logger.error(f"❌ Failed to connect to database: {e}")
        exit(1)

    # Start Flask server
    import os
    port = int(os.getenv('FLASK_RUN_PORT', 5001))
    logger.info(f"🚀 Starting analytics server on http://localhost:{port}")
    app.run(host='0.0.0.0', port=port, debug=False)
