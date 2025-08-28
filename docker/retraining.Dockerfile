# ML Retraining Service Dockerfile
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

# Copy ML service code
COPY ML_Webserver/ ./ML_Webserver/
COPY analytics/ ./analytics/
COPY utils/ ./utils/

# Create necessary directories and set up models
RUN mkdir -p /app/logs /app/ML_Webserver/ml_models
RUN chmod 755 /app/ML_Webserver/ml_models

# Copy existing models to the container (they will be read-only from host)
# The container will have its own writable copy for new models
RUN cp -r /app/ML_Webserver/ml_models/* /app/ML_Webserver/ml_models/ 2>/dev/null || true

# Set environment variables
ENV PYTHONPATH=/app
ENV ENVIRONMENT=production

# Expose port (if the retraining service has an API)
EXPOSE 5006

# Start the retraining service
CMD ["python", "ML_Webserver/start_retraining_pipeline.py"]
