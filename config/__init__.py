"""
Configuration management for the trading strategies project
Supports multiple environments: development, testing, production
"""

import os
from pathlib import Path
from typing import Dict, Any, Optional
import json
import re
from dataclasses import dataclass, asdict
from dotenv import load_dotenv

@dataclass
class DatabaseConfig:
    """Database configuration settings"""
    host: str
    port: int
    name: str
    user: str
    password: str
    charset: str = 'utf8mb4'

    @property
    def connection_string(self) -> str:
        return f"mysql+pymysql://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}?charset={self.charset}"

@dataclass
class ServiceConfig:
    """Service configuration settings"""
    host: str
    port: int
    debug: bool
    workers: int = 1
    api_url: Optional[str] = None

    @property
    def url(self) -> str:
        return f"http://{self.host}:{self.port}"

@dataclass
class MLConfig:
    """ML service configuration settings"""
    models_dir: str
    analytics_url: str
    max_request_size: int = 16 * 1024 * 1024  # 16MB
    confidence_thresholds: Dict[str, float] = None

    def __post_init__(self):
        if self.confidence_thresholds is None:
            self.confidence_thresholds = {
                'healthy': 0.3,
                'warning': 0.6,
                'critical': 0.7
            }

@dataclass
class ServiceLoggingConfig:
    """Service-specific logging configuration"""
    file_path: str
    max_bytes: int = 10 * 1024 * 1024  # 10MB
    backup_count: int = 5

@dataclass
class LoggingConfig:
    """Logging configuration settings"""
    level: str
    format: str
    services: Dict[str, ServiceLoggingConfig]
    max_bytes: int = 10 * 1024 * 1024  # 10MB
    backup_count: int = 5

    def get_service_log_path(self, service_name: str) -> str:
        """Get log file path for a specific service"""
        if service_name in self.services:
            return self.services[service_name].file_path
        # Fallback to general log path
        return self.services.get('general', self.services['analytics']).file_path

@dataclass
class SecurityConfig:
    """Security configuration settings"""
    secret_key: str
    cors_origins: list
    jwt_secret: str
    api_rate_limit: int = 100  # requests per minute

