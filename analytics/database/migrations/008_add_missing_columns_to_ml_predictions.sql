-- Migration: 008_add_missing_columns_to_ml_predictions.sql
-- Description: Add missing columns to ml_predictions table that the EA sends
-- Date: 2025-01-XX

-- Add missing columns to ml_predictions table
ALTER TABLE ml_predictions
ADD COLUMN symbol VARCHAR(20) NULL COMMENT 'Symbol from EA data',
ADD COLUMN timeframe VARCHAR(10) NULL COMMENT 'Timeframe from EA data',
ADD COLUMN strategy_name VARCHAR(100) NULL COMMENT 'Strategy name from EA data',
ADD COLUMN strategy_version VARCHAR(20) NULL COMMENT 'Strategy version from EA data';

-- Add comment to document the change
ALTER TABLE ml_predictions COMMENT = 'Added missing columns (symbol, timeframe, strategy_name, strategy_version) from EA data';

-- Verify the columns have been added
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ml_predictions'
AND COLUMN_NAME IN ('symbol', 'timeframe', 'strategy_name', 'strategy_version')
ORDER BY COLUMN_NAME;
