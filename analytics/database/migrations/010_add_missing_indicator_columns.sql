-- Migration: 010_add_missing_indicator_columns.sql
-- Description: Add missing indicator columns that the EA is sending
-- Date: 2025-01-04

-- Add williams_r column (Williams %R indicator)
ALTER TABLE market_conditions
ADD COLUMN williams_r DECIMAL(8,4) NULL COMMENT 'Williams %R indicator value';

-- Add force_index column (Force Index indicator)
ALTER TABLE market_conditions
ADD COLUMN force_index DECIMAL(15,4) NULL COMMENT 'Force Index indicator value';

-- Verify the columns have been added
SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions'
AND COLUMN_NAME IN ('williams_r', 'force_index')
ORDER BY COLUMN_NAME;

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Added williams_r and force_index columns for complete indicator data';