class Config:
    """Main configuration class"""

    def __init__(self, environment: str = None):
        # Load environment variables from .env file
        load_dotenv()

        self.environment = environment or os.getenv('ENVIRONMENT', 'development')
        self.config_dir = Path(__file__).parent
        self.load_config()

    def _substitute_env_vars(self, template_content: str) -> Dict[str, Any]:
        """Substitute environment variables in template content"""
        def replace_var(match):
            var_name = match.group(1)
            return os.getenv(var_name, '')

        # Replace ${VAR_NAME} with environment variable values
        substituted_content = re.sub(r'\$\{([^}]+)\}', replace_var, template_content)

        try:
            return json.loads(substituted_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON after environment variable substitution: {e}")

    def load_config(self):
        """Load configuration from environment-specific file or template"""
        config_file = self.config_dir / f"{self.environment}.json"
        template_file = self.config_dir / "templates" / f"{self.environment}.json.template"

        if config_file.exists():
            # Load from actual config file
            with open(config_file, 'r') as f:
                config_data = json.load(f)
        elif template_file.exists():
            # Load from template and substitute environment variables
            with open(template_file, 'r') as f:
                template_content = f.read()
            config_data = self._substitute_env_vars(template_content)
        else:
            # Fallback to development template
            template_file = self.config_dir / "templates" / "development.json.template"
            with open(template_file, 'r') as f:
                template_content = f.read()
            config_data = self._substitute_env_vars(template_content)

        # Load database config
        db_config = config_data.get('database', {})
        self.database = DatabaseConfig(
            host=db_config.get('host', 'localhost'),
            port=db_config.get('port', 3306),
            name=db_config.get('name', 'breakout_analytics'),
            user=db_config.get('user', 'breakout_user'),
            password=db_config.get('password', 'breakout_password_2024')
        )

        # Load service configs
        services = config_data.get('services', {})

        self.analytics = ServiceConfig(
            host=services.get('analytics', {}).get('host', '0.0.0.0'),
            port=services.get('analytics', {}).get('port', 5001),
            debug=services.get('analytics', {}).get('debug', True),
            workers=services.get('analytics', {}).get('workers', 1)
        )

        self.ml_service = ServiceConfig(
            host=services.get('ml_service', {}).get('host', '0.0.0.0'),
            port=services.get('ml_service', {}).get('port', 5002),
            debug=services.get('ml_service', {}).get('debug', True),
            workers=services.get('ml_service', {}).get('workers', 1)
        )

        self.dashboard = ServiceConfig(
            host=services.get('dashboard', {}).get('host', 'localhost'),
            port=services.get('dashboard', {}).get('port', 3000),
            debug=services.get('dashboard', {}).get('debug', False),
            api_url=services.get('dashboard', {}).get('api_url', 'http://localhost:5001')
        )

        # Load ML config
        ml_config = config_data.get('ml', {})
        self.ml = MLConfig(
            models_dir=ml_config.get('models_dir', 'ML_Webserver/ml_models'),
            analytics_url=f"http://{self.analytics.host}:{self.analytics.port}",
            max_request_size=ml_config.get('max_request_size', 16 * 1024 * 1024),
            confidence_thresholds=ml_config.get('confidence_thresholds')
        )

        # Load logging config
        logging_config = config_data.get('logging', {})

        # Load service-specific logging configs
        services_logging = logging_config.get('services', {})
        service_logging_configs = {}

        for service_name, service_config in services_logging.items():
            service_logging_configs[service_name] = ServiceLoggingConfig(
                file_path=service_config.get('file_path', f'logs/{service_name}.log'),
                max_bytes=service_config.get('max_bytes', 10 * 1024 * 1024),
                backup_count=service_config.get('backup_count', 5)
            )

        self.logging = LoggingConfig(
            level=logging_config.get('level', 'INFO'),
            format=logging_config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s'),
            services=service_logging_configs,
            max_bytes=logging_config.get('max_bytes', 10 * 1024 * 1024),
            backup_count=logging_config.get('backup_count', 5)
        )

        # Load security config
        security_config = config_data.get('security', {})
        self.security = SecurityConfig(
            secret_key=security_config.get('secret_key', 'dev-secret-key-change-in-production'),
            cors_origins=security_config.get('cors_origins', ['http://localhost:3000']),
            jwt_secret=security_config.get('jwt_secret', 'dev-jwt-secret-change-in-production'),
            api_rate_limit=security_config.get('api_rate_limit', 100)
        )

    def get_database_url(self) -> str:
        """Get database connection URL"""
        return self.database.connection_string

    def get_analytics_url(self) -> str:
        """Get analytics service URL"""
        return self.analytics.url

    def get_ml_service_url(self) -> str:
        """Get ML service URL"""
        return self.ml_service.url

    def to_dict(self) -> Dict[str, Any]:
        """Convert config to dictionary"""
        return {
            'environment': self.environment,
            'database': asdict(self.database),
            'analytics': asdict(self.analytics),
            'ml_service': asdict(self.ml_service),
            'dashboard': asdict(self.dashboard),
            'ml': asdict(self.ml),
            'logging': asdict(self.logging),
            'security': asdict(self.security)
        }

    def __str__(self) -> str:
        return f"Config(environment={self.environment})"

    def get_test_service_ports(self) -> Dict[str, int]:
        """Get test service ports - single source of truth for testing"""
        return {
            'analytics': self.analytics.port,
            'ml_service': self.ml_service.port
        }

    def get_test_analytics_port(self) -> int:
        """Get test analytics service port"""
        return self.analytics.port

    def get_test_ml_port(self) -> int:
        """Get test ML service port"""
        return self.ml_service.port

    def get_test_database_config(self) -> DatabaseConfig:
        """Get test database configuration"""
        return self.database

# Global config instance
config = Config()

# Convenience functions
def get_config() -> Config:
    """Get the global configuration instance"""
    return config

def get_database_config() -> DatabaseConfig:
    """Get database configuration"""
    return config.database

def get_analytics_config() -> ServiceConfig:
    """Get analytics service configuration"""
    return config.analytics

def get_ml_service_config() -> ServiceConfig:
    """Get ML service configuration"""
    return config.ml_service

def get_ml_config() -> MLConfig:
    """Get ML configuration"""
    return config.ml

def get_logging_config() -> LoggingConfig:
    """Get logging configuration"""
    return config.logging

def get_service_log_path(service_name: str) -> str:
    """Get log file path for a specific service"""
    return config.logging.get_service_log_path(service_name)

def get_dashboard_config() -> ServiceConfig:
    """Get dashboard configuration"""
    return config.dashboard
