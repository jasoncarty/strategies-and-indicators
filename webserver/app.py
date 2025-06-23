from flask import Flask, request, jsonify, render_template
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from datetime import datetime
import json
import os

app = Flask(__name__)
CORS(app)

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///strategy_tester.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Database Models
class StrategyTest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    strategy_name = db.Column(db.String(100), nullable=False)
    symbol = db.Column(db.String(20), nullable=False)
    timeframe = db.Column(db.String(10), nullable=False)
    start_date = db.Column(db.DateTime, nullable=False)
    end_date = db.Column(db.DateTime, nullable=False)
    initial_deposit = db.Column(db.Float, nullable=False)
    final_balance = db.Column(db.Float, nullable=False)
    profit = db.Column(db.Float, nullable=False)
    profit_factor = db.Column(db.Float, nullable=False)
    max_drawdown = db.Column(db.Float, nullable=False)
    total_trades = db.Column(db.Integer, nullable=False)
    winning_trades = db.Column(db.Integer, nullable=False)
    losing_trades = db.Column(db.Integer, nullable=False)
    win_rate = db.Column(db.Float, nullable=False)
    sharpe_ratio = db.Column(db.Float, nullable=True)

    # --- New Fields ---
    gross_profit = db.Column(db.Float, nullable=True)
    gross_loss = db.Column(db.Float, nullable=True)
    recovery_factor = db.Column(db.Float, nullable=True)
    expected_payoff = db.Column(db.Float, nullable=True)
    z_score = db.Column(db.Float, nullable=True)
    long_trades = db.Column(db.Integer, nullable=True)
    short_trades = db.Column(db.Integer, nullable=True)
    long_trades_won = db.Column(db.Integer, nullable=True)
    short_trades_won = db.Column(db.Integer, nullable=True)
    largest_profit = db.Column(db.Float, nullable=True)
    largest_loss = db.Column(db.Float, nullable=True)
    avg_profit = db.Column(db.Float, nullable=True)
    avg_loss = db.Column(db.Float, nullable=True)
    max_consecutive_wins = db.Column(db.Integer, nullable=True)
    max_consecutive_losses = db.Column(db.Integer, nullable=True)
    avg_consecutive_wins = db.Column(db.Integer, nullable=True)
    avg_consecutive_losses = db.Column(db.Integer, nullable=True)
    # --- End New Fields ---

    test_date = db.Column(db.DateTime, default=datetime.utcnow)
    parameters = db.Column(db.Text, nullable=True)  # JSON string of strategy parameters

