# ML Service Dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies including timezone support
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y gcc default-libmysqlclient-dev pkg-config tzdata \
    && rm -rf /var/lib/apt/lists/*

# Set timezone to Stockholm, Sweden
ENV TZ=Europe/Stockholm
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip \
    && pip install mysqlclient \
    && pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY ML_Webserver/ ./ML_Webserver/
COPY config/ ./config/
COPY utils/ ./utils/

# Create logs directory
RUN mkdir -p logs

# Set environment variables
ENV PYTHONPATH=/app
ENV FLASK_APP=ML_Webserver/ml_prediction_service.py
ENV FLASK_ENV=production

# Expose port (will be overridden by docker-compose)
EXPOSE 5002

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5002/health || exit 1

# Run the application (will use environment variables from docker-compose)
CMD python -m flask run --host=0.0.0.0 --port=$ML_SERVICE_PORT
