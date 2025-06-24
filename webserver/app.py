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
    strategy_version = db.Column(db.String(20), nullable=False)
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

    # Unique constraint to prevent duplicate test runs
    __table_args__ = (
        db.Index('idx_strategy_test_unique',
                 'strategy_name', 'strategy_version', 'timeframe', 'start_date', 'end_date', 'parameters'),
        db.UniqueConstraint('strategy_name', 'strategy_version', 'timeframe', 'start_date', 'end_date', 'parameters',
                           name='uq_strategy_test_run'),
    )

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

        # Check if this test run already exists
        existing_test = StrategyTest.query.filter_by(
            strategy_name=data['strategy_name'],
            strategy_version=data['strategy_version'],
            timeframe=data['timeframe'],
            start_date=datetime.fromisoformat(data['start_date']),
            end_date=datetime.fromisoformat(data['end_date']),
            parameters=json.dumps(data.get('parameters', {}))
        ).first()

        if existing_test:
            return jsonify({
                "success": False,
                "error": "Duplicate test run detected",
                "message": f"A test run with the same parameters already exists (ID: {existing_test.id})",
                "existing_test_id": existing_test.id
            }), 409  # Conflict status code

        # Create new strategy test
        test = StrategyTest(
            strategy_name=data['strategy_name'],
            strategy_version=data['strategy_version'],
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
        db.session.rollback()
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

@app.route('/api/tests', methods=['GET'])
def get_tests():
    try:
        tests = StrategyTest.query.order_by(StrategyTest.test_date.desc()).all()

        # Calculate scores for each test
        scored_tests = []
        for test in tests:
            score_data = calculate_strategy_score(test)
            scored_tests.append({
                'id': test.id,
                'strategy_name': test.strategy_name,
                'strategy_version': test.strategy_version,
                'symbol': test.symbol,
                'timeframe': test.timeframe,
                'test_date': test.test_date.isoformat(),
                'profit': test.profit,
                'win_rate': test.win_rate,
                'total_trades': test.total_trades,
                'score': score_data['total_score'],
                'score_breakdown': score_data['breakdown']
            })

        # Sort by score (highest first)
        scored_tests.sort(key=lambda x: x['score'], reverse=True)

        return jsonify(scored_tests)
    except Exception as e:
        print(f"Error fetching tests: {e}")
        return jsonify({"error": "Failed to fetch test results", "details": str(e)}), 500

def calculate_strategy_score(test):
    """
    Calculate a composite score for a strategy test based on multiple metrics.
    Returns a score between 0-100 and a breakdown of individual component scores.
    """
    breakdown = {}
    total_score = 0

    # 1. Profit Factor (0-20 points)
    # Excellent: >2.0, Good: 1.5-2.0, Acceptable: 1.2-1.5, Poor: <1.2
    if test.profit_factor:
        if test.profit_factor >= 2.0:
            pf_score = 20
        elif test.profit_factor >= 1.5:
            pf_score = 15 + (test.profit_factor - 1.5) * 10
        elif test.profit_factor >= 1.2:
            pf_score = 10 + (test.profit_factor - 1.2) * 16.67
        else:
            pf_score = max(0, test.profit_factor * 8.33)
        breakdown['profit_factor'] = round(pf_score, 2)
        total_score += pf_score

    # 2. Recovery Factor (0-15 points)
    # Excellent: >3.0, Good: 2.0-3.0, Acceptable: 1.0-2.0, Poor: <1.0
    if test.recovery_factor:
        if test.recovery_factor >= 3.0:
            rf_score = 15
        elif test.recovery_factor >= 2.0:
            rf_score = 10 + (test.recovery_factor - 2.0) * 5
        elif test.recovery_factor >= 1.0:
            rf_score = 5 + (test.recovery_factor - 1.0) * 5
        else:
            rf_score = max(0, test.recovery_factor * 5)
        breakdown['recovery_factor'] = round(rf_score, 2)
        total_score += rf_score

    # 3. Win Rate (0-15 points)
    # Excellent: >70%, Good: 60-70%, Acceptable: 50-60%, Poor: <50%
    if test.win_rate:
        if test.win_rate >= 70:
            wr_score = 15
        elif test.win_rate >= 60:
            wr_score = 10 + (test.win_rate - 60) * 0.5
        elif test.win_rate >= 50:
            wr_score = 5 + (test.win_rate - 50) * 0.5
        else:
            wr_score = max(0, test.win_rate * 0.1)
        breakdown['win_rate'] = round(wr_score, 2)
        total_score += wr_score

    # 4. Sharpe Ratio (0-15 points)
    # Excellent: >2.0, Good: 1.0-2.0, Acceptable: 0.5-1.0, Poor: <0.5
    if test.sharpe_ratio:
        if test.sharpe_ratio >= 2.0:
            sr_score = 15
        elif test.sharpe_ratio >= 1.0:
            sr_score = 10 + (test.sharpe_ratio - 1.0) * 5
        elif test.sharpe_ratio >= 0.5:
            sr_score = 5 + (test.sharpe_ratio - 0.5) * 10
        else:
            sr_score = max(0, test.sharpe_ratio * 10)
        breakdown['sharpe_ratio'] = round(sr_score, 2)
        total_score += sr_score

    # 5. Max Drawdown (0-10 points) - Lower is better
    # Excellent: <5%, Good: 5-10%, Acceptable: 10-20%, Poor: >20%
    if test.max_drawdown:
        if test.max_drawdown <= 5:
            dd_score = 10
        elif test.max_drawdown <= 10:
            dd_score = 8 + (10 - test.max_drawdown) * 0.4
        elif test.max_drawdown <= 20:
            dd_score = 5 + (20 - test.max_drawdown) * 0.3
        else:
            dd_score = max(0, (50 - test.max_drawdown) * 0.1)
        breakdown['max_drawdown'] = round(dd_score, 2)
        total_score += dd_score

    # 6. Consecutive Wins (0-8 points)
    # Bonus for consistency
    if test.max_consecutive_wins:
        cw_score = min(8, test.max_consecutive_wins * 0.5)
        breakdown['consecutive_wins'] = round(cw_score, 2)
        total_score += cw_score

    # 7. Consecutive Losses (0-7 points) - Lower is better
    # Penalty for long losing streaks
    if test.max_consecutive_losses:
        cl_score = max(0, 7 - test.max_consecutive_losses * 0.5)
        breakdown['consecutive_losses'] = round(cl_score, 2)
        total_score += cl_score

    # 8. Total Trades (0-5 points) - More trades = more statistical significance
    # Bonus for sufficient sample size
    if test.total_trades:
        if test.total_trades >= 100:
            tt_score = 5
        elif test.total_trades >= 50:
            tt_score = 3 + (test.total_trades - 50) * 0.04
        elif test.total_trades >= 20:
            tt_score = 1 + (test.total_trades - 20) * 0.067
        else:
            tt_score = test.total_trades * 0.05
        breakdown['total_trades'] = round(tt_score, 2)
        total_score += tt_score

    # 9. Expected Payoff (0-5 points)
    # Bonus for positive expected value
    if test.expected_payoff:
        if test.expected_payoff > 0:
            ep_score = min(5, test.expected_payoff * 2)
        else:
            ep_score = 0
        breakdown['expected_payoff'] = round(ep_score, 2)
        total_score += ep_score

    return {
        'total_score': round(total_score, 2),
        'breakdown': breakdown
    }

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

@app.route('/api/tests/scored', methods=['GET'])
def get_scored_tests():
    """
    Get all tests with detailed scoring information and sorting options.
    Query parameters:
    - sort_by: 'score', 'profit', 'win_rate', 'date', 'trades'
    - order: 'asc' or 'desc'
    - min_trades: minimum number of trades to include
    - min_score: minimum score to include
    """
    try:
        sort_by = request.args.get('sort_by', 'score')
        order = request.args.get('order', 'desc')
        min_trades = request.args.get('min_trades', type=int)
        min_score = request.args.get('min_score', type=float)

        # Build query
        query = StrategyTest.query

        # Apply filters
        if min_trades:
            query = query.filter(StrategyTest.total_trades >= min_trades)

        tests = query.all()

        # Calculate scores and apply score filter
        scored_tests = []
        for test in tests:
            score_data = calculate_strategy_score(test)
            if min_score and score_data['total_score'] < min_score:
                continue

            scored_tests.append({
                'id': test.id,
                'strategy_name': test.strategy_name,
                'strategy_version': test.strategy_version,
                'symbol': test.symbol,
                'timeframe': test.timeframe,
                'test_date': test.test_date.isoformat(),
                'profit': test.profit,
                'profit_factor': test.profit_factor,
                'recovery_factor': test.recovery_factor,
                'win_rate': test.win_rate,
                'sharpe_ratio': test.sharpe_ratio,
                'max_drawdown': test.max_drawdown,
                'total_trades': test.total_trades,
                'expected_payoff': test.expected_payoff,
                'max_consecutive_wins': test.max_consecutive_wins,
                'max_consecutive_losses': test.max_consecutive_losses,
                'score': score_data['total_score'],
                'score_breakdown': score_data['breakdown']
            })

        # Sort results
        reverse = order.lower() == 'desc'
        if sort_by == 'score':
            scored_tests.sort(key=lambda x: x['score'], reverse=reverse)
        elif sort_by == 'profit':
            scored_tests.sort(key=lambda x: x['profit'], reverse=reverse)
        elif sort_by == 'win_rate':
            scored_tests.sort(key=lambda x: x['win_rate'], reverse=reverse)
        elif sort_by == 'date':
            scored_tests.sort(key=lambda x: x['test_date'], reverse=reverse)
        elif sort_by == 'trades':
            scored_tests.sort(key=lambda x: x['total_trades'], reverse=reverse)
        elif sort_by == 'profit_factor':
            scored_tests.sort(key=lambda x: x['profit_factor'] or 0, reverse=reverse)
        elif sort_by == 'recovery_factor':
            scored_tests.sort(key=lambda x: x['recovery_factor'] or 0, reverse=reverse)
        elif sort_by == 'sharpe_ratio':
            scored_tests.sort(key=lambda x: x['sharpe_ratio'] or 0, reverse=reverse)
        elif sort_by == 'drawdown':
            scored_tests.sort(key=lambda x: x['max_drawdown'] or 0, reverse=not reverse)  # Lower is better

        return jsonify({
            'success': True,
            'tests': scored_tests,
            'total_count': len(scored_tests),
            'sort_by': sort_by,
            'order': order
        })

    except Exception as e:
        print(f"Error fetching scored tests: {e}")
        return jsonify({"error": "Failed to fetch scored test results", "details": str(e)}), 500
