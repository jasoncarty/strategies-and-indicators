-- Migration: 003_add_ml_trade_logging.sql
-- Description: Add tables for ML trade logging and retraining data
-- Date: 2025-07-30

-- Table for ML trade log data (trade entry with features)
CREATE TABLE IF NOT EXISTS ml_trade_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    trade_id VARCHAR(255) NOT NULL,
    strategy VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    direction ENUM('BUY', 'SELL', 'TEST') NOT NULL,
    entry_price DECIMAL(10, 5) NOT NULL,
    stop_loss DECIMAL(10, 5) NOT NULL,
    take_profit DECIMAL(10, 5) NOT NULL,
    lot_size DECIMAL(10, 2) NOT NULL,
    ml_prediction DECIMAL(10, 4) NOT NULL,
    ml_confidence DECIMAL(10, 4) NOT NULL,
    ml_model_type VARCHAR(50) NOT NULL,
    ml_model_key VARCHAR(100) NOT NULL,
    trade_time BIGINT NOT NULL,
    features_json JSON NOT NULL,
    status ENUM('OPEN', 'CLOSED', 'CANCELLED', 'TEST') DEFAULT 'OPEN',
    profit_loss DECIMAL(10, 2) DEFAULT 0.0,
    close_price DECIMAL(10, 5) DEFAULT 0.0,
    close_time BIGINT DEFAULT 0,
    exit_reason VARCHAR(50) DEFAULT '',
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_trade_id (trade_id),
    INDEX idx_strategy (strategy),
    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_trade_time (trade_time),
    INDEX idx_ml_model (ml_model_type, ml_model_key)
);

-- Table for ML trade close data (trade exit results)
CREATE TABLE IF NOT EXISTS ml_trade_closes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    trade_id VARCHAR(255) NOT NULL,
    strategy VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    close_price DECIMAL(10, 5) NOT NULL,
    profit_loss DECIMAL(10, 2) NOT NULL,
    profit_loss_pips DECIMAL(10, 1) NOT NULL,
    close_time BIGINT NOT NULL,
    exit_reason VARCHAR(50) NOT NULL,
    status ENUM('OPEN', 'CLOSED', 'CANCELLED', 'TEST') NOT NULL,
    success BOOLEAN NOT NULL,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_trade_id (trade_id),
    INDEX idx_strategy (strategy),
    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_close_time (close_time),
    INDEX idx_success (success)
);

-- Add comments for documentation
ALTER TABLE ml_trade_logs COMMENT = 'Stores trade entry data with ML features for model retraining';
ALTER TABLE ml_trade_closes COMMENT = 'Stores trade exit data with results for model retraining';
