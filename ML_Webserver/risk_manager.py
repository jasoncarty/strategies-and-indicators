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
                 take_profit: float, profit_loss: float, open_time: str, comment: str,
                 tick_value: float = 0.0, tick_size: float = 0.0):
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
        self.tick_value = tick_value
        self.tick_size = tick_size
        self.risk_amount = 0.0

class MLRiskManager:
    """Comprehensive risk management for ML trading system"""

    def __init__(self):
        self.config = RiskConfig()
        self.portfolio = PortfolioRisk()

        # Risk tracking
        self.initial_balance = 0.0
        self.daily_start_balance = 0.0
        self.last_daily_reset = datetime.now()
        self.weekly_drawdown = 0.0  # Weekly drawdown from EA

        # Position tracking
        self.positions: List[PositionData] = []

        # Risk calculation cache
        self.risk_cache = {}
        self.risk_cache_time = {}
        self.risk_cache_size = 100

        logger.info("ML Risk Manager initialized successfully")

    def set_portfolio_data(self, portfolio_data: Dict) -> None:
        """Set portfolio data from external source (e.g., MT5 account info)"""
        logger.info("🔍 ===== SETTING PORTFOLIO DATA =====")
        logger.info(f"🔍 Received portfolio data: {portfolio_data}")
        logger.info(f"🔍 Data type: {type(portfolio_data)}")
        logger.info(f"🔍 Data keys: {list(portfolio_data.keys()) if isinstance(portfolio_data, dict) else 'Not a dict'}")

        # Analytics service only provides position counts and volume data
        # Account balance and equity are set separately via set_account_info
        self.portfolio.total_positions = portfolio_data.get('total_positions', 0)
        self.portfolio.long_positions = portfolio_data.get('long_positions', 0)
        self.portfolio.short_positions = portfolio_data.get('short_positions', 0)

        logger.info(f"🔍 Set portfolio values:")
        logger.info(f"  Total Positions: {self.portfolio.total_positions}")
        logger.info(f"  Long Positions: {self.portfolio.long_positions}")
        logger.info(f"  Short Positions: {self.portfolio.short_positions}")
        logger.info("🔍 ===== END PORTFOLIO DATA =====")

    def set_weekly_drawdown(self, weekly_drawdown: float) -> None:
        """Set weekly drawdown from EA for risk management"""
        logger.info("🔍 ===== SETTING WEEKLY DRAWDOWN =====")
        logger.info(f"🔍 Weekly Drawdown: {weekly_drawdown * 100:.2f}%")

        self.weekly_drawdown = weekly_drawdown

        # Log weekly drawdown status
        if weekly_drawdown >= 0.20:  # 20% threshold
            logger.warning(f"🔍 ⚠️ Weekly drawdown {weekly_drawdown * 100:.2f}% exceeds 20% threshold!")
        elif weekly_drawdown >= 0.15:  # 15% warning
            logger.warning(f"🔍 ⚠️ Weekly drawdown {weekly_drawdown * 100:.2f}% approaching 20% threshold")
        else:
            logger.info(f"🔍 ✅ Weekly drawdown {weekly_drawdown * 100:.2f}% within acceptable range")

        logger.info("🔍 ===== END WEEKLY DRAWDOWN =====")

    def get_weekly_drawdown(self) -> float:
        """Get current weekly drawdown value"""
        return self.weekly_drawdown

    def set_account_info(self, account_balance: float, account_equity: float = None) -> None:
        """Set account balance and equity for risk calculations"""
        logger.info("🔍 ===== SETTING ACCOUNT INFO =====")
        logger.info(f"🔍 Account Balance: ${account_balance:,.2f}")

        self.portfolio.total_balance = account_balance
        self.portfolio.total_equity = account_equity if account_equity is not None else account_balance



        logger.info(f"🔍 Set account values:")
        logger.info(f"  Balance: ${self.portfolio.total_balance:,.2f}")
        logger.info(f"  Equity: ${self.portfolio.total_equity:,.2f}")
        logger.info("🔍 ===== END ACCOUNT INFO =====")

        # Calculate margin level
        if self.portfolio.total_margin > 0:
            self.portfolio.margin_level = (self.portfolio.total_equity / self.portfolio.total_margin) * 100

        # Calculate daily loss
        if self.daily_start_balance > 0:
            self.portfolio.daily_loss_percent = (self.daily_start_balance - self.portfolio.total_equity) / self.daily_start_balance

        # Reset daily tracking if needed
        if datetime.now() - self.last_daily_reset > timedelta(days=1):
            self._reset_daily_tracking()

    def set_positions_data(self, positions_data: List[Dict]) -> None:
        """Set positions data from external source (e.g., MT5 open positions)"""
        logger.info("🔍 ===== SETTING POSITIONS DATA =====")
        logger.info(f"🔍 Received positions data: {positions_data}")
        logger.info(f"🔍 Data type: {type(positions_data)}")
        logger.info(f"🔍 Number of positions: {len(positions_data) if isinstance(positions_data, list) else 'Not a list'}")

        if isinstance(positions_data, list) and len(positions_data) > 0:
            logger.info(f"🔍 First position sample: {positions_data[0]}")
            logger.info(f"🔍 Position keys: {list(positions_data[0].keys()) if positions_data[0] else 'Empty position'}")

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
                comment=pos_data.get('comment', ''),
                tick_value=pos_data.get('tick_value', 0.0),
                tick_size=pos_data.get('tick_size', 0.0)
            )

            # Calculate risk amount
            position.risk_amount = self._calculate_position_risk(position)

            # Update counters
            self.portfolio.total_positions += 1
            self.portfolio.total_profit_loss += position.profit_loss

            # Log significant P&L positions
            if abs(position.profit_loss) > 10.0:  # Log positions with >$10 P&L
                logger.info(f"🔍 Position {position.symbol} {position.direction}: P&L ${position.profit_loss:,.2f}")

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
        logger.info("🔍 Calculating total portfolio risk...")

        # Debug: Log positions with extremely high risk
        high_risk_positions = [pos for pos in self.positions if pos.risk_amount > 1000]
        if high_risk_positions:
            logger.warning(f"🔍 ⚠️ Found {len(high_risk_positions)} positions with risk > $1,000:")
            for i, pos in enumerate(high_risk_positions[:5]):  # Show first 5
                logger.warning(f"🔍   [{i}] {pos.symbol} {pos.direction}: Risk ${pos.risk_amount:,.2f}, Volume: {pos.volume}, Price: {pos.current_price}, SL: {pos.stop_loss}")
            if len(high_risk_positions) > 5:
                logger.warning(f"🔍   ... and {len(high_risk_positions) - 5} more high-risk positions")

        self.portfolio.total_risk_percent = self._calculate_total_portfolio_risk()
        logger.info(f"🔍 Calculated total risk: {self.portfolio.total_risk_percent * 100:.2f}%")

        # Log total P&L summary
        logger.info(f"🔍 Total P&L from {self.portfolio.total_positions} positions: ${self.portfolio.total_profit_loss:,.2f}")
        if self.portfolio.total_profit_loss > 0:
            logger.info(f"🔍 Portfolio is profitable: +${self.portfolio.total_profit_loss:,.2f}")
        elif self.portfolio.total_profit_loss < 0:
            logger.info(f"🔍 Portfolio is losing: ${self.portfolio.total_profit_loss:,.2f}")
        else:
            logger.info(f"🔍 Portfolio is break-even: $0.00")

        # Calculate real equity based on account balance + unrealized P&L
        self.portfolio.total_equity = self.portfolio.total_balance + self.portfolio.total_profit_loss
        logger.info(f"🔍 Calculated real equity: ${self.portfolio.total_equity:,.2f} (Balance: ${self.portfolio.total_balance:,.2f} + P&L: ${self.portfolio.total_profit_loss:,.2f})")

        # Use weekly drawdown from EA instead of calculating peak-based drawdown
        # The EA provides accurate weekly drawdown from MT5 deal history
        if self.weekly_drawdown > 0:
            logger.info(f"🔍 Using weekly drawdown from EA: {self.weekly_drawdown * 100:.2f}%")
            # Set current drawdown to weekly drawdown for consistency
            self.portfolio.current_drawdown_percent = self.weekly_drawdown
            self.portfolio.max_drawdown_percent = max(self.portfolio.max_drawdown_percent, self.weekly_drawdown)
        else:
            logger.info("🔍 No weekly drawdown data from EA - using 0% as default")
            self.portfolio.current_drawdown_percent = 0.0

        # Calculate risk ratios
        self._calculate_risk_ratios()

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

            # 2b. Check weekly drawdown limit (additional safety)
            if hasattr(self, 'weekly_drawdown') and self.weekly_drawdown > self.config.max_drawdown_percent:
                return False, {"reason": "Weekly drawdown limit exceeded",
                             "current": f"{self.weekly_drawdown * 100:.2f}%",
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
        """Calculate risk amount for a position using MT5-style calculations"""
        # If no stop loss is set, use a reasonable default risk calculation
        if position.stop_loss <= 0:
            # For positions without stop loss, estimate risk as 2% of position value
            # This is a conservative estimate for risk management
            position_value = position.volume * position.current_price * 100000  # Standard lot size calculation
            default_risk = position_value * 0.02  # 2% of position value

            # Safety check: cap extremely high risk amounts
            if default_risk > 10000:  # Cap at $10,000 per position
                logger.warning(f"🔍   ⚠️ Default risk amount ${default_risk:.2f} exceeds $10,000 cap, capping to $10,000")
                default_risk = 10000

            logger.info(f"🔍   No stop loss set, using default risk: ${default_risk:.2f} (2% of position value)")
            return default_risk

        # Calculate risk based on actual stop loss using MT5-style approach
        stop_distance = abs(position.current_price - position.stop_loss)

        # Use the same logic as TradeUtils.mqh CalculateLotSize function
        # Risk per lot = (stop_distance / tick_size) * tick_value
        # Then scale by actual position volume

        # Use tick information from the position data (sent by the EA)
        tick_value = position.tick_value
        tick_size = position.tick_size

        if tick_size <= 0 or tick_value <= 0:
            logger.warning(f"🔍   ⚠️ Missing tick info for {position.symbol} (tick_value: {tick_value}, tick_size: {tick_size}), using fallback calculation")
            # Fallback to percentage-based risk
            price_change_percent = (stop_distance / position.current_price) * 100
            position_value = position.volume * position.current_price * 100000
            risk_amount = position_value * (price_change_percent / 100) * 0.1  # Scale down to 0.1% for safety
        else:
            # Calculate risk using MT5-style formula
            risk_per_lot = (stop_distance / tick_size) * tick_value
            risk_amount = risk_per_lot * position.volume

        # Safety check: cap extremely high risk amounts
        if risk_amount > 10000:  # Cap at $10,000 per position
            logger.warning(f"🔍   ⚠️ Risk amount ${risk_amount:.2f} exceeds $10,000 cap, capping to $10,000")
            risk_amount = 10000

        return risk_amount

    def _calculate_total_portfolio_risk(self) -> float:
        """Calculate total portfolio risk percentage"""
        logger.info(f"🔍 _calculate_total_portfolio_risk called with {len(self.positions)} positions")
        logger.info(f"🔍 Portfolio balance: {self.portfolio.total_balance}")

        total_risk = sum(pos.risk_amount for pos in self.positions)
        logger.info(f"🔍 Sum of position risks: {total_risk}")

        if self.portfolio.total_balance > 0:
            risk_percent = total_risk / self.portfolio.total_balance
            logger.info(f"🔍 Calculated risk percentage: {risk_percent * 100:.2f}%")

            # Factor in weekly drawdown if available
            if hasattr(self, 'weekly_drawdown') and self.weekly_drawdown > 0:
                logger.info(f"🔍 Weekly drawdown factor: {self.weekly_drawdown * 100:.2f}%")
                # Increase risk percentage based on weekly drawdown
                # Higher drawdown = higher risk multiplier
                drawdown_multiplier = 1.0 + (self.weekly_drawdown * 2)  # Max 3x multiplier at 100% drawdown
                adjusted_risk = risk_percent * drawdown_multiplier
                logger.info(f"🔍 Risk adjusted for weekly drawdown: {adjusted_risk * 100:.2f}% (multiplier: {drawdown_multiplier:.2f})")
                return adjusted_risk

            return risk_percent

        logger.info("🔍 Portfolio balance is 0, returning 0.0")
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
