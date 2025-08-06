"""
Database configuration for BreakoutStrategy analytics
"""
import os
from typing import Dict, Any

class DatabaseConfig:
    """Database configuration class"""

    def __init__(self):
        # Check if we're in test mode
        if os.getenv('TEST_DATABASE'):
            # Test database settings
            self.host = os.getenv('TEST_DB_HOST', 'localhost')
            self.port = int(os.getenv('TEST_DB_PORT', 3306))
            self.database = os.getenv('TEST_DATABASE', 'test_breakout_analytics')
            self.user = os.getenv('TEST_DB_USER', 'breakout_user')
            self.password = os.getenv('TEST_DB_PASSWORD', 'breakout_password_2024')
        else:
            # Default local development settings
            self.host = os.getenv('DB_HOST', 'localhost')
            self.port = int(os.getenv('DB_PORT', 3306))
            self.database = os.getenv('DB_NAME', 'breakout_analytics')
            self.user = os.getenv('DB_USER', 'breakout_user')
            self.password = os.getenv('DB_PASSWORD', 'breakout_password_2024')

        self.charset = 'utf8mb4'

    def get_connection_string(self) -> str:
        """Get MySQL connection string"""
        return f"mysql+pymysql://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}?charset={self.charset}"

    def get_connection_params(self) -> Dict[str, Any]:
        """Get connection parameters as dictionary"""
        return {
            'host': self.host,
            'port': self.port,
            'database': self.database,
            'user': self.user,
            'password': self.password,
            'charset': self.charset,
            'autocommit': True
        }

# Global configuration instance
db_config = DatabaseConfig()

def get_database_config() -> Dict[str, Any]:
    """Get database configuration as dictionary"""
    return db_config.get_connection_params()
