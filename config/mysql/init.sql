-- MySQL Initialization Script for Trading Strategies Database
-- This script runs when the MySQL container starts for the first time

-- Create the database if it doesn't exist
CREATE DATABASE IF NOT EXISTS breakout_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Use the database
USE breakout_analytics;

-- Create user if it doesn't exist (using mysql_native_password for compatibility)
CREATE USER IF NOT EXISTS 'breakout_user'@'%' IDENTIFIED WITH mysql_native_password BY 'breakout_password_2024';

-- Grant privileges to the user
GRANT ALL PRIVILEGES ON breakout_analytics.* TO 'breakout_user'@'%';

-- Grant additional privileges for development
GRANT CREATE, DROP, ALTER, INDEX, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER ON breakout_analytics.* TO 'breakout_user'@'%';

-- Flush privileges
FLUSH PRIVILEGES;

-- Create basic tables structure (these will be created by your application)
-- The actual table creation is handled by your Python application using migrations

-- Show created databases and users
SHOW DATABASES;
SELECT User, Host FROM mysql.user WHERE User = 'breakout_user';
