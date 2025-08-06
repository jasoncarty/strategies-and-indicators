-- Migration: 006_remove_breakout_columns.sql
-- Description: Remove breakout-related columns that were removed from ML training
-- Date: 2025-01-XX

-- Remove breakout-related columns from market_conditions table (only if they exist)
-- Check and drop breakout_level column if it exists
SET @sql = (SELECT IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'breakout_level') > 0,
    'ALTER TABLE market_conditions DROP COLUMN breakout_level',
    'SELECT "breakout_level column does not exist" as message'
));
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Check and drop retest_level column if it exists
SET @sql = (SELECT IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'retest_level') > 0,
    'ALTER TABLE market_conditions DROP COLUMN retest_level',
    'SELECT "retest_level column does not exist" as message'
));
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Check and drop swing_point column if it exists
SET @sql = (SELECT IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'swing_point') > 0,
    'ALTER TABLE market_conditions DROP COLUMN swing_point',
    'SELECT "swing_point column does not exist" as message'
));
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Check and drop breakout_direction column if it exists
SET @sql = (SELECT IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'breakout_direction') > 0,
    'ALTER TABLE market_conditions DROP COLUMN breakout_direction',
    'SELECT "breakout_direction column does not exist" as message'
));
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Removed breakout-related columns (breakout_level, retest_level, swing_point, breakout_direction) as they were removed from ML training';

-- Verify the columns have been removed
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions'
AND COLUMN_NAME IN ('breakout_level', 'retest_level', 'swing_point', 'breakout_direction');
