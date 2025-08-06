-- Migration: 001_create_initial_tables.sql
-- Description: Create initial tables for BreakoutStrategy analytics
-- Date: 2024-07-25

-- Create trades table
CREATE TABLE IF NOT EXISTS trades (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    trade_id VARCHAR(50) UNIQUE NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    direction ENUM('BUY', 'SELL') NOT NULL,
    entry_price DECIMAL(20, 8) NOT NULL,
    exit_price DECIMAL(20, 8) NULL,
    stop_loss DECIMAL(20, 8) NOT NULL,
    take_profit DECIMAL(20, 8) NOT NULL,
    lot_size DECIMAL(10, 4) NOT NULL,
    profit_loss DECIMAL(20, 8) NULL,
    profit_loss_pips DECIMAL(10, 2) NULL,
    entry_time DATETIME NOT NULL,
    exit_time DATETIME NULL,
    duration_seconds INT NULL,
    status ENUM('OPEN', 'CLOSED', 'CANCELLED') DEFAULT 'OPEN',
    strategy_name VARCHAR(100) NOT NULL,
    strategy_version VARCHAR(20) NOT NULL,
    account_id VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_entry_time (entry_time),
    INDEX idx_status (status),
    INDEX idx_strategy (strategy_name, strategy_version)
);

-- Create ML predictions table
CREATE TABLE IF NOT EXISTS ml_predictions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    trade_id VARCHAR(50) NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    model_type ENUM('BUY', 'SELL', 'COMBINED') NOT NULL,
    prediction_probability DECIMAL(5, 4) NOT NULL,
    confidence_score DECIMAL(5, 4) NOT NULL,
    features_json JSON NULL,
    prediction_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (trade_id) REFERENCES trades(trade_id) ON DELETE CASCADE,
    INDEX idx_trade_id (trade_id),
    INDEX idx_model (model_name, model_type),
    INDEX idx_prediction_time (prediction_time)
);

-- Create market conditions table
CREATE TABLE IF NOT EXISTS market_conditions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    trade_id VARCHAR(50) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    rsi DECIMAL(8, 4) NULL,
    stoch_main DECIMAL(8, 4) NULL,
    stoch_signal DECIMAL(8, 4) NULL,
    macd_main DECIMAL(8, 4) NULL,
    macd_signal DECIMAL(8, 4) NULL,
    bb_upper DECIMAL(20, 8) NULL,
    bb_lower DECIMAL(20, 8) NULL,
    adx DECIMAL(8, 4) NULL,
    cci DECIMAL(8, 4) NULL,
    momentum DECIMAL(8, 4) NULL,
    atr DECIMAL(20, 8) NULL,
    volume_ratio DECIMAL(10, 4) NULL,
    price_change DECIMAL(10, 6) NULL,
    volatility DECIMAL(10, 6) NULL,
    spread DECIMAL(20, 8) NULL,
    session_hour INT NULL,
    day_of_week INT NULL,
    month INT NULL,
    breakout_level DECIMAL(20, 8) NULL,
    retest_level DECIMAL(20, 8) NULL,
    swing_point DECIMAL(20, 8) NULL,
    breakout_direction VARCHAR(20) NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (trade_id) REFERENCES trades(trade_id) ON DELETE CASCADE,
    INDEX idx_trade_id (trade_id),
    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_recorded_at (recorded_at)
);

-- Create strategy performance table
CREATE TABLE IF NOT EXISTS strategy_performance (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    strategy_name VARCHAR(100) NOT NULL,
    strategy_version VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    period_start DATETIME NOT NULL,
    period_end DATETIME NOT NULL,
    total_trades INT NOT NULL DEFAULT 0,
    winning_trades INT NOT NULL DEFAULT 0,
    losing_trades INT NOT NULL DEFAULT 0,
    total_profit DECIMAL(20, 8) NOT NULL DEFAULT 0,
    total_loss DECIMAL(20, 8) NOT NULL DEFAULT 0,
    net_profit DECIMAL(20, 8) NOT NULL DEFAULT 0,
    win_rate DECIMAL(5, 2) NOT NULL DEFAULT 0,
    profit_factor DECIMAL(10, 4) NOT NULL DEFAULT 0,
    average_win DECIMAL(20, 8) NOT NULL DEFAULT 0,
    average_loss DECIMAL(20, 8) NOT NULL DEFAULT 0,
    largest_win DECIMAL(20, 8) NOT NULL DEFAULT 0,
    largest_loss DECIMAL(20, 8) NOT NULL DEFAULT 0,
    max_drawdown DECIMAL(20, 8) NOT NULL DEFAULT 0,
    sharpe_ratio DECIMAL(10, 4) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_strategy_period (strategy_name, strategy_version, symbol, timeframe, period_start, period_end),
    INDEX idx_strategy_symbol (strategy_name, strategy_version, symbol, timeframe),
    INDEX idx_period (period_start, period_end)
);

-- Create ML model performance table
CREATE TABLE IF NOT EXISTS ml_model_performance (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    model_type ENUM('BUY', 'SELL', 'COMBINED') NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    period_start DATETIME NOT NULL,
    period_end DATETIME NOT NULL,
    total_predictions INT NOT NULL DEFAULT 0,
    correct_predictions INT NOT NULL DEFAULT 0,
    accuracy DECIMAL(5, 4) NOT NULL DEFAULT 0,
    average_confidence DECIMAL(5, 4) NOT NULL DEFAULT 0,
    average_prediction_probability DECIMAL(5, 4) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_model_period (model_name, model_type, symbol, timeframe, period_start, period_end),
    INDEX idx_model_symbol (model_name, model_type, symbol, timeframe),
    INDEX idx_period (period_start, period_end)
);

-- Create daily statistics table
CREATE TABLE IF NOT EXISTS daily_statistics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    strategy_name VARCHAR(100) NOT NULL,
    strategy_version VARCHAR(20) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    date DATE NOT NULL,
    total_trades INT NOT NULL DEFAULT 0,
    winning_trades INT NOT NULL DEFAULT 0,
    losing_trades INT NOT NULL DEFAULT 0,
    net_profit DECIMAL(20, 8) NOT NULL DEFAULT 0,
    win_rate DECIMAL(5, 2) NOT NULL DEFAULT 0,
    average_profit_per_trade DECIMAL(20, 8) NOT NULL DEFAULT 0,
    max_drawdown DECIMAL(20, 8) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_daily_stats (strategy_name, strategy_version, symbol, timeframe, date),
    INDEX idx_strategy_date (strategy_name, strategy_version, symbol, timeframe, date)
);
