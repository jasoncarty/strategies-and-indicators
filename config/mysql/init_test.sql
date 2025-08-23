-- Test Database Initialization
-- This script runs only in the test MySQL container
-- It's completely separate from the main development/production database

-- Create test database (already created by MYSQL_DATABASE env var, but ensure it exists)
CREATE DATABASE IF NOT EXISTS test_breakout_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create test user with appropriate permissions
CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY 'test_password_2024';

-- Grant permissions to test user
GRANT ALL PRIVILEGES ON test_breakout_analytics.* TO 'test_user'@'%';
GRANT ALL PRIVILEGES ON test_breakout_analytics.* TO 'root'@'%';

-- Flush privileges
FLUSH PRIVILEGES;

-- Use test database
USE test_breakout_analytics;

-- Create basic test tables (migrations will handle the rest)
CREATE TABLE IF NOT EXISTS migration_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('SUCCESS', 'FAILED') DEFAULT 'SUCCESS',
    error_message TEXT NULL,
    UNIQUE KEY unique_migration (filename),
    INDEX idx_executed_at (executed_at)
) COMMENT = 'Tracks which database migrations have been executed for testing';

-- Log successful initialization
INSERT INTO migration_log (filename, status) VALUES ('init_test.sql', 'SUCCESS');
