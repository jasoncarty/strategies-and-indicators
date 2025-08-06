-- Migration: 013_fix_missing_trade_data.sql
-- Description: Fix missing stop_loss, take_profit, and duration_seconds in existing trades by copying from ml_trade_logs
-- Date: 2025-08-05

-- Update trades table with missing stop_loss and take_profit from ml_trade_logs
UPDATE trades t
JOIN ml_trade_logs ml ON t.trade_id = ml.trade_id
SET t.stop_loss = ml.stop_loss,
    t.take_profit = ml.take_profit
WHERE t.stop_loss = 0.0 OR t.take_profit = 0.0;

-- Update trades table with missing duration_seconds for closed trades
UPDATE trades
SET duration_seconds = TIMESTAMPDIFF(SECOND, entry_time, exit_time)
WHERE status = 'CLOSED'
  AND duration_seconds IS NULL
  AND entry_time IS NOT NULL
  AND exit_time IS NOT NULL;

-- Add comment explaining the data fix
ALTER TABLE trades COMMENT = 'Trades table with missing data fixed from ml_trade_logs';
