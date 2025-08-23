"""
Logging setup utility for trading strategies services
Provides easy-to-use functions for setting up service-specific logging
"""

import logging
import logging.handlers
import os
from pathlib import Path
from typing import Optional
from config import get_service_log_path, get_logging_config

def setup_service_logging(
    service_name: str,
    logger_name: Optional[str] = None,
    log_level: Optional[str] = None
) -> logging.Logger:
    """
    Set up logging for a specific service

    Args:
        service_name: Name of the service (e.g., 'analytics', 'ml_service', 'webserver')
        logger_name: Name for the logger (defaults to service_name)
        log_level: Log level override (defaults to config level)

    Returns:
        Configured logger instance
    """
    # Get configuration
    config = get_logging_config()
    log_path = get_service_log_path(service_name)
    level = log_level or config.level
    logger_name = logger_name or service_name

    # Create logger
    logger = logging.getLogger(logger_name)
    logger.setLevel(getattr(logging, level.upper()))

    # Clear existing handlers to avoid duplicates
    logger.handlers.clear()

    # Create formatter
    formatter = logging.Formatter(config.format)

    # Create file handler with rotation
    log_dir = Path(log_path).parent
    log_dir.mkdir(parents=True, exist_ok=True)

    # Get service-specific logging config
    service_config = config.services.get(service_name, config.services.get('general'))
    if service_config:
        file_handler = logging.handlers.RotatingFileHandler(
            log_path,
            maxBytes=service_config.max_bytes,
            backupCount=service_config.backup_count
        )
    else:
        # Fallback to default config
        file_handler = logging.handlers.RotatingFileHandler(
            log_path,
            maxBytes=config.max_bytes,
            backupCount=config.backup_count
        )

    file_handler.setLevel(getattr(logging, level.upper()))
    file_handler.setFormatter(formatter)

    # Create console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, level.upper()))
    console_handler.setFormatter(formatter)

    # Add handlers to logger
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

    # Prevent propagation to root logger
    logger.propagate = False

    return logger

def get_service_logger(service_name: str) -> logging.Logger:
    """
    Get a logger for a specific service (creates if doesn't exist)

    Args:
        service_name: Name of the service

    Returns:
        Logger instance for the service
    """
    logger = logging.getLogger(service_name)

    # If logger doesn't have handlers, set it up
    if not logger.handlers:
        logger = setup_service_logging(service_name)

    return logger

def setup_analytics_logging() -> logging.Logger:
    """Set up logging for analytics service"""
    return setup_service_logging('analytics')

def setup_ml_service_logging() -> logging.Logger:
    """Set up logging for ML service"""
    return setup_service_logging('ml_service')

def setup_webserver_logging() -> logging.Logger:
    """Set up logging for webserver"""
    return setup_service_logging('webserver')

def setup_dashboard_logging() -> logging.Logger:
    """Set up logging for dashboard"""
    return setup_service_logging('dashboard')

def setup_general_logging() -> logging.Logger:
    """Set up general logging"""
    return setup_service_logging('general')

# Convenience function for quick setup
def quick_logger(service_name: str) -> logging.Logger:
    """
    Quick way to get a logger for a service

    Args:
        service_name: Name of the service

    Returns:
        Logger instance
    """
    return get_service_logger(service_name)
