# Configuration Management & Deployment Guide

This document explains the new configuration management system and deployment strategy for the Trading Strategies project.

## 🏗️ Architecture Overview

The project is structured as a **monorepo** containing multiple services:

- **Analytics Service** - Database analytics and model health monitoring
- **ML Prediction Service** - Real-time ML predictions for trading
- **MT5 Strategies & Indicators** - MetaTrader 5 Expert Advisors
- **Shared Models & Utilities** - Common ML models and utilities

### 📁 Important Directory Structure Notes

**ML Models Location:**
- **Actual models**: `ML_Webserver/ml_models/` - Contains all trained ML models
- **Root models**: `ml_models/` - Currently empty, kept for future use
- **Test models**: `tests/test_models/` - Contains models for testing

**Why this structure?**
- The ML service was originally designed to look in `ML_Webserver/ml_models/`
- This keeps models close to the service that uses them
- The root `ml_models/` directory can be used for shared models in the future

## ⚙️ Configuration Management

### Environment-Based Configuration

The system now supports multiple environments through JSON configuration files:

```
config/
├── __init__.py              # Configuration management module
├── development.json         # Development environment settings
├── testing.json            # Testing environment settings
└── production.json         # Production environment settings
```

### Configuration Structure

Each environment configuration includes:

```json
{
  "environment": "development",
  "database": {
    "host": "localhost",
    "port": 3306,
    "name": "breakout_analytics",
    "user": "breakout_user",
    "password": "breakout_password_2024"
  },
  "services": {
    "analytics": {
      "host": "0.0.0.0",
      "port": 5001,
      "debug": true,
      "workers": 1
    },
    "ml_service": {
      "host": "0.0.0.0",
      "port": 5002,
      "debug": true,
      "workers": 1
    }
  },
  "ml": {
    "models_dir": "ML_Webserver/ml_models",
    "max_request_size": 16777216,
    "confidence_thresholds": {
      "healthy": 0.3,
      "warning": 0.6,
      "critical": 0.7
    }
  },
  "logging": {
    "level": "DEBUG",
    "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    "file_path": "logs/app.log"
  },
  "security": {
    "secret_key": "dev-secret-key",
    "cors_origins": ["http://localhost:3000"],
    "jwt_secret": "dev-jwt-secret",
    "api_rate_limit": 1000
  }
}
```

### Using Configuration in Code

```python
from config import get_config, get_database_config, get_ml_config

# Get global config
config = get_config()

# Get specific configs
db_config = get_database_config()
ml_config = get_ml_config()

# Use configuration
analytics_url = config.get_analytics_url()
database_url = config.get_database_url()
models_dir = ml_config.models_dir
```

### Models Directory Configuration

The `models_dir` configuration points to different locations based on environment:

- **Development**: `ML_Webserver/ml_models` - Uses actual trained models
- **Testing**: `tests/test_models` - Uses lightweight test models
- **Production**: `/opt/trading/ML_Webserver/ml_models` - Uses production models

This ensures that:
- Development uses real models for accurate testing
- Testing uses lightweight models for fast CI/CD
- Production uses the correct model path on the server

### Logging Configuration

The system now supports **service-specific logging** with separate log files for each service:

```json
"logging": {
  "level": "INFO",
  "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
  "services": {
    "analytics": {
      "file_path": "logs/analytics.log",
      "max_bytes": 10485760,
      "backup_count": 5
    },
    "ml_service": {
      "file_path": "logs/ml_service.log",
      "max_bytes": 10485760,
      "backup_count": 5
    },
    "webserver": {
      "file_path": "logs/webserver.log",
      "max_bytes": 10485760,
      "backup_count": 5
    },
    "general": {
      "file_path": "logs/general.log",
      "max_bytes": 10485760,
      "backup_count": 5
    }
  }
}
```

**Benefits of Service-Specific Logging:**
- ✅ **Separate log files** - No more mixed-up logs
- ✅ **Independent rotation** - Each service can have different log sizes
- ✅ **Easier debugging** - Find issues in specific services quickly
- ✅ **Better organization** - Clear separation of concerns
- ✅ **Scalable** - Easy to add new services

