"""
Risk Management Module for ML Trading System
Provides comprehensive risk management including position sizing, portfolio limits, and trade validation
"""

import os
import logging
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
import math

logger = logging.getLogger(__name__)

class RiskConfig:
    """Risk management configuration loaded from environment variables"""

    def __init__(self):
        # Position sizing
        self.risk_per_trade_percent = float(os.getenv('RISK_PER_TRADE_PERCENT', '0.01'))  # 1% per trade
        self.max_risk_per_trade_percent = float(os.getenv('MAX_RISK_PER_TRADE_PERCENT', '0.015'))  # 1.5% max per trade

        # Portfolio limits
        self.max_total_risk_percent = float(os.getenv('MAX_TOTAL_RISK_PERCENT', '0.08'))  # 8% total portfolio
        self.max_drawdown_percent = float(os.getenv('MAX_DRAWDOWN_PERCENT', '0.20'))  # 20% max drawdown
        self.max_daily_loss_percent = float(os.getenv('MAX_DAILY_LOSS_PERCENT', '0.05'))  # 5% daily loss limit

        # Position limits
        self.max_total_positions = int(os.getenv('MAX_TOTAL_POSITIONS', '40'))  # 40 total positions
        self.max_positions_per_direction = int(os.getenv('MAX_POSITIONS_PER_DIRECTION', '4'))  # 4 positions per direction
        self.max_positions_per_symbol = int(os.getenv('MAX_POSITIONS_PER_SYMBOL', '2'))  # 2 positions per symbol

        # Correlation limits
        self.max_correlation_threshold = float(os.getenv('MAX_CORRELATION_THRESHOLD', '0.7'))  # 70% correlation limit

        # Risk calculation
        self.risk_free_rate = float(os.getenv('RISK_FREE_RATE', '0.02'))  # 2% risk-free rate
        self.lookback_period = int(os.getenv('RISK_LOOKBACK_PERIOD', '20'))  # 20 periods for volatility

        logger.info("Risk configuration loaded:")
        logger.info(f"  Risk per trade: {self.risk_per_trade_percent * 100:.2f}%")
        logger.info(f"  Max total risk: {self.max_total_risk_percent * 100:.2f}%")
        logger.info(f"  Max drawdown: {self.max_drawdown_percent * 100:.2f}%")
        logger.info(f"  Max positions: {self.max_total_positions}")

class PortfolioRisk:
    """Portfolio risk metrics and calculations"""

    def __init__(self):
        self.total_equity = 0.0
        self.total_balance = 0.0
        self.total_profit_loss = 0.0
        self.total_margin = 0.0
        self.free_margin = 0.0
        self.margin_level = 0.0

        # Risk metrics
        self.total_risk_percent = 0.0
        self.current_drawdown_percent = 0.0
        self.daily_loss_percent = 0.0
        self.max_drawdown_percent = 0.0

        # Position counts
        self.total_positions = 0
        self.long_positions = 0
        self.short_positions = 0
        self.positions_per_symbol = {}

        # Risk ratios
        self.sharpe_ratio = 0.0
        self.calmar_ratio = 0.0
        self.sortino_ratio = 0.0

class PositionData:
    """Individual position data for risk calculations"""

    def __init__(self, ticket: str, symbol: str, direction: str, volume: float,
                 open_price: float, current_price: float, stop_loss: float,
                 take_profit: float, profit_loss: float, open_time: str, comment: str):
        self.ticket = ticket
        self.symbol = symbol
        self.direction = direction
        self.volume = volume
        self.open_price = open_price
        self.current_price = current_price
        self.stop_loss = stop_loss
        self.take_profit = take_profit
        self.profit_loss = profit_loss
        self.open_time = open_time
        self.comment = comment
        self.risk_amount = 0.0

