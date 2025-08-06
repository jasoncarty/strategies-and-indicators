-- Migration: 004_use_mt5_ticket_as_trade_id.sql
-- Description: Change trade_id fields to use MT5 ticket numbers instead of generated strings
-- Date: 2025-08-01

-- Drop foreign key constraints first
ALTER TABLE ml_predictions DROP FOREIGN KEY ml_predictions_ibfk_1;
ALTER TABLE market_conditions DROP FOREIGN KEY market_conditions_ibfk_1;

-- Update trades table to use BIGINT for trade_id (parent table first)
ALTER TABLE trades MODIFY COLUMN trade_id BIGINT UNIQUE NOT NULL;

-- Update ml_trade_logs table to use BIGINT for trade_id
ALTER TABLE ml_trade_logs MODIFY COLUMN trade_id BIGINT NOT NULL;

-- Update ml_trade_closes table to use BIGINT for trade_id
ALTER TABLE ml_trade_closes MODIFY COLUMN trade_id BIGINT NOT NULL;

-- Update ml_predictions table to use BIGINT for trade_id
ALTER TABLE ml_predictions MODIFY COLUMN trade_id BIGINT NOT NULL;

-- Update market_conditions table to use BIGINT for trade_id
ALTER TABLE market_conditions MODIFY COLUMN trade_id BIGINT NOT NULL;

-- Recreate foreign key constraints
ALTER TABLE ml_predictions ADD CONSTRAINT ml_predictions_ibfk_1
    FOREIGN KEY (trade_id) REFERENCES trades(trade_id) ON DELETE CASCADE;

ALTER TABLE market_conditions ADD CONSTRAINT market_conditions_ibfk_1
    FOREIGN KEY (trade_id) REFERENCES trades(trade_id) ON DELETE CASCADE;

-- Add comments for documentation
ALTER TABLE ml_trade_logs COMMENT = 'Stores trade entry data with ML features for model retraining (uses MT5 ticket as trade_id)';
ALTER TABLE ml_trade_closes COMMENT = 'Stores trade exit data with results for model retraining (uses MT5 ticket as trade_id)';
ALTER TABLE trades COMMENT = 'Main trade records (uses MT5 ticket as trade_id)';