**Environment Variables for Logging:**
```bash
# Service-specific log paths
ANALYTICS_LOG_PATH=logs/analytics.log
ML_SERVICE_LOG_PATH=logs/ml_service.log
WEBSERVER_LOG_PATH=logs/webserver.log
DASHBOARD_LOG_PATH=logs/dashboard.log
GENERAL_LOG_PATH=logs/general.log
```

**Dashboard Configuration:**
```bash
# Dashboard service
DASHBOARD_PORT=3000
DASHBOARD_API_URL=http://analytics:5001  # For Docker
# DASHBOARD_API_URL=http://localhost:5001  # For local development
```

**Nginx Configuration:**
```bash
# Worker and connection settings
NGINX_WORKER_CONNECTIONS=1024
NGINX_KEEPALIVE_TIMEOUT=65
NGINX_CLIENT_MAX_BODY_SIZE=16M

# Rate limiting
NGINX_API_RATE_LIMIT=10      # Requests per second for analytics
NGINX_ML_RATE_LIMIT=5        # Requests per second for ML service
NGINX_API_BURST=20           # Burst allowance for analytics
NGINX_ML_BURST=10            # Burst allowance for ML service

# Proxy timeouts
NGINX_PROXY_CONNECT_TIMEOUT=30
NGINX_PROXY_SEND_TIMEOUT=30
NGINX_PROXY_READ_TIMEOUT=30
```

**Using Service-Specific Logging in Code:**

```python
# Option 1: Use the utility functions
from utils.logging_setup import setup_analytics_logging, setup_ml_service_logging

# Analytics service
logger = setup_analytics_logging()
logger.info("Analytics service started")

# ML service
logger = setup_ml_service_logging()
logger.info("ML service started")

# Option 2: Quick logger function
from utils.logging_setup import quick_logger

analytics_logger = quick_logger('analytics')
ml_logger = quick_logger('ml_service')
webserver_logger = quick_logger('webserver')

# Option 3: Direct configuration access
from config import get_service_log_path

analytics_log_path = get_service_log_path('analytics')
ml_log_path = get_service_log_path('ml_service')
```

**Log File Structure:**
```
logs/
├── analytics.log          # Analytics service logs
├── ml_service.log         # ML prediction service logs
├── webserver.log          # Web server logs
├── general.log            # General system logs
└── old_logs/              # Rotated log files
    ├── analytics.log.1
    ├── ml_service.log.1
    └── webserver.log.1
```

## 🐳 Docker Deployment

The project includes Docker support for easy deployment and development:

### Docker Compose Configuration

The `docker-compose.yml` file now uses **environment variables** instead of hardcoded values:

```yaml
# Before (hardcoded) ❌
ports:
  - "5001:5001"
  - "5002:5002"

environment:
  - MYSQL_ROOT_PASSWORD=breakout_root_2024
  - MYSQL_DATABASE=breakout_analytics

# After (environment-based) ✅
ports:
  - "${ANALYTICS_PORT:-5001}:${ANALYTICS_PORT:-5001}"
  - "${ML_SERVICE_PORT:-5002}:${ML_SERVICE_PORT:-5002}"

environment:
  - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-breakout_root_2024}
  - MYSQL_DATABASE=${DB_NAME:-breakout_analytics}
```

### Docker Environment Management

Use the `docker_env.sh` script to manage Docker environments:

```bash
# Setup Docker environment
./scripts/docker_env.sh setup development
./scripts/docker_env.sh setup testing
./scripts/docker_env.sh setup production

# Switch environments
./scripts/docker_env.sh switch testing

# Check current environment
./scripts/docker_env.sh current

# Validate configuration
./scripts/docker_env.sh validate

# List available environments
./scripts/docker_env.sh list
```

### Docker Environment Files

- **`docker.env.example`**: Template with all Docker variables
- **`docker.env`**: Your actual Docker configuration (created by setup script)
- **`.env`**: General application configuration

### Docker Infrastructure

The project includes complete Docker infrastructure:

**Dockerfiles:**
- **`docker/analytics.Dockerfile`**: Analytics service container (configurable ports)
- **`docker/ml_service.Dockerfile`**: ML prediction service container (configurable ports)

