#!/bin/bash

# Add Redis to Docker Compose Script
# Use this when you need Redis for caching, rate limiting, or performance optimization

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Adding Redis to Docker Compose...${NC}"

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ docker-compose.yml not found${NC}"
    exit 1
fi

# Add Redis service before Nginx
echo -e "${BLUE}📝 Adding Redis service to docker-compose.yml...${NC}"

# Create backup
cp docker-compose.yml docker-compose.yml.backup

# Add Redis service using sed
sed -i.bak '/# Nginx reverse proxy/i\
  # Redis for caching and rate limiting\
  redis:\
    image: redis:7-alpine\
    container_name: trading_redis\
    ports:\
      - "${REDIS_PORT:-6379}:6379"\
    volumes:\
      - redis_data:/data\
    networks:\
      - trading_network\
    restart: unless-stopped\
\
' docker-compose.yml

# Add Redis volume
sed -i.bak '/volumes:/a\
  redis_data:\
' docker-compose.yml

# Add Redis environment variable to docker.env.example
if [ -f "docker.env.example" ]; then
    echo -e "${BLUE}📝 Adding REDIS_PORT to docker.env.example...${NC}"
    sed -i.bak '/NGINX_HTTP_PORT=/a\
REDIS_PORT=6379\
' docker.env.example
fi

# Add Redis environment variable to docker.env if it exists
if [ -f "docker.env" ]; then
    echo -e "${BLUE}📝 Adding REDIS_PORT to docker.env...${NC}"
    sed -i.bak '/NGINX_HTTP_PORT=/a\
REDIS_PORT=6379\
' docker.env
fi

echo -e "${GREEN}✅ Redis added successfully!${NC}"
echo ""
echo -e "${BLUE}📋 What was added:${NC}"
echo "  • Redis service (port 6379)"
echo "  • Redis volume for data persistence"
echo "  • REDIS_PORT environment variable"
echo ""
echo -e "${YELLOW}⚠️  Next steps:${NC}"
echo "  1. Restart Docker services: docker-compose down && docker-compose up -d"
echo "  2. Redis will be available at localhost:6379"
echo "  3. Use Redis for caching, rate limiting, or session management"
echo ""
echo -e "${BLUE}💡 Redis Use Cases:${NC}"
echo "  • Cache ML model predictions"
echo "  • API rate limiting"
echo "  • Session storage"
echo "  • Real-time data caching"
echo ""
echo -e "${GREEN}🚀 Redis is ready to use!${NC}"
