-- Migration: 011_remove_atr_column.sql
-- Description: Remove ATR column from market_conditions table since it's not used by ML models
-- Date: 2025-01-04

-- Remove ATR column since it's not used by the ML models
ALTER TABLE market_conditions
DROP COLUMN atr;

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Removed ATR column - not used by ML models';

-- Verify the column has been removed
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions'
AND COLUMN_NAME = 'atr';
