#!/bin/bash

# Environment Switcher Script
# Quickly switch between development, testing, and production environments

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show current environment
show_current_env() {
    local current_env=$(echo $ENVIRONMENT)
    if [ -z "$current_env" ]; then
        current_env="development (default)"
    fi

    echo -e "${BLUE}Current Environment:${NC} $current_env"
    echo -e "${BLUE}Config File:${NC} config/${current_env}.json"
}

# Function to switch environment
switch_environment() {
    local new_env=$1

    # Validate environment
    if [ ! -f "config/${new_env}.json" ]; then
        echo -e "${YELLOW}Warning:${NC} Configuration file config/${new_env}.json not found"
        echo "Available environments:"
        ls config/*.json | sed 's/config\///' | sed 's/\.json//'
        exit 1
    fi

    # Set environment variable
    export ENVIRONMENT=$new_env

    # Update .env file
    echo "ENVIRONMENT=$new_env" > .env

    echo -e "${GREEN}Environment switched to:${NC} $new_env"
    echo -e "${GREEN}Configuration loaded from:${NC} config/${new_env}.json"

    # Show environment info
    echo ""
    echo -e "${BLUE}Environment Details:${NC}"
    python3 -c "
from config import get_config
config = get_config()
print(f'  Database: {config.database.host}:{config.database.port}/{config.database.name}')
print(f'  Analytics: {config.analytics.url}')
print(f'  ML Service: {config.ml_service.url}')
print(f'  Models Dir: {config.ml.models_dir}')
print(f'  Log Level: {config.logging.level}')
print(f'  Analytics Log: {config.logging.get_service_log_path(\"analytics\")}')
print(f'  ML Service Log: {config.logging.get_service_log_path(\"ml_service\")}')
print(f'  Web Server Log: {config.logging.get_service_log_path(\"webserver\")}')
"
}

# Function to show available environments
list_environments() {
    echo -e "${BLUE}Available Environments:${NC}"
    for config_file in config/*.json; do
        if [ -f "$config_file" ]; then
            env_name=$(basename "$config_file" .json)
            if [ "$env_name" = "$ENVIRONMENT" ]; then
                echo -e "  ${GREEN}* $env_name${NC} (current)"
            else
                echo -e "  $env_name"
            fi
        fi
    done
}

# Function to show help
show_help() {
    echo "Environment Switcher for Trading Strategies Project"
    echo ""
    echo "Usage: $0 [COMMAND] [ENVIRONMENT]"
    echo ""
    echo "Commands:"
    echo "  [ENVIRONMENT]    Switch to specified environment"
    echo "  current          Show current environment"
    echo "  list             List available environments"
    echo "  help             Show this help message"
    echo ""
    echo "Environments:"
    echo "  development      Development environment (default)"
    echo "  testing         Testing environment"
    echo "  production      Production environment"
    echo ""
    echo "Examples:"
    echo "  $0 testing       # Switch to testing environment"
    echo "  $0 current       # Show current environment"
    echo "  $0 list          # List all environments"
    echo ""
    echo "Note: Environment changes are saved to .env file"
}

# Main script logic
case "${1:-current}" in
    "current")
        show_current_env
        ;;
    "list")
        list_environments
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        switch_environment "$1"
        ;;
esac
