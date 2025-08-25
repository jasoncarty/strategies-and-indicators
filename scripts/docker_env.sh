#!/bin/bash

# Docker Environment Management Script
# Helps manage different Docker environments (development, testing, production)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_ENV="development"
ENV_FILE="docker.env"

show_help() {
    echo -e "${BLUE}Docker Environment Management Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [ENVIRONMENT]"
    echo ""
    echo "Commands:"
    echo "  setup [env]     Setup Docker environment (default: development)"
    echo "  switch [env]    Switch to different environment"
    echo "  current         Show current Docker environment"
    echo "  list            List available environments"
    echo "  validate        Validate current Docker configuration"
    echo "  help            Show this help message"
    echo ""
    echo "Environments:"
    echo "  development     Development environment (default)"
    echo "  testing         Testing environment"
    echo "  production      Production environment"
    echo ""
    echo "Examples:"
    echo "  $0 setup production"
    echo "  $0 switch testing"
    echo "  $0 current"
}

setup_docker_env() {
    local env=${1:-$DEFAULT_ENV}

    echo -e "${BLUE}Setting up Docker environment: ${env}${NC}"

    # Check if docker.env.example exists
    if [ ! -f "docker.env.example" ]; then
        echo -e "${RED}❌ docker.env.example not found${NC}"
        exit 1
    fi

    # Create docker.env from template
    if [ ! -f "$ENV_FILE" ]; then
        echo "Creating $ENV_FILE from docker.env.example..."
        cp docker.env.example "$ENV_FILE"
        echo -e "${GREEN}✅ Created $ENV_FILE${NC}"
    else
        echo -e "${YELLOW}⚠️  $ENV_FILE already exists${NC}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp docker.env.example "$ENV_FILE"
            echo -e "${GREEN}✅ Updated $ENV_FILE${NC}"
        else
            echo -e "${YELLOW}⚠️  Keeping existing $ENV_FILE${NC}"
        fi
    fi

    # Update environment in docker.env
    sed -i.bak "s/ENVIRONMENT=.*/ENVIRONMENT=$env/" "$ENV_FILE"

    # Update database host for Docker
    if [ "$env" = "development" ] || [ "$env" = "testing" ]; then
        sed -i.bak "s/DB_HOST=.*/DB_HOST=mysql/" "$ENV_FILE"
    fi

    echo -e "${GREEN}✅ Docker environment '$env' configured in $ENV_FILE${NC}"
    echo ""
    echo -e "${YELLOW}📝 Please edit $ENV_FILE with your actual values:${NC}"
    echo "   - Database passwords"
    echo "   - Service ports (if you want to change defaults)"
    echo "   - Security keys"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "   1. Edit $ENV_FILE with your values"
    echo "   2. Run: docker-compose up -d"
}

switch_docker_env() {
    local env=${1:-$DEFAULT_ENV}

    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ $ENV_FILE not found. Run 'setup' first.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Switching Docker environment to: ${env}${NC}"

    # Update environment in docker.env
    sed -i.bak "s/ENVIRONMENT=.*/ENVIRONMENT=$env/" "$ENV_FILE"

    # Update database host for Docker
    if [ "$env" = "development" ] || [ "$env" = "testing" ]; then
        sed -i.bak "s/DB_HOST=.*/DB_HOST=mysql/" "$ENV_FILE"
    else
        sed -i.bak "s/DB_HOST=.*/DB_HOST=localhost/" "$ENV_FILE"
    fi

    echo -e "${GREEN}✅ Switched to Docker environment: $env${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to restart Docker services:${NC}"
    echo "   docker-compose down"
    echo "   docker-compose up -d"
}

show_current_docker_env() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ $ENV_FILE not found${NC}"
        echo "Run '$0 setup' to create it."
        exit 1
    fi

    local env=$(grep "^ENVIRONMENT=" "$ENV_FILE" | cut -d'=' -f2)
    echo -e "${BLUE}Current Docker Environment: ${GREEN}$env${NC}"
    echo -e "${BLUE}Config File: ${GREEN}$ENV_FILE${NC}"
    echo ""

    echo -e "${BLUE}Key Configuration:${NC}"
    echo "  Database Host: $(grep "^DB_HOST=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Analytics Port: $(grep "^ANALYTICS_PORT=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  ML Service Port: $(grep "^ML_SERVICE_PORT=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Dashboard Port: $(grep "^DASHBOARD_PORT=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Nginx HTTP Port: $(grep "^NGINX_HTTP_PORT=" "$ENV_FILE" | cut -d'=' -f2)"
}

list_environments() {
    echo -e "${BLUE}Available Docker Environments:${NC}"
    echo ""
    echo -e "${GREEN}development${NC}  - Local development with Docker"
    echo "  • Database: mysql container"
    echo "  • Services: localhost ports"
    echo "  • Logs: local logs directory"
    echo ""
    echo -e "${GREEN}testing${NC}      - Testing environment with Docker"
    echo "  • Database: mysql container"
    echo "  • Services: localhost ports"
    echo "  • Logs: tests/logs directory"
    echo ""
    echo -e "${GREEN}production${NC}   - Production environment"
    echo "  • Database: external MySQL"
    echo "  • Services: production ports"
    echo "  • Logs: production log paths"
}

validate_docker_config() {
    echo -e "${BLUE}Validating Docker configuration...${NC}"

    # Check if docker.env exists
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ $ENV_FILE not found${NC}"
        exit 1
    fi

    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}❌ docker-compose.yml not found${NC}"
        exit 1
    fi

    # Check required environment variables
    local missing_vars=()
    local required_vars=("ENVIRONMENT" "DB_NAME" "DB_USER" "DB_PASSWORD" "MYSQL_ROOT_PASSWORD")

    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$ENV_FILE"; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All required variables present${NC}"
    else
        echo -e "${RED}❌ Missing required variables:${NC}"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Docker configuration is valid${NC}"
    echo -e "${GREEN}✅ Docker daemon is running${NC}"
}

# Main script logic
case "${1:-help}" in
    "setup")
        setup_docker_env "$2"
        ;;
    "switch")
        switch_docker_env "$2"
        ;;
    "current")
        show_current_docker_env
        ;;
    "list")
        list_environments
        ;;
    "validate")
        validate_docker_config
        ;;
    "help"|*)
        show_help
        ;;
esac
