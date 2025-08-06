"""
Analytics collector for BreakoutStrategy EA
"""
import json
import logging
from datetime import datetime
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict

from .database.manager import analytics_db

logger = logging.getLogger(__name__)

@dataclass
class TradeData:
    """Trade data structure"""
    trade_id: str
    symbol: str
    timeframe: str
    direction: str
    entry_price: float
    stop_loss: float
    take_profit: float
    lot_size: float
    strategy_name: str
    strategy_version: str
    account_id: str
    entry_time: datetime
    exit_price: Optional[float] = None
    profit_loss: Optional[float] = None
    profit_loss_pips: Optional[float] = None
    exit_time: Optional[datetime] = None
    duration_seconds: Optional[int] = None
    status: str = "OPEN"

@dataclass
class MLPredictionData:
    """ML prediction data structure"""
    trade_id: str
    model_name: str
    model_type: str
    prediction_probability: float
    confidence_score: float
    features_json: Optional[Dict[str, Any]] = None

@dataclass
class MarketConditionsData:
    """Market conditions data structure"""
    trade_id: str
    symbol: str
    timeframe: str
    rsi: Optional[float] = None
    stoch_main: Optional[float] = None
    stoch_signal: Optional[float] = None
    macd_main: Optional[float] = None
    macd_signal: Optional[float] = None
    bb_upper: Optional[float] = None
    bb_lower: Optional[float] = None
    adx: Optional[float] = None
    cci: Optional[float] = None
    momentum: Optional[float] = None
    atr: Optional[float] = None
    volume_ratio: Optional[float] = None
    price_change: Optional[float] = None
    volatility: Optional[float] = None
    spread: Optional[float] = None
    session_hour: Optional[int] = None
    day_of_week: Optional[int] = None
    month: Optional[int] = None

class AnalyticsCollector:
    """Analytics data collector"""

    def __init__(self, strategy_name: str, strategy_version: str, account_id: str):
        self.strategy_name = strategy_name
        self.strategy_version = strategy_version
        self.account_id = account_id
        self.enabled = True

        # Try to connect to database
        try:
            analytics_db.connect()
            logger.info("✅ Analytics collector initialized with database connection")
        except Exception as e:
            logger.warning(f"⚠️ Analytics collector initialized without database: {e}")
            self.enabled = False

    def __del__(self):
        """Cleanup database connection"""
        if hasattr(self, 'enabled') and self.enabled:
            analytics_db.disconnect()

    def record_trade_entry(self, trade_data: TradeData) -> bool:
        """Record a new trade entry"""
        if not self.enabled:
            return False

        try:
            # Convert to dictionary and add strategy info
            data = asdict(trade_data)
            data['strategy_name'] = self.strategy_name
            data['strategy_version'] = self.strategy_version
            data['account_id'] = self.account_id

            analytics_db.insert_trade(data)
            logger.info(f"📊 Recorded trade entry: {trade_data.trade_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to record trade entry: {e}")
            return False

    def record_trade_exit(self, trade_id: str, exit_data: Dict[str, Any]) -> bool:
        """Record trade exit information"""
        if not self.enabled:
            return False

        try:
            analytics_db.update_trade_exit(trade_id, exit_data)
            logger.info(f"📊 Recorded trade exit: {trade_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to record trade exit: {e}")
            return False

    def record_ml_prediction(self, prediction_data: MLPredictionData) -> bool:
        """Record ML prediction data"""
        if not self.enabled:
            return False

        try:
            data = asdict(prediction_data)
            analytics_db.insert_ml_prediction(data)
            logger.info(f"🤖 Recorded ML prediction for trade: {prediction_data.trade_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to record ML prediction: {e}")
            return False

    def record_market_conditions(self, conditions_data: MarketConditionsData) -> bool:
        """Record market conditions data"""
        if not self.enabled:
            return False

        try:
            data = asdict(conditions_data)
            analytics_db.insert_market_conditions(data)
            logger.info(f"📈 Recorded market conditions for trade: {conditions_data.trade_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to record market conditions: {e}")
            return False

    def get_performance_summary(self, symbol: str, timeframe: str,
                              start_date: datetime, end_date: datetime) -> Dict[str, Any]:
        """Get performance summary for the strategy"""
        if not self.enabled:
            return {}

        try:
            return analytics_db.get_trade_performance(
                self.strategy_name, self.strategy_version,
                symbol, timeframe, start_date.date(), end_date.date()
            )
        except Exception as e:
            logger.error(f"❌ Failed to get performance summary: {e}")
            return {}

    def get_ml_model_performance(self, model_name: str, model_type: str,
                               symbol: str, timeframe: str,
                               start_date: datetime, end_date: datetime) -> Dict[str, Any]:
        """Get ML model performance summary"""
        if not self.enabled:
            return {}

        try:
            return analytics_db.get_ml_model_performance(
                model_name, model_type, symbol, timeframe,
                start_date.date(), end_date.date()
            )
        except Exception as e:
            logger.error(f"❌ Failed to get ML model performance: {e}")
            return {}

# Global analytics collector instance
analytics_collector = None