**Nginx Configuration:**
- **`docker/nginx/nginx.conf.template`**: Template with configurable settings
- **`docker/nginx/nginx.conf`**: Generated configuration (auto-created)
- **`docker/nginx/ssl/`: SSL certificates directory

**Database:**
- **`config/mysql/init.sql`**: MySQL initialization script

**Development Scripts:**
- **`scripts/docker_dev.sh`**: Docker development helper

**Docker Build Configuration:**
- **`docker/build.env.example`**: Template for build arguments
- **`docker/build.env`**: Your actual build configuration (auto-created)
- **Build arguments**: Ports, hosts, Python version, image tags

**Using Docker Development Script:**
```bash
# Build all images
./scripts/docker_dev.sh build

# Build specific service
./scripts/docker_dev.sh build analytics

# Start all services
./scripts/docker_dev.sh start

# View logs
./scripts/docker_dev.sh logs

# View specific service logs
./scripts/docker_dev.sh logs ml_service

# Open shell in container
./scripts/docker_dev.sh shell analytics

# Check service status
./scripts/docker_dev.sh status

# Clean up everything
./scripts/docker_dev.sh clean
```

**Key Docker Environment Variables:**
```bash
# Database
DB_HOST=mysql                    # Use 'mysql' for Docker, 'localhost' for external
DB_PORT=3306
DB_NAME=breakout_analytics
DB_USER=breakout_user
DB_PASSWORD=breakout_password_2024
MYSQL_ROOT_PASSWORD=breakout_root_2024

# Service Ports (host ports for port mapping)
ANALYTICS_PORT=5001
ML_SERVICE_PORT=5002
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

# Environment
ENVIRONMENT=development
```

### Local Development

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Services

- **MySQL** (Port 3306) - Database
- **Analytics** (Port 5001) - Analytics service
- **ML Service** (Port 5002) - ML prediction service
- **Dashboard** (Port 3000) - React dashboard application
- **Nginx** (Port 80/443) - Reverse proxy

> **Note**: Redis has been removed for low-traffic scenarios. It can be easily added back later for caching, rate limiting, and performance optimization when needed.
>
> **To add Redis later**: Run `./scripts/add_redis.sh` when you need caching, rate limiting, or performance optimization.

### Dashboard Configuration

The React dashboard has its own configuration system:

**Setup Dashboard Environment:**
```bash
# Setup for development
./scripts/setup_dashboard.sh setup development

# Setup for testing
./scripts/setup_dashboard.sh setup testing

# Setup for production
./scripts/setup_dashboard.sh setup production

# Check current configuration
./scripts/setup_dashboard.sh current
```

**Dashboard Environment Variables:**
```bash
# API Configuration
REACT_APP_API_URL=http://localhost:5001

# Build Configuration
REACT_APP_ENVIRONMENT=development
REACT_APP_VERSION=0.1.0

# Feature Flags
REACT_APP_ENABLE_ML_PREDICTIONS=true
REACT_APP_ENABLE_MODEL_HEALTH=true
REACT_APP_ENABLE_TRADE_ANALYTICS=true
```

**Dashboard Logging:**
```python
from utils.logging_setup import setup_dashboard_logging

logger = setup_dashboard_logging()
logger.info("Dashboard started successfully")
```

## ☁️ Cloud Deployment

### Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **SSH key pair** for EC2 access
3. **Docker** and **Docker Compose** installed locally

### Deployment Commands

```bash
# Deploy to AWS (production)
./deploy/cloud_deploy.sh production aws us-east-1 t3.medium

# Deploy to AWS (testing)
./deploy/cloud_deploy.sh testing aws us-west-2 t3.small

# Deploy locally with Docker
./deploy/cloud_deploy.sh development docker

# Show help
./deploy/cloud_deploy.sh --help
```

### AWS Deployment Process

1. **Security Group Creation** - Creates firewall rules for required ports
2. **EC2 Instance Launch** - Launches Ubuntu instance with specified type
3. **Docker Installation** - Installs Docker and Docker Compose
4. **Service Deployment** - Copies code and starts services
5. **Health Check** - Verifies all services are running

