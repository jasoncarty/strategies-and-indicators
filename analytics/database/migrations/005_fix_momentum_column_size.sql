-- Migration 005: Fix momentum column size to handle larger values
-- Date: 2025-08-02
-- Description: Increase momentum column size to prevent overflow errors

-- Fix momentum column in market_conditions table
ALTER TABLE market_conditions MODIFY COLUMN momentum DECIMAL(12, 4) NULL;

-- Add comment to document the change
ALTER TABLE market_conditions COMMENT = 'Updated momentum column to DECIMAL(12,4) to handle larger momentum values';

-- Verify the change
SELECT COLUMN_NAME, DATA_TYPE, NUMERIC_PRECISION, NUMERIC_SCALE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'market_conditions' AND COLUMN_NAME = 'momentum';
