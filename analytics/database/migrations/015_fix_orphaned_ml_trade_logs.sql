-- Migration: 015_fix_orphaned_ml_trade_logs.sql
-- Description: Create placeholder trades for orphaned ML trade logs that were created before the fix
-- Date: 2025-08-06

-- Create placeholder trades for orphaned ML trade logs
-- Only for logs created after August 5th (when our fix was applied) and not test data
INSERT INTO trades (
    trade_id, symbol, timeframe, direction, entry_price, exit_price,
    stop_loss, take_profit, lot_size, profit_loss, profit_loss_pips,
    entry_time, exit_time, duration_seconds, status, strategy_name, strategy_version, account_id
)
SELECT
    ml.trade_id,
    ml.symbol,
    ml.timeframe,
    ml.direction,
    ml.entry_price,
    NULL as exit_price,
    ml.stop_loss,
    ml.take_profit,
    ml.lot_size,
    NULL as profit_loss,
    NULL as profit_loss_pips,
    FROM_UNIXTIME(ml.trade_time) as entry_time,
    NULL as exit_time,
    NULL as duration_seconds,
    ml.status,
    ml.strategy as strategy_name,
    '1.00' as strategy_version,
    'LIVE_ACCOUNT' as account_id
FROM ml_trade_logs ml
LEFT JOIN trades t ON ml.trade_id = t.trade_id
WHERE t.trade_id IS NULL
  AND ml.trade_time >= 1754400000  -- After August 5th, 2025
  AND ml.trade_id != '12345'       -- Exclude test data
  AND ml.trade_id NOT LIKE 'test%' -- Exclude test data
ON DUPLICATE KEY UPDATE
    symbol = VALUES(symbol),
    timeframe = VALUES(timeframe),
    direction = VALUES(direction),
    entry_price = VALUES(entry_price),
    stop_loss = VALUES(stop_loss),
    take_profit = VALUES(take_profit),
    lot_size = VALUES(lot_size),
    status = VALUES(status),
    strategy_name = VALUES(strategy_name);

-- Add comment explaining the orphaned logs fix
ALTER TABLE trades COMMENT = 'Trades table with orphaned ML trade logs fixed';
