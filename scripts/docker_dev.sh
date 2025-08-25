#!/bin/bash

# Docker Development Helper Script
# Helps with common Docker development tasks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo -e "${BLUE}Docker Development Helper Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build           Build all Docker images"
    echo "  build [service] Build specific service (analytics, ml_service, nginx)"
    echo "  start           Start all services"
    echo "  stop            Stop all services"
    echo "  restart         Restart all services"
    echo "  logs [service]  Show logs for all or specific service"
    echo "  shell [service] Open shell in running container"
    echo "  clean           Clean up containers, images, and volumes"
    echo "  status          Show status of all services"
    echo "  help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 build analytics"
    echo "  $0 logs ml_service"
    echo "  $0 shell analytics"
}

build_images() {
    local service=${1:-all}

    echo -e "${BLUE}Building Docker images...${NC}"

    # Load build environment if it exists
    if [ -f "docker/build.env" ]; then
        echo "Loading build environment from docker/build.env..."
        export $(grep -v '^#' docker/build.env | xargs)
    elif [ -f "docker/build.env.example" ]; then
        echo "Creating build.env from template..."
        cp docker/build.env.example docker/build.env
        echo -e "${YELLOW}⚠️  Please edit docker/build.env with your values${NC}"
        export $(grep -v '^#' docker/build.env | xargs)
    fi

    if [ "$service" = "all" ]; then
        echo "Building all services..."
        docker-compose build
    else
        echo "Building $service service..."
        docker-compose build "$service"
    fi

    echo -e "${GREEN}✅ Build completed${NC}"
}

start_services() {
    echo -e "${BLUE}Starting Docker services...${NC}"
    docker-compose up -d
    echo -e "${GREEN}✅ Services started${NC}"
    echo ""
    echo -e "${BLUE}Service URLs:${NC}"

    # Load environment variables for port display
    if [ -f "docker.env" ]; then
        source docker.env
    fi

    echo "  Analytics: http://localhost:${ANALYTICS_PORT:-5004}"
    echo "  ML Service: http://localhost:${ML_SERVICE_PORT:-5005}"
    echo "  Nginx: http://localhost:80"
    echo "  MySQL: localhost:3306"
}

stop_services() {
    echo -e "${BLUE}Stopping Docker services...${NC}"
    docker-compose down
    echo -e "${GREEN}✅ Services stopped${NC}"
}

restart_services() {
    echo -e "${BLUE}Restarting Docker services...${NC}"
    docker-compose restart
    echo -e "${GREEN}✅ Services restarted${NC}"
}

show_logs() {
    local service=${1:-all}

    if [ "$service" = "all" ]; then
        echo -e "${BLUE}Showing logs for all services...${NC}"
        docker-compose logs -f
    else
        echo -e "${BLUE}Showing logs for $service...${NC}"
        docker-compose logs -f "$service"
    fi
}

open_shell() {
    local service=${1}

    if [ -z "$service" ]; then
        echo -e "${RED}❌ Please specify a service${NC}"
        echo "Available services: analytics, ml_service, nginx, mysql"
        exit 1
    fi

    echo -e "${BLUE}Opening shell in $service container...${NC}"
    docker-compose exec "$service" /bin/bash
}

clean_docker() {
    echo -e "${YELLOW}⚠️  This will remove all containers, images, and volumes${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Cleaning up Docker...${NC}"
        docker-compose down -v --rmi all
        docker system prune -af
        echo -e "${GREEN}✅ Cleanup completed${NC}"
    else
        echo -e "${YELLOW}Cleanup cancelled${NC}"
    fi
}

show_status() {
    echo -e "${BLUE}Docker Services Status:${NC}"
    echo ""
    docker-compose ps
    echo ""

    echo -e "${BLUE}Container Resource Usage:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
}

# Main script logic
case "${1:-help}" in
    "build")
        build_images "$2"
        ;;
    "start")
        start_services
        ;;
    "stop")
        stop_services
        ;;
    "restart")
        restart_services
        ;;
    "logs")
        show_logs "$2"
        ;;
    "shell")
        open_shell "$2"
        ;;
    "clean")
        clean_docker
        ;;
    "status")
        show_status
        ;;
    "help"|*)
        show_help
        ;;
esac