### Security Considerations

- **Database passwords** should be changed in production
- **Secret keys** must be secure random strings
- **CORS origins** should be restricted to your domains
- **API rate limits** should be appropriate for production load

## 🔄 Migration from Old System

### Step 1: Update Service Code

Replace hardcoded values with configuration calls:

```python
# Old way
analytics_url = 'http://localhost:5001'

# New way
from config import get_config
config = get_config()
analytics_url = config.get_analytics_url()
```

### Step 2: Update Environment Variables

```bash
# Set environment
export ENVIRONMENT=development

# Or use .env file
echo "ENVIRONMENT=development" > .env
```

### Step 3: Test Configuration

```bash
# Test configuration loading
python -c "from config import get_config; print(get_config())"

# Run tests with new config
ENVIRONMENT=testing python -m pytest tests/
```

## 🧪 Testing

### Environment-Specific Testing

```bash
# Test with development config
ENVIRONMENT=development python -m pytest

# Test with testing config
ENVIRONMENT=testing python -m pytest

# Test with production config (be careful!)
ENVIRONMENT=production python -m pytest
```

### Configuration Testing

```python
def test_config_loading():
    from config import get_config

    # Test development config
    config = get_config()
    assert config.environment == 'development'
    assert config.database.host == 'localhost'
    assert config.analytics.port == 5001
```

## 📁 File Structure

```
strategies-and-indicators/
├── config/                    # Configuration management
│   ├── __init__.py
│   ├── development.json
│   ├── testing.json
│   └── production.json
├── deploy/                    # Deployment scripts
│   └── cloud_deploy.sh
├── docker/                    # Docker configurations
│   ├── analytics.Dockerfile
│   ├── ml_service.Dockerfile
│   └── nginx/
├── docker-compose.yml         # Local development
├── analytics/                 # Analytics service
├── ML_Webserver/             # ML prediction service
│   └── ml_models/            # ML models (actual location)
├── tests/                     # Test suite
│   └── test_models/          # Test models
├── ml_models/                 # Root models directory (currently empty)
└── requirements.txt           # Python dependencies
```

## 🚀 Next Steps

### Immediate Actions

1. **Update existing services** to use the new configuration system
2. **Test configuration loading** in all environments
3. **Update deployment scripts** with your specific requirements
4. **Secure production configurations** with proper secrets

### Future Enhancements

1. **Secrets Management** - Integrate with AWS Secrets Manager or HashiCorp Vault
2. **Configuration Validation** - Add schema validation for config files
3. **Dynamic Configuration** - Support runtime configuration updates
4. **Multi-Region Deployment** - Support deployment across multiple regions
5. **Monitoring & Alerting** - Add CloudWatch integration for monitoring

### Repository Structure Evolution

**Current (Monorepo):**
- ✅ Easier development and testing
- ✅ Coordinated deployments
- ✅ Shared utilities and models

**Future (Multi-repo):**
- 🔄 Independent service development
- 🔄 Service-specific CI/CD pipelines
- 🔄 Independent versioning and releases

## 🆘 Troubleshooting

### Common Issues

1. **Configuration not found**
   - Check `ENVIRONMENT` environment variable
   - Verify config files exist in `config/` directory

2. **Docker deployment fails**
   - Ensure Docker and Docker Compose are installed
   - Check port availability (5001, 5002, 3306)

3. **AWS deployment fails**
   - Verify AWS CLI configuration
   - Check SSH key pair exists and is accessible
   - Ensure sufficient IAM permissions

4. **Service connection issues**
   - Verify service URLs in configuration
   - Check firewall and security group settings
   - Test network connectivity between services

### Getting Help

- Check service logs: `docker-compose logs [service_name]`
- Verify configuration: `python -c "from config import get_config; print(get_config())"`
- Test connectivity: `curl http://localhost:5001/health`

## 📚 Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [AWS EC2 User Guide](https://docs.aws.amazon.com/ec2/)
- [Flask Configuration](https://flask.palletsprojects.com/en/2.3.x/config/)
- [Python Environment Variables](https://docs.python.org/3/library/os.html#os.environ)
