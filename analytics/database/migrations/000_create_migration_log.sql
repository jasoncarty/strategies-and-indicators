-- Migration: 000_create_migration_log.sql
-- Description: Create migration log table to track executed migrations
-- Date: 2025-01-XX

-- Create migration log table to track which migrations have been executed
CREATE TABLE IF NOT EXISTS migration_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('SUCCESS', 'FAILED') DEFAULT 'SUCCESS',
    error_message TEXT NULL,

    UNIQUE KEY unique_migration (filename),
    INDEX idx_executed_at (executed_at)
) COMMENT = 'Tracks which database migrations have been executed';
