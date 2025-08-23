#!/bin/bash

# Dashboard Environment Setup Script
# Sets up environment configuration for the React dashboard

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DASHBOARD_DIR="analytics/dashboard"
ENV_FILE="$DASHBOARD_DIR/.env"
ENV_EXAMPLE="$DASHBOARD_DIR/env.example"

show_help() {
    echo -e "${BLUE}Dashboard Environment Setup Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [ENVIRONMENT]"
    echo ""
    echo "Commands:"
    echo "  setup [env]     Setup dashboard environment (default: development)"
    echo "  current         Show current dashboard configuration"
    echo "  help            Show this help message"
    echo ""
    echo "Environments:"
    echo "  development     Development environment (default)"
    echo "  testing         Testing environment"
    echo "  production      Production environment"
    echo ""
    echo "Examples:"
    echo "  $0 setup production"
    echo "  $0 current"
}

setup_dashboard_env() {
    local env=${1:-development}

    echo -e "${BLUE}Setting up dashboard environment: ${env}${NC}"

    # Check if dashboard directory exists
    if [ ! -d "$DASHBOARD_DIR" ]; then
        echo -e "${RED}❌ Dashboard directory not found: $DASHBOARD_DIR${NC}"
        exit 1
    fi

    # Check if env.example exists
    if [ ! -f "$ENV_EXAMPLE" ]; then
        echo -e "${RED}❌ $ENV_EXAMPLE not found${NC}"
        exit 1
    fi

    # Create .env from template
    if [ ! -f "$ENV_FILE" ]; then
        echo "Creating $ENV_FILE from $ENV_EXAMPLE..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        echo -e "${GREEN}✅ Created $ENV_FILE${NC}"
    else
        echo -e "${YELLOW}⚠️  $ENV_FILE already exists${NC}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            echo -e "${GREEN}✅ Updated $ENV_FILE${NC}"
        else
            echo -e "${YELLOW}⚠️  Keeping existing $ENV_FILE${NC}"
        fi
    fi

    # Update environment-specific settings
    case $env in
        "development")
            sed -i.bak "s|REACT_APP_API_URL=.*|REACT_APP_API_URL=http://localhost:5001|" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_ENVIRONMENT=.*/REACT_APP_ENVIRONMENT=development/" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_DEBUG=.*/REACT_APP_DEBUG=true/" "$ENV_FILE"
            ;;
        "testing")
            sed -i.bak "s|REACT_APP_API_URL=.*|REACT_APP_API_URL=http://localhost:5001|" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_ENVIRONMENT=.*/REACT_APP_ENVIRONMENT=testing/" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_DEBUG=.*/REACT_APP_DEBUG=false/" "$ENV_FILE"
            ;;
        "production")
            sed -i.bak "s|REACT_APP_API_URL=.*|REACT_APP_API_URL=https://your-production-domain.com|" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_ENVIRONMENT=.*/REACT_APP_ENVIRONMENT=production/" "$ENV_FILE"
            sed -i.bak "s/REACT_APP_DEBUG=.*/REACT_APP_DEBUG=false/" "$ENV_FILE"
            ;;
        *)
            echo -e "${RED}❌ Unknown environment: $env${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}✅ Dashboard environment '$env' configured in $ENV_FILE${NC}"
    echo ""
    echo -e "${YELLOW}📝 Please edit $ENV_FILE with your actual values:${NC}"
    echo "   - API URLs for your environment"
    echo "   - Feature flags"
    echo "   - Production domain (if applicable)"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "   1. Edit $ENV_FILE with your values"
    echo "   2. Run: cd $DASHBOARD_DIR && npm start"
}

show_current_dashboard_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ $ENV_FILE not found${NC}"
        echo "Run '$0 setup' to create it."
        exit 1
    fi

    echo -e "${BLUE}Current Dashboard Configuration:${NC}"
    echo -e "${BLUE}Config File: ${GREEN}$ENV_FILE${NC}"
    echo ""

    echo -e "${BLUE}Key Settings:${NC}"
    echo "  API URL: $(grep "^REACT_APP_API_URL=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Environment: $(grep "^REACT_APP_ENVIRONMENT=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Debug: $(grep "^REACT_APP_DEBUG=" "$ENV_FILE" | cut -d'=' -f2)"
    echo "  Version: $(grep "^REACT_APP_VERSION=" "$ENV_FILE" | cut -d'=' -f2)"

    echo ""
    echo -e "${BLUE}Feature Flags:${NC}"
    grep "^REACT_APP_ENABLE_" "$ENV_FILE" | while read line; do
        echo "  $line"
    done
}

# Main script logic
case "${1:-help}" in
    "setup")
        setup_dashboard_env "$2"
        ;;
    "current")
        show_current_dashboard_config
        ;;
    "help"|*)
        show_help
        ;;
esac
