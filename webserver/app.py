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
        result = []

        for test in tests:
            result.append({
                "id": test.id,
                "strategy_name": test.strategy_name,
                "symbol": test.symbol,
                "timeframe": test.timeframe,
                "start_date": test.start_date.isoformat(),
                "end_date": test.end_date.isoformat(),
                "initial_deposit": test.initial_deposit,
                "final_balance": test.final_balance,
                "profit": test.profit,
                "profit_factor": test.profit_factor,
                "max_drawdown": test.max_drawdown,
                "total_trades": test.total_trades,
                "winning_trades": test.winning_trades,
                "losing_trades": test.losing_trades,
                "win_rate": test.win_rate,
                "sharpe_ratio": test.sharpe_ratio,
                "test_date": test.test_date.isoformat(),
                "parameters": json.loads(test.parameters) if test.parameters else {}
            })

        return jsonify({
            "success": True,
            "tests": result,
            "count": len(result)
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

@app.route('/api/test/<int:test_id>', methods=['GET'])
def get_test(test_id):
    try:
        test = StrategyTest.query.get_or_404(test_id)
        trades = Trade.query.filter_by(strategy_test_id=test_id).all()

        test_data = {
            "id": test.id,
            "strategy_name": test.strategy_name,
            "symbol": test.symbol,
            "timeframe": test.timeframe,
            "start_date": test.start_date.isoformat(),
            "end_date": test.end_date.isoformat(),
            "initial_deposit": test.initial_deposit,
            "final_balance": test.final_balance,
            "profit": test.profit,
            "profit_factor": test.profit_factor,
            "max_drawdown": test.max_drawdown,
            "total_trades": test.total_trades,
            "winning_trades": test.winning_trades,
            "losing_trades": test.losing_trades,
            "win_rate": test.win_rate,
            "sharpe_ratio": test.sharpe_ratio,
            "test_date": test.test_date.isoformat(),
            "parameters": json.loads(test.parameters) if test.parameters else {},
            "trades": []
        }

        for trade in trades:
            test_data["trades"].append({
                "id": trade.id,
                "ticket": trade.ticket,
                "symbol": trade.symbol,
                "type": trade.type,
                "volume": trade.volume,
                "open_price": trade.open_price,
                "close_price": trade.close_price,
                "open_time": trade.open_time.isoformat(),
                "close_time": trade.close_time.isoformat(),
                "profit": trade.profit,
                "swap": trade.swap,
                "commission": trade.commission,
                "net_profit": trade.net_profit
            })

        return jsonify({
            "success": True,
            "test": test_data
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400

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
        total_tests = StrategyTest.query.count()
        profitable_tests = StrategyTest.query.filter(StrategyTest.profit > 0).count()

        if total_tests > 0:
            avg_profit = db.session.query(db.func.avg(StrategyTest.profit)).scalar()
            avg_profit_factor = db.session.query(db.func.avg(StrategyTest.profit_factor)).scalar()
            avg_win_rate = db.session.query(db.func.avg(StrategyTest.win_rate)).scalar()
            avg_drawdown = db.session.query(db.func.avg(StrategyTest.max_drawdown)).scalar()
        else:
            avg_profit = avg_profit_factor = avg_win_rate = avg_drawdown = 0

        return jsonify({
            "success": True,
            "stats": {
                "total_tests": total_tests,
                "profitable_tests": profitable_tests,
                "success_rate": (profitable_tests / total_tests * 100) if total_tests > 0 else 0,
                "average_profit": round(avg_profit, 2) if avg_profit else 0,
                "average_profit_factor": round(avg_profit_factor, 2) if avg_profit_factor else 0,
                "average_win_rate": round(avg_win_rate, 2) if avg_win_rate else 0,
                "average_drawdown": round(avg_drawdown, 2) if avg_drawdown else 0
            }
        })

    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 400
