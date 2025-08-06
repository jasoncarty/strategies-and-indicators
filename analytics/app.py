#!/usr/bin/env python3
"""
Flask web server for receiving analytics data from MT5 EA
"""
from flask import Flask, request, jsonify
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

# Initialize database connection on startup
def initialize_database():
    """Initialize database connection and run migrations if needed"""
    try:
        analytics_db.connect()
        logger.info("✅ Database connection initialized on startup")

        # Run migrations if needed
        run_migrations_on_startup()

    except Exception as e:
        logger.error(f"❌ Failed to initialize database connection: {e}")

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

# Initialize database when app starts
initialize_database()

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
            # Attempt to reconnect
            analytics_db._ensure_connection()
            if analytics_db.is_connected():
                db_status = "connected"
                logger.info("✅ Database connection restored during health check")
            else:
                db_status = "disconnected"
                logger.error("❌ Failed to restore database connection")
    except Exception as e:
        logger.error(f"❌ Database health check failed: {e}")
        db_status = "error"

    # Determine overall health status
    overall_status = "healthy" if db_status == "connected" else "degraded"
    status_code = 200 if db_status == "connected" else 503

    return jsonify({
        "status": overall_status,
        "timestamp": datetime.now().isoformat(),
        "database": db_status
    }), status_code

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
            FROM trades
            WHERE status = 'CLOSED'
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
