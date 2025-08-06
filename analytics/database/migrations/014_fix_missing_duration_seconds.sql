-- Migration: 014_fix_missing_duration_seconds.sql
-- Description: Fix missing duration_seconds in existing trades by calculating from entry and exit times
-- Date: 2025-08-06

-- Update trades table with missing duration_seconds for closed trades
-- Calculate duration from entry_time and exit_time
UPDATE trades
SET duration_seconds = TIMESTAMPDIFF(SECOND, entry_time, exit_time)
WHERE status = 'CLOSED'
  AND (duration_seconds IS NULL OR duration_seconds = 0)
  AND entry_time IS NOT NULL
  AND exit_time IS NOT NULL
  AND exit_time > entry_time;

-- Add comment explaining the duration fix
ALTER TABLE trades COMMENT = 'Trades table with missing duration_seconds fixed from entry/exit times';