class MLRiskManager:
    """Comprehensive risk management for ML trading system"""

    def __init__(self):
        self.config = RiskConfig()
        self.portfolio = PortfolioRisk()

        # Risk tracking
        self.initial_balance = 0.0
        self.peak_balance = 0.0
        self.daily_start_balance = 0.0
        self.last_daily_reset = datetime.now()

        # Position tracking
        self.positions: List[PositionData] = []

        # Risk calculation cache
        self.risk_cache = {}
        self.risk_cache_time = {}
        self.risk_cache_size = 100

        logger.info("ML Risk Manager initialized successfully")

    def set_portfolio_data(self, portfolio_data: Dict) -> None:
        """Set portfolio data from external source (e.g., MT5 account info)"""
        self.portfolio.total_equity = portfolio_data.get('equity', 0.0)
        self.portfolio.total_balance = portfolio_data.get('balance', 0.0)
        self.portfolio.total_margin = portfolio_data.get('margin', 0.0)
        self.portfolio.free_margin = portfolio_data.get('free_margin', 0.0)

        # Calculate margin level
        if self.portfolio.total_margin > 0:
            self.portfolio.margin_level = (self.portfolio.total_equity / self.portfolio.total_margin) * 100

        # Update peak balance and drawdown
        if self.portfolio.total_equity > self.peak_balance:
            self.peak_balance = self.portfolio.total_equity

        if self.peak_balance > 0:
            self.portfolio.current_drawdown_percent = (self.peak_balance - self.portfolio.total_equity) / self.peak_balance
            self.portfolio.max_drawdown_percent = max(self.portfolio.max_drawdown_percent, self.portfolio.current_drawdown_percent)

        # Calculate daily loss
        if self.daily_start_balance > 0:
            self.portfolio.daily_loss_percent = (self.daily_start_balance - self.portfolio.total_equity) / self.daily_start_balance

        # Reset daily tracking if needed
        if datetime.now() - self.last_daily_reset > timedelta(days=1):
            self._reset_daily_tracking()

    def set_positions_data(self, positions_data: List[Dict]) -> None:
        """Set positions data from external source (e.g., MT5 open positions)"""
        self.positions = []
        self.portfolio.total_positions = 0
        self.portfolio.long_positions = 0
        self.portfolio.short_positions = 0
        self.portfolio.total_profit_loss = 0.0
        self.portfolio.positions_per_symbol = {}

        for pos_data in positions_data:
            position = PositionData(
                ticket=pos_data.get('ticket', ''),
                symbol=pos_data.get('symbol', ''),
                direction=pos_data.get('direction', ''),
                volume=pos_data.get('volume', 0.0),
                open_price=pos_data.get('open_price', 0.0),
                current_price=pos_data.get('current_price', 0.0),
                stop_loss=pos_data.get('stop_loss', 0.0),
                take_profit=pos_data.get('take_profit', 0.0),
                profit_loss=pos_data.get('profit_loss', 0.0),
                open_time=pos_data.get('open_time', ''),
                comment=pos_data.get('comment', '')
            )

            # Calculate risk amount
            position.risk_amount = self._calculate_position_risk(position)

            # Update counters
            self.portfolio.total_positions += 1
            self.portfolio.total_profit_loss += position.profit_loss

            if position.direction.lower() == 'buy':
                self.portfolio.long_positions += 1
            else:
                self.portfolio.short_positions += 1

            # Update symbol position counts
            if position.symbol not in self.portfolio.positions_per_symbol:
                self.portfolio.positions_per_symbol[position.symbol] = 0
            self.portfolio.positions_per_symbol[position.symbol] += 1

            self.positions.append(position)

        # Calculate total risk percentage
        self.portfolio.total_risk_percent = self._calculate_total_portfolio_risk()

        # Calculate risk ratios
        self._calculate_risk_ratios()

        logger.info(f"Portfolio updated: {self.portfolio.total_positions} positions, "
                   f"Risk: {self.portfolio.total_risk_percent * 100:.2f}%, "
                   f"Drawdown: {self.portfolio.current_drawdown_percent * 100:.2f}%")

    def calculate_optimal_lot_size(self, symbol: str, entry_price: float, stop_loss: float,
                                 account_balance: float, risk_override: float = 0.0) -> Tuple[float, Dict]:
        """Calculate optimal lot size based on risk management rules"""
        try:
            # Calculate stop distance
            stop_distance = abs(entry_price - stop_loss)
            if stop_distance <= 0:
                return 0.0, {"error": "Invalid stop loss distance"}

            # Get risk percentage
            risk_percent = risk_override if risk_override > 0 else self.config.risk_per_trade_percent
            risk_amount = account_balance * risk_percent

            # Calculate lot size based on risk
            # This is a simplified calculation - in production you'd want more sophisticated metrics
            # based on symbol-specific tick values and risk per pip
            lot_size = risk_amount / (stop_distance * 100)  # Simplified risk per point calculation

            # Apply lot size constraints (example constraints)
            min_lot = 0.01
            max_lot = 100.0
            lot_size = max(min_lot, min(max_lot, lot_size))

            # Validate against maximum risk per trade
            actual_risk_amount = lot_size * stop_distance * 100  # Simplified
            actual_risk_percent = actual_risk_amount / account_balance

            if actual_risk_percent > self.config.max_risk_per_trade_percent:
                logger.warning(f"Calculated risk ({actual_risk_percent * 100:.2f}%) exceeds maximum "
                             f"({self.config.max_risk_per_trade_percent * 100:.2f}%)")
                lot_size = (account_balance * self.config.max_risk_per_trade_percent) / (stop_distance * 100)
                lot_size = max(min_lot, min(max_lot, lot_size))

            result = {
                "lot_size": round(lot_size, 2),
                "risk_amount": round(risk_amount, 2),
                "risk_percent": round(risk_percent * 100, 2),
                "actual_risk_percent": round(actual_risk_percent * 100, 2),
                "stop_distance": round(stop_distance, 5)
            }

            logger.info(f"Lot size calculation for {symbol}: {result}")
            return lot_size, result

        except Exception as e:
            logger.error(f"Error calculating lot size: {e}")
            return 0.0, {"error": str(e)}

    def can_open_new_trade(self, symbol: str, lot_size: float, stop_loss_distance: float,
                          direction: str) -> Tuple[bool, Dict]:
        """Check if new trade is allowed based on risk management rules"""
        try:
            # 1. Check total position limit
            if self.portfolio.total_positions >= self.config.max_total_positions:
                return False, {"reason": "Maximum positions reached", "limit": self.config.max_total_positions}

            # 2. Check drawdown limit
            if self.portfolio.current_drawdown_percent > self.config.max_drawdown_percent:
                return False, {"reason": "Drawdown limit exceeded",
                             "current": f"{self.portfolio.current_drawdown_percent * 100:.2f}%",
                             "limit": f"{self.config.max_drawdown_percent * 100:.2f}%"}

            # 3. Check daily loss limit
            if self.portfolio.daily_loss_percent > self.config.max_daily_loss_percent:
                return False, {"reason": "Daily loss limit exceeded",
                             "current": f"{self.portfolio.daily_loss_percent * 100:.2f}%",
                             "limit": f"{self.config.max_daily_loss_percent * 100:.2f}%"}

            # 4. Check total risk limit
            new_trade_risk = self._calculate_trade_risk(symbol, lot_size, stop_loss_distance)
            total_risk_with_new = self.portfolio.total_risk_percent + new_trade_risk

            if total_risk_with_new > self.config.max_total_risk_percent:
                return False, {"reason": "Total risk limit exceeded",
                             "current": f"{self.portfolio.total_risk_percent * 100:.2f}%",
                             "with_new": f"{total_risk_with_new * 100:.2f}%",
                             "limit": f"{self.config.max_total_risk_percent * 100:.2f}%"}

            # 5. Check symbol position limit
            symbol_positions = self.portfolio.positions_per_symbol.get(symbol, 0)
            if symbol_positions >= self.config.max_positions_per_symbol:
                return False, {"reason": "Symbol position limit reached",
                             "symbol": symbol, "current": symbol_positions,
                             "limit": self.config.max_positions_per_symbol}

            # 6. Check direction correlation
            if not self._check_direction_correlation(symbol, direction):
                return False, {"reason": "Direction correlation limit exceeded"}

            return True, {"reason": "All risk checks passed"}

        except Exception as e:
            logger.error(f"Error checking trade permission: {e}")
            return False, {"error": str(e)}

    def get_risk_status(self) -> Dict:
        """Get current risk status for trading"""
        status = "LOW_RISK"

        if self.portfolio.current_drawdown_percent > self.config.max_drawdown_percent * 0.8:
            status = "HIGH_RISK"
        elif (self.portfolio.total_risk_percent > self.config.max_total_risk_percent * 0.8 or
              self.portfolio.daily_loss_percent > self.config.max_daily_loss_percent * 0.8):
            status = "MEDIUM_RISK"

        return {
            "status": status,
            "portfolio": {
                "total_equity": round(self.portfolio.total_equity, 2),
                "total_balance": round(self.portfolio.total_balance, 2),
                "total_profit_loss": round(self.portfolio.total_profit_loss, 2),
                "total_risk_percent": round(self.portfolio.total_risk_percent * 100, 2),
                "current_drawdown_percent": round(self.portfolio.current_drawdown_percent * 100, 2),
                "daily_loss_percent": round(self.portfolio.daily_loss_percent * 100, 2),
                "total_positions": self.portfolio.total_positions,
                "long_positions": self.portfolio.long_positions,
                "short_positions": self.portfolio.short_positions
            },
            "limits": {
                "max_total_risk": f"{self.config.max_total_risk_percent * 100:.2f}%",
                "max_drawdown": f"{self.config.max_drawdown_percent * 100:.2f}%",
                "max_daily_loss": f"{self.config.max_daily_loss_percent * 100:.2f}%",
                "max_positions": self.config.max_total_positions
            }
        }

    def _reset_daily_tracking(self) -> None:
        """Reset daily tracking metrics"""
        self.daily_start_balance = self.portfolio.total_equity
        self.last_daily_reset = datetime.now()
        logger.info(f"Daily tracking reset - Start balance: ${self.daily_start_balance:.2f}")

    def _calculate_position_risk(self, position: PositionData) -> float:
        """Calculate risk amount for a position"""
        if position.stop_loss <= 0:
            return 0.0

        stop_distance = abs(position.current_price - position.stop_loss)
        # Simplified risk calculation - in production use symbol-specific tick values
        return position.volume * stop_distance * 100

    def _calculate_total_portfolio_risk(self) -> float:
        """Calculate total portfolio risk percentage"""
        total_risk = sum(pos.risk_amount for pos in self.positions)

        if self.portfolio.total_balance > 0:
            return total_risk / self.portfolio.total_balance

        return 0.0

    def _calculate_trade_risk(self, symbol: str, lot_size: float, stop_loss_distance: float) -> float:
        """Calculate risk for a new trade"""
        # Simplified risk calculation
        risk_amount = lot_size * stop_loss_distance * 100

        if self.portfolio.total_balance > 0:
            return risk_amount / self.portfolio.total_balance

        return 0.0

    def _check_direction_correlation(self, symbol: str, direction: str) -> bool:
        """Check if adding this position would exceed direction limits"""
        long_count = 0
        short_count = 0

        for pos in self.positions:
            if pos.symbol == symbol:
                if pos.direction.lower() == 'buy':
                    long_count += 1
                else:
                    short_count += 1

        # Check if adding this position would exceed direction limits
        if direction.lower() == 'buy' and long_count >= self.config.max_positions_per_direction:
            return False

        if direction.lower() == 'sell' and short_count >= self.config.max_positions_per_direction:
            return False

        return True

    def _calculate_risk_ratios(self) -> None:
        """Calculate risk ratios (simplified)"""
        self.portfolio.sharpe_ratio = 0.0
        self.portfolio.calmar_ratio = 0.0
        self.portfolio.sortino_ratio = 0.0

        # Calculate Sharpe ratio (simplified)
        if self.portfolio.current_drawdown_percent > 0:
            excess_return = self.portfolio.total_profit_loss / self.portfolio.total_balance - self.config.risk_free_rate
            self.portfolio.sharpe_ratio = excess_return / self.portfolio.current_drawdown_percent

        # Calculate Calmar ratio (simplified)
        if self.portfolio.max_drawdown_percent > 0:
            annual_return = self.portfolio.total_profit_loss / self.portfolio.total_balance
            self.portfolio.calmar_ratio = annual_return / self.portfolio.max_drawdown_percent
