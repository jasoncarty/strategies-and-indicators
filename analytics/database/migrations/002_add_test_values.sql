-- Migration: 002_add_test_values.sql
-- Description: Add TEST values to ENUM fields for testing scenarios
-- Date: 2025-07-30

-- Update trades table to allow TEST direction and status
ALTER TABLE trades
MODIFY COLUMN direction ENUM('BUY', 'SELL', 'TEST') NOT NULL,
MODIFY COLUMN status ENUM('OPEN', 'CLOSED', 'CANCELLED', 'TEST') DEFAULT 'OPEN';

-- Update ml_predictions table to allow TEST model type
ALTER TABLE ml_predictions
MODIFY COLUMN model_type ENUM('BUY', 'SELL', 'COMBINED', 'TEST') NOT NULL;
