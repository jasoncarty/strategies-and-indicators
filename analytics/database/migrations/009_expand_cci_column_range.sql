-- Migration: 009_expand_cci_column_range.sql
-- Description: Expand cci column range to accommodate larger CCI values
-- Date: 2025-01-04

-- Update cci column to DECIMAL(10,4) to accommodate larger values
-- This allows range from -999999.9999 to +999999.9999
ALTER TABLE market_conditions
MODIFY COLUMN cci DECIMAL(10,4) COMMENT 'Commodity Channel Index - expanded range for extreme values';

-- Verify the column has been updated
SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE, COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions'
AND COLUMN_NAME = 'cci';

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Updated cci column to DECIMAL(10,4) to accommodate extreme CCI values';