class Trade(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    strategy_test_id = db.Column(db.Integer, db.ForeignKey('strategy_test.id'), nullable=False)
    ticket = db.Column(db.Integer, nullable=False)
    symbol = db.Column(db.String(20), nullable=False)
    type = db.Column(db.String(10), nullable=False)  # BUY/SELL
    volume = db.Column(db.Float, nullable=False)
    open_price = db.Column(db.Float, nullable=False)
    close_price = db.Column(db.Float, nullable=False)
    open_time = db.Column(db.DateTime, nullable=False)
    close_time = db.Column(db.DateTime, nullable=False)
    profit = db.Column(db.Float, nullable=False)
    swap = db.Column(db.Float, nullable=False)
    commission = db.Column(db.Float, nullable=False)
    net_profit = db.Column(db.Float, nullable=False)

class TradingConditions(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    trade_id = db.Column(db.Integer, db.ForeignKey('trade.id'), nullable=False)

    # Basic trade info
    entry_time = db.Column(db.DateTime, nullable=False)
    order_type = db.Column(db.String(10), nullable=False)  # BUY/SELL
    entry_price = db.Column(db.Float, nullable=False)
    stop_loss = db.Column(db.Float, nullable=False)
    target_price = db.Column(db.Float, nullable=False)
    lot_size = db.Column(db.Float, nullable=False)
    current_price = db.Column(db.Float, nullable=False)

    # Market conditions
    atr_value = db.Column(db.Float, nullable=True)
    volume = db.Column(db.Float, nullable=True)
    volume_ratio = db.Column(db.Float, nullable=True)

    # ICT Strategy conditions
    in_kill_zone = db.Column(db.Boolean, nullable=True)
    kill_zone_type = db.Column(db.String(50), nullable=True)
    has_market_structure = db.Column(db.Boolean, nullable=True)
    market_structure_bullish = db.Column(db.Boolean, nullable=True)
    has_liquidity_sweep = db.Column(db.Boolean, nullable=True)
    liquidity_sweep_time = db.Column(db.DateTime, nullable=True)
    liquidity_sweep_level = db.Column(db.Float, nullable=True)

    # FVG conditions
    has_fvg = db.Column(db.Boolean, nullable=True)
    fvg_type = db.Column(db.String(20), nullable=True)  # Bullish/Bearish
    fvg_start = db.Column(db.Float, nullable=True)
    fvg_end = db.Column(db.Float, nullable=True)
    fvg_filled = db.Column(db.Boolean, nullable=True)
    fvg_time = db.Column(db.DateTime, nullable=True)

    # OTE conditions
    has_ote = db.Column(db.Boolean, nullable=True)
    ote_type = db.Column(db.String(20), nullable=True)  # FVG/Fib/OrderBlock/StdDev
    ote_level = db.Column(db.Float, nullable=True)
    ote_strength = db.Column(db.Float, nullable=True)

    # Lower timeframe conditions
    has_ltf_break = db.Column(db.Boolean, nullable=True)
    has_ltf_confirmation = db.Column(db.Boolean, nullable=True)
    has_ote_retest = db.Column(db.Boolean, nullable=True)
    ltf_break_type = db.Column(db.String(20), nullable=True)  # Bullish/Bearish

    # Fibonacci conditions
    near_fib_level = db.Column(db.Boolean, nullable=True)
    fib_level = db.Column(db.Float, nullable=True)
    fib_type = db.Column(db.String(10), nullable=True)  # 0.236, 0.382, etc.

    # Order block conditions
    near_order_block = db.Column(db.Boolean, nullable=True)
    order_block_high = db.Column(db.Float, nullable=True)
    order_block_low = db.Column(db.Float, nullable=True)
    order_block_bullish = db.Column(db.Boolean, nullable=True)

    # Volume conditions
    volume_confirmation = db.Column(db.Boolean, nullable=True)
    volume_ratio_value = db.Column(db.Float, nullable=True)

    # Risk management
    risk_amount = db.Column(db.Float, nullable=True)
    risk_percent = db.Column(db.Float, nullable=True)
    reward_risk_ratio = db.Column(db.Float, nullable=True)

    # Additional context
    additional_notes = db.Column(db.Text, nullable=True)

# Routes
@app.route('/')
def home():
    return render_template('index.html')

@app.route('/dashboard')
def dashboard():
    return render_template('index.html')

@app.route('/api')
def api_info():
    return jsonify({
        "message": "MT5 Strategy Tester Web Server API",
        "version": "1.0.0",
        "endpoints": {
            "POST /api/test": "Save strategy test results",
            "GET /api/tests": "Get all strategy tests",
            "GET /api/test/<id>": "Get specific test with trades",
            "DELETE /api/test/<id>": "Delete a test",
            "GET /api/stats": "Get overall statistics"
        }
    })

@app.route('/api/test', methods=['POST'])
def save_test():
    try:
        data = request.get_json()

        # Create new strategy test
        test = StrategyTest(
            strategy_name=data['strategy_name'],
            symbol=data['symbol'],
            timeframe=data['timeframe'],
            start_date=datetime.fromisoformat(data['start_date']),
            end_date=datetime.fromisoformat(data['end_date']),
            initial_deposit=float(data['initial_deposit']),
            final_balance=float(data['final_balance']),
            profit=float(data['profit']),
            profit_factor=float(data['profit_factor']),
            max_drawdown=float(data['max_drawdown']),
            total_trades=int(data['total_trades']),
            winning_trades=int(data['winning_trades']),
            losing_trades=int(data['losing_trades']),
            win_rate=float(data['win_rate']),
            sharpe_ratio=float(data.get('sharpe_ratio', 0)),

            # --- New Fields ---
            gross_profit=float(data.get('gross_profit', 0)),
            gross_loss=float(data.get('gross_loss', 0)),
            recovery_factor=float(data.get('recovery_factor', 0)),
            expected_payoff=float(data.get('expected_payoff', 0)),
            z_score=float(data.get('z_score', 0)),
            long_trades=int(data.get('long_trades', 0)),
            short_trades=int(data.get('short_trades', 0)),
            long_trades_won=int(data.get('long_trades_won', 0)),
            short_trades_won=int(data.get('short_trades_won', 0)),
            largest_profit=float(data.get('largest_profit', 0)),
            largest_loss=float(data.get('largest_loss', 0)),
            avg_profit=float(data.get('avg_profit', 0)),
            avg_loss=float(data.get('avg_loss', 0)),
            max_consecutive_wins=int(data.get('max_consecutive_wins', 0)),
            max_consecutive_losses=int(data.get('max_consecutive_losses', 0)),
            avg_consecutive_wins=int(data.get('avg_consecutive_wins', 0)),
            avg_consecutive_losses=int(data.get('avg_consecutive_losses', 0)),
            # --- End New Fields ---

            parameters=json.dumps(data.get('parameters', {}))
        )

        db.session.add(test)
        db.session.commit()

        # Save trades if provided
        if 'trades' in data:
            for trade_data in data['trades']:
                trade = Trade(
                    strategy_test_id=test.id,
                    ticket=int(trade_data['ticket']),
                    symbol=trade_data['symbol'],
                    type=trade_data['type'],
                    volume=float(trade_data['volume']),
                    open_price=float(trade_data['open_price']),
                    close_price=float(trade_data['close_price']),
                    open_time=datetime.fromisoformat(trade_data['open_time']),
                    close_time=datetime.fromisoformat(trade_data['close_time']),
                    profit=float(trade_data['profit']),
                    swap=float(trade_data.get('swap', 0)),
                    commission=float(trade_data.get('commission', 0)),
                    net_profit=float(trade_data['net_profit'])
                )
                db.session.add(trade)
                db.session.flush()  # Get the trade ID

                # Save trading conditions if provided
                if 'trading_conditions' in trade_data:
                    conditions_data = trade_data['trading_conditions']
                    conditions = TradingConditions(
                        trade_id=trade.id,
                        entry_time=datetime.fromisoformat(conditions_data.get('entryTime', trade_data['open_time'])),
                        order_type=conditions_data.get('orderType', trade_data['type']),
                        entry_price=float(conditions_data.get('entryPrice', trade_data['open_price'])),
                        stop_loss=float(conditions_data.get('stopLoss', 0)),
                        target_price=float(conditions_data.get('targetPrice', 0)),
                        lot_size=float(conditions_data.get('lotSize', trade_data['volume'])),
                        current_price=float(conditions_data.get('currentPrice', trade_data['open_price'])),
                        atr_value=float(conditions_data.get('atrValue', 0)),
                        volume=float(conditions_data.get('volume', 0)),
                        volume_ratio=float(conditions_data.get('volumeRatio', 0)),
                        in_kill_zone=conditions_data.get('inKillZone', False),
                        kill_zone_type=conditions_data.get('killZoneType', ''),
                        has_market_structure=conditions_data.get('hasMarketStructure', False),
                        market_structure_bullish=conditions_data.get('marketStructureBullish', False),
                        has_liquidity_sweep=conditions_data.get('hasLiquiditySweep', False),
                        liquidity_sweep_time=datetime.fromisoformat(conditions_data['liquiditySweepTime']) if conditions_data.get('liquiditySweepTime') else None,
                        liquidity_sweep_level=float(conditions_data.get('liquiditySweepLevel', 0)),
                        has_fvg=conditions_data.get('hasFVG', False),
                        fvg_type=conditions_data.get('fvgType', ''),
                        fvg_start=float(conditions_data.get('fvgStart', 0)),
                        fvg_end=float(conditions_data.get('fvgEnd', 0)),
                        fvg_filled=conditions_data.get('fvgFilled', False),
                        fvg_time=datetime.fromisoformat(conditions_data['fvgTime']) if conditions_data.get('fvgTime') else None,
                        has_ote=conditions_data.get('hasOTE', False),
                        ote_type=conditions_data.get('oteType', ''),
                        ote_level=float(conditions_data.get('oteLevel', 0)),
                        ote_strength=float(conditions_data.get('oteStrength', 0)),
                        has_ltf_break=conditions_data.get('hasLTFBreak', False),
                        has_ltf_confirmation=conditions_data.get('hasLTFConfirmation', False),
                        has_ote_retest=conditions_data.get('hasOTERetest', False),
                        ltf_break_type=conditions_data.get('ltfBreakType', ''),
                        near_fib_level=conditions_data.get('nearFibLevel', False),
                        fib_level=float(conditions_data.get('fibLevel', 0)),
                        fib_type=conditions_data.get('fibType', ''),
                        near_order_block=conditions_data.get('nearOrderBlock', False),
                        order_block_high=float(conditions_data.get('orderBlockHigh', 0)),
                        order_block_low=float(conditions_data.get('orderBlockLow', 0)),
                        order_block_bullish=conditions_data.get('orderBlockBullish', False),
                        volume_confirmation=conditions_data.get('volumeConfirmation', False),
                        volume_ratio_value=float(conditions_data.get('volumeRatioValue', 0)),
                        risk_amount=float(conditions_data.get('riskAmount', 0)),
                        risk_percent=float(conditions_data.get('riskPercent', 0)),
                        reward_risk_ratio=float(conditions_data.get('rewardRiskRatio', 0)),
                        additional_notes=conditions_data.get('additionalNotes', '')
                    )
                    db.session.add(conditions)

            db.session.commit()

        return jsonify({
            "success": True,
            "message": "Test saved successfully",
            "test_id": test.id
        }), 201

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

@app.route('/api/tests', methods=['GET'])
def get_tests():
    try:
        tests = StrategyTest.query.order_by(StrategyTest.test_date.desc()).all()
        return jsonify([{
            'id': test.id,
            'strategy_name': test.strategy_name,
            'symbol': test.symbol,
            'timeframe': test.timeframe,
            'test_date': test.test_date.isoformat(),
            'profit': test.profit,
            'win_rate': test.win_rate,
            'total_trades': test.total_trades
        } for test in tests])
    except Exception as e:
        print(f"Error fetching tests: {e}")
        return jsonify({"error": "Failed to fetch test results", "details": str(e)}), 500

@app.route('/api/test/<int:test_id>', methods=['GET'])
def get_test_api(test_id):
    try:
        test = db.session.get(StrategyTest, test_id)
        if not test:
            return jsonify({"error": "Test not found"}), 404

        # Convert the main test object to a dictionary
        test_data = {c.name: getattr(test, c.name) for c in test.__table__.columns}

        # Manually format dates to ISO format string
        test_data['start_date'] = test.start_date.isoformat()
        test_data['end_date'] = test.end_date.isoformat()
        test_data['test_date'] = test.test_date.isoformat()

        # Query and serialize trades
        trades_query = Trade.query.filter_by(strategy_test_id=test.id).all()
        trades_list = []
        for trade in trades_query:
            trade_data = {c.name: getattr(trade, c.name) for c in trade.__table__.columns}

            # Manually format dates to ISO format string
            trade_data['open_time'] = trade.open_time.isoformat()
            trade_data['close_time'] = trade.close_time.isoformat()

            # Query and serialize trading conditions
            conditions = TradingConditions.query.filter_by(trade_id=trade.id).first()
            if conditions:
                conditions_data = {c.name: getattr(conditions, c.name) for c in conditions.__table__.columns}
                # Manually format dates to ISO format string
                for key, value in conditions_data.items():
                    if isinstance(value, datetime):
                        conditions_data[key] = value.isoformat()
                trade_data['trading_conditions'] = conditions_data
            else:
                trade_data['trading_conditions'] = None

            trades_list.append(trade_data)

        test_data['trades'] = trades_list
        return jsonify(test_data)

    except Exception as e:
        print(f"Error fetching test {test_id}: {e}")
        return jsonify({"error": "Failed to fetch test details", "details": str(e)}), 500

@app.route('/test/<int:test_id>')
def view_test_details(test_id):
    test = db.session.get(StrategyTest, test_id)

    if not test:
            return jsonify({"error": "Test not found"}), 404
    test_data = {c.name: getattr(test, c.name) for c in test.__table__.columns}

    # This page will now be rendered empty and will fetch its own data via javascript
    return render_template('test_details.html', test=test_data)

@app.route('/api/test/<int:test_id>', methods=['DELETE'])
def delete_test(test_id):
    try:
        test = StrategyTest.query.get_or_404(test_id)

        # Delete associated trades first
        Trade.query.filter_by(strategy_test_id=test_id).delete()

        # Delete the test
        db.session.delete(test)
        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Test deleted successfully"
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

@app.route('/api/stats', methods=['GET'])
def get_stats():
    try:
        tests = StrategyTest.query.all()
        total_tests = len(tests)

        if total_tests == 0:
            return jsonify({
                "success": True,
                "stats": {
                    "total_tests": 0,
                    "total_profit": 0,
                    "profitable_tests": 0,
                    "success_rate": 0,
                    "average_profit": 0,
                    "average_profit_factor": 0,
                    "average_win_rate": 0,
                }
            })

        profitable_tests = sum(1 for test in tests if test.profit > 0)
        success_rate = (profitable_tests / total_tests) * 100 if total_tests > 0 else 0

        total_profit = sum(test.profit for test in tests)
        average_profit = total_profit / total_tests

        # Avoid division by zero for profit factor and win rate
        total_profit_factor = sum(test.profit_factor for test in tests if test.profit_factor is not None)
        average_profit_factor = total_profit_factor / total_tests if total_tests > 0 else 0

        total_win_rate = sum(test.win_rate for test in tests if test.win_rate is not None)
        average_win_rate = total_win_rate / total_tests if total_tests > 0 else 0

        return jsonify({
            "success": True,
            "stats": {
                "total_tests": total_tests,
                "total_profit": total_profit,
                "profitable_tests": profitable_tests,
                "success_rate": success_rate,
                "average_profit": average_profit,
                "average_profit_factor": average_profit_factor,
                "average_win_rate": average_win_rate,
            }
        })

    except Exception as e:
        app.logger.error(f"Error in get_stats: {e}")
        return jsonify({"success": False, "error": "Could not retrieve statistics."}), 500

def model_to_dict(model_instance):
    return {c.name: getattr(model_instance, c.name) for c in model_instance.__table__.columns}
