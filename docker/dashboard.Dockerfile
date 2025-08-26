# React Dashboard Dockerfile
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY dashboard/package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY dashboard/ ./

# Build the React app with environment variables
ARG REACT_APP_API_URL
ARG REACT_APP_ML_SERVICE_URL
ARG REACT_APP_ENVIRONMENT

ENV REACT_APP_API_URL=$REACT_APP_API_URL
ENV REACT_APP_ML_SERVICE_URL=$REACT_APP_ML_SERVICE_URL
ENV REACT_APP_ENVIRONMENT=$REACT_APP_ENVIRONMENT


# Build the React app
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built React app to nginx
COPY --from=builder /app/build /usr/share/nginx/html

# Copy custom nginx config for React routing
COPY docker/nginx/dashboard.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 3000

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
