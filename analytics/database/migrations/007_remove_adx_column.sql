-- Migration: 007_remove_adx_column.sql
-- Description: Remove adx column that was removed from ML training
-- Date: 2025-01-XX

-- Remove adx column from market_conditions table (only if it exists)
SET @sql = (SELECT IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'adx') > 0,
    'ALTER TABLE market_conditions DROP COLUMN adx',
    'SELECT "adx column does not exist" as message'
));
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Removed adx column as it was removed from ML training';

-- Verify the column has been removed
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions'
AND COLUMN_NAME = 'adx';
