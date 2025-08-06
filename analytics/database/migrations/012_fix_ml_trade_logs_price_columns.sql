-- Migration: 012_fix_ml_trade_logs_price_columns.sql
-- Description: Fix price column sizes in ml_trade_logs and ml_trade_closes tables to handle BTCUSD prices
-- Date: 2025-08-05

-- Fix ml_trade_logs table price columns
ALTER TABLE ml_trade_logs
MODIFY COLUMN entry_price DECIMAL(20, 8) NOT NULL,
MODIFY COLUMN stop_loss DECIMAL(20, 8) NOT NULL,
MODIFY COLUMN take_profit DECIMAL(20, 8) NOT NULL,
MODIFY COLUMN close_price DECIMAL(20, 8) DEFAULT 0.0;

-- Fix ml_trade_closes table price columns
ALTER TABLE ml_trade_closes
MODIFY COLUMN close_price DECIMAL(20, 8) NOT NULL;

-- Add comment explaining the change
ALTER TABLE ml_trade_logs COMMENT = 'Stores trade entry data with ML features for model retraining (updated price columns for BTCUSD support)';
ALTER TABLE ml_trade_closes COMMENT = 'Stores trade exit data with results for model retraining (updated price columns for BTCUSD support)';
