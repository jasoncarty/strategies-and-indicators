#!/bin/bash

# Configuration Setup Script
# Helps users set up configuration files from templates

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show help
show_help() {
    echo "Configuration Setup Script for Trading Strategies Project"
    echo ""
    echo "Usage: $0 [COMMAND] [ENVIRONMENT]"
    echo ""
    echo "Commands:"
    echo "  setup [ENVIRONMENT]    Setup configuration for specified environment"
    echo "  list                   List available environments"
    echo "  help                   Show this help message"
    echo ""
    echo "Environments:"
    echo "  development            Development environment"
    echo "  testing               Testing environment"
    echo "  production            Production environment"
    echo ""
    echo "Examples:"
    echo "  $0 setup production   # Setup production configuration"
    echo "  $0 setup development  # Setup development configuration"
    echo "  $0 list               # List available environments"
    echo ""
    echo "Note: This script will create .env file and config files from templates"
}

# Function to list available environments
list_environments() {
    echo -e "${BLUE}Available Environments:${NC}"
    for template_file in config/templates/*.json.template; do
        if [ -f "$template_file" ]; then
            env_name=$(basename "$template_file" .json.template)
            echo -e "  $env_name"
        fi
    done
}

# Function to setup environment configuration
setup_environment() {
    local env_name=$1

    echo -e "${BLUE}Setting up configuration for environment:${NC} $env_name"

    # Check if template exists
    local template_file="config/templates/${env_name}.json.template"
    if [ ! -f "$template_file" ]; then
        echo -e "${RED}Error: Template file not found:${NC} $template_file"
        echo "Available environments:"
        list_environments
        exit 1
    fi

    # Create .env file if it doesn't exist
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}Creating .env file from env.example...${NC}"
        if [ -f "env.example" ]; then
            cp env.example .env
            echo -e "${GREEN}Created .env file${NC}"
            echo -e "${YELLOW}Please edit .env file with your actual values${NC}"
        else
            echo -e "${RED}Error: env.example file not found${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}.env file already exists${NC}"
    fi

    # Create actual config file from template
    local config_file="config/${env_name}.json"
    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}Config file already exists:${NC} $config_file"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Skipping config file creation${NC}"
            return
        fi
    fi

    echo -e "${BLUE}Creating config file:${NC} $config_file"

    # Copy template to config file
    cp "$template_file" "$config_file"

    # Replace environment variable placeholders with actual values from .env
    if [ -f ".env" ]; then
        echo -e "${BLUE}Substituting environment variables...${NC}"

        # Load environment variables from .env
        set -a
        source .env
        set +a

        # Replace variables in config file
        sed -i.bak "s/\${DB_HOST}/$DB_HOST/g" "$config_file"
        sed -i.bak "s/\${DB_PORT}/$DB_PORT/g" "$config_file"
        sed -i.bak "s/\${DB_NAME}/$DB_NAME/g" "$config_file"
        sed -i.bak "s/\${DB_USER}/$DB_USER/g" "$config_file"
        sed -i.bak "s/\${DB_PASSWORD}/$DB_PASSWORD/g" "$config_file"
        sed -i.bak "s/\${ANALYTICS_PORT}/$ANALYTICS_PORT/g" "$config_file"
        sed -i.bak "s/\${ML_SERVICE_PORT}/$ML_SERVICE_PORT/g" "$config_file"
        sed -i.bak "s/\${DASHBOARD_PORT}/$DASHBOARD_PORT/g" "$config_file"
        sed -i.bak "s/\${ANALYTICS_WORKERS}/$ANALYTICS_WORKERS/g" "$config_file"
        sed -i.bak "s/\${ML_SERVICE_WORKERS}/$ML_SERVICE_WORKERS/g" "$config_file"
        sed -i.bak "s|\${ML_MODELS_DIR}|$ML_MODELS_DIR|g" "$config_file"
        sed -i.bak "s/\${LOG_LEVEL}/$LOG_LEVEL/g" "$config_file"
        sed -i.bak "s|\${DASHBOARD_API_URL}|$DASHBOARD_API_URL|g" "$config_file"

        # Replace Nginx configuration variables
        sed -i.bak "s/\${NGINX_WORKER_CONNECTIONS}/$NGINX_WORKER_CONNECTIONS/g" "$config_file"
        sed -i.bak "s/\${NGINX_KEEPALIVE_TIMEOUT}/$NGINX_KEEPALIVE_TIMEOUT/g" "$config_file"
        sed -i.bak "s/\${NGINX_TYPES_HASH_MAX_SIZE}/$NGINX_TYPES_HASH_MAX_SIZE/g" "$config_file"
        sed -i.bak "s|\${NGINX_CLIENT_MAX_BODY_SIZE}|$NGINX_CLIENT_MAX_BODY_SIZE|g" "$config_file"
        sed -i.bak "s/\${NGINX_GZIP_LEVEL}/$NGINX_GZIP_LEVEL/g" "$config_file"
        sed -i.bak "s/\${NGINX_API_RATE_LIMIT}/$NGINX_API_RATE_LIMIT/g" "$config_file"
        sed -i.bak "s/\${NGINX_ML_RATE_LIMIT}/$NGINX_ML_RATE_LIMIT/g" "$config_file"
        sed -i.bak "s/\${NGINX_API_BURST}/$NGINX_API_BURST/g" "$config_file"
        sed -i.bak "s/\${NGINX_ML_BURST}/$NGINX_ML_BURST/g" "$config_file"
        sed -i.bak "s/\${NGINX_PROXY_CONNECT_TIMEOUT}/$NGINX_PROXY_CONNECT_TIMEOUT/g" "$config_file"
        sed -i.bak "s/\${NGINX_PROXY_SEND_TIMEOUT}/$NGINX_PROXY_SEND_TIMEOUT/g" "$config_file"
        sed -i.bak "s/\${NGINX_PROXY_READ_TIMEOUT}/$NGINX_PROXY_READ_TIMEOUT/g" "$config_file"

        # Replace logging path variables
        sed -i.bak "s|\${ANALYTICS_LOG_PATH}|$ANALYTICS_LOG_PATH|g" "$config_file"
        sed -i.bak "s|\${ML_SERVICE_LOG_PATH}|$ML_SERVICE_LOG_PATH|g" "$config_file"
        sed -i.bak "s|\${WEBSERVER_LOG_PATH}|$WEBSERVER_LOG_PATH|g" "$config_file"
        sed -i.bak "s|\${DASHBOARD_LOG_PATH}|$DASHBOARD_LOG_PATH|g" "$config_file"
        sed -i.bak "s|\${GENERAL_LOG_PATH}|$GENERAL_LOG_PATH|g" "$config_file"

        sed -i.bak "s/\${SECRET_KEY}/$SECRET_KEY/g" "$config_file"
        sed -i.bak "s/\${JWT_SECRET}/$JWT_SECRET/g" "$config_file"
        # Handle CORS_ORIGINS specially (contains brackets that need escaping)
        if [ -n "$CORS_ORIGINS" ]; then
            # Escape the brackets for sed
            escaped_cors=$(echo "$CORS_ORIGINS" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g')
            sed -i.bak "s/\${CORS_ORIGINS}/$escaped_cors/g" "$config_file"
        fi
        sed -i.bak "s/\${API_RATE_LIMIT}/$API_RATE_LIMIT/g" "$config_file"

        # Remove backup file
        rm "${config_file}.bak"

        echo -e "${GREEN}Environment variables substituted successfully${NC}"
    else
        echo -e "${YELLOW}Warning: .env file not found, using template as-is${NC}"
    fi

    echo -e "${GREEN}Configuration setup completed for:${NC} $env_name"
    echo -e "${BLUE}Config file:${NC} $config_file"

    # Show next steps
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Review and edit .env file with your actual values"
    echo "2. Review the generated config file: $config_file"
    echo "3. Test configuration: python -c \"from config import get_config; print(get_config())\""
}

# Main script logic
case "${1:-help}" in
    "setup")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment not specified${NC}"
            echo "Usage: $0 setup [ENVIRONMENT]"
            echo "Run '$0 list' to see available environments"
            exit 1
        fi
        setup_environment "$2"
        ;;
    "list")
        list_environments
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command:${NC} $1"
        show_help
        exit 1
        ;;
esac
