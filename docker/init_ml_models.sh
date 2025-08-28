#!/bin/bash

# Script to initialize ML models in Docker volume
# This ensures existing models are available in the container

set -e

echo "🔧 Initializing ML models in Docker volume..."

# Check if we're in the right directory
if [ ! -d "ML_Webserver/ml_models" ]; then
    echo "❌ Error: ML_Webserver/ml_models directory not found"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Get the container prefix from environment or use default
CONTAINER_PREFIX=${CONTAINER_PREFIX:-trading}
VOLUME_NAME="${CONTAINER_PREFIX}_ml_models_data"

echo "🏷️  Using container prefix: $CONTAINER_PREFIX"
echo "📦 Volume name: $VOLUME_NAME"

# Create the volume if it doesn't exist
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "📦 Creating Docker volume: $VOLUME_NAME"
    docker volume create "$VOLUME_NAME"
else
    echo "✅ Docker volume already exists: $VOLUME_NAME"
fi

# Create a temporary container to copy models
TEMP_CONTAINER="temp_ml_models_init"

echo "📋 Copying existing models to Docker volume..."

# Create temporary container
docker run -d --name "$TEMP_CONTAINER" \
    -v "$VOLUME_NAME:/models" \
    -v "$(pwd)/ML_Webserver/ml_models:/source:ro" \
    alpine:latest tail -f /dev/null

# Copy models from source to volume
docker exec "$TEMP_CONTAINER" sh -c "cp -r /source/* /models/ 2>/dev/null || true"

# Clean up temporary container
docker stop "$TEMP_CONTAINER" >/dev/null 2>&1 || true
docker rm "$TEMP_CONTAINER" >/dev/null 2>&1 || true

echo "✅ ML models initialized successfully!"
echo "📊 Models available in volume: $VOLUME_NAME"
echo ""
echo "🚀 You can now start your services with:"
echo "   docker-compose --env-file docker.test.env up -d"
