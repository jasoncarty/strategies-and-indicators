#!/bin/bash

# Cloud Deployment Script for Trading Strategies Project
# Supports multiple cloud providers and environments

set -e

# Configuration
ENVIRONMENT=${1:-production}
CLOUD_PROVIDER=${2:-aws}
REGION=${3:-us-east-1}
INSTANCE_TYPE=${4:-t3.medium}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if required tools are installed
    command -v docker >/dev/null 2>&1 || { log_error "Docker is required but not installed. Aborting."; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || { log_error "Docker Compose is required but not installed. Aborting."; exit 1; }

    # Check if configuration files exist
    if [ ! -f "config/${ENVIRONMENT}.json" ]; then
        log_error "Configuration file config/${ENVIRONMENT}.json not found. Aborting."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Setup environment
setup_environment() {
    log_info "Setting up environment: $ENVIRONMENT"

    # Create necessary directories
    mkdir -p logs
    mkdir -p ml_models
    mkdir -p data_backups

    # Set environment variable
    export ENVIRONMENT=$ENVIRONMENT

    log_success "Environment setup completed"
}

# Deploy to AWS
deploy_aws() {
    log_info "Deploying to AWS ($REGION) with instance type: $INSTANCE_TYPE"

    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi

    # Create security group
    log_info "Creating security group..."
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "trading-strategies-${ENVIRONMENT}" \
        --description "Security group for Trading Strategies ${ENVIRONMENT} environment" \
        --region $REGION \
        --query 'GroupId' --output text)

    # Add security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region $REGION

    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region $REGION

    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region $REGION

    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 5001 \
        --cidr 0.0.0.0/0 \
        --region $REGION

    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 5002 \
        --cidr 0.0.0.0/0 \
        --region $REGION

    # Launch EC2 instance
    log_info "Launching EC2 instance..."
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ami-0c02fb55956c7d316 \
        --count 1 \
        --instance-type $INSTANCE_TYPE \
        --key-name your-key-pair-name \
        --security-group-ids $SECURITY_GROUP_ID \
        --region $REGION \
        --query 'Instances[0].InstanceId' --output text)

    log_info "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

    log_success "Instance launched successfully: $INSTANCE_ID ($PUBLIC_IP)"

    # Wait for SSH to be available
    log_info "Waiting for SSH to be available..."
    while ! nc -z $PUBLIC_IP 22; do
        sleep 5
    done

    # Copy files and deploy
    deploy_to_instance $PUBLIC_IP
}

# Deploy to instance
deploy_to_instance() {
    local IP=$1

    log_info "Deploying to instance: $IP"

    # Create deployment package
    log_info "Creating deployment package..."
    tar -czf deployment.tar.gz \
        --exclude='.git' \
        --exclude='venv' \
        --exclude='__pycache__' \
        --exclude='.pytest_cache' \
        --exclude='logs/*' \
        --exclude='*.log' \
        .

    # Copy to instance
    log_info "Copying deployment package to instance..."
    scp -i ~/.ssh/your-key-pair-name.pem deployment.tar.gz ubuntu@$IP:~/

    # Execute deployment commands
    log_info "Executing deployment commands..."
    ssh -i ~/.ssh/your-key-pair-name.pem ubuntu@$IP << 'EOF'
        # Update system
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose python3-pip

        # Start Docker service
        sudo systemctl start docker
        sudo systemctl enable docker

        # Add user to docker group
        sudo usermod -aG docker $USER

        # Extract deployment package
        tar -xzf deployment.tar.gz
        cd strategies-and-indicators

        # Set environment
        export ENVIRONMENT=production

        # Start services
        sudo docker-compose up -d

        # Clean up
        rm ~/deployment.tar.gz
EOF

    log_success "Deployment completed successfully!"
    log_info "Services available at:"
    log_info "  - Analytics: http://$IP:5001"
    log_info "  - ML Service: http://$IP:5002"
    log_info "  - Nginx: http://$IP"

    # Clean up local deployment package
    rm deployment.tar.gz
}

# Deploy to Docker (local/remote)
deploy_docker() {
    log_info "Deploying with Docker Compose..."

    # Build and start services
    docker-compose -f docker-compose.yml up -d --build

    log_success "Docker deployment completed"
    log_info "Services available at:"
    log_info "  - Analytics: http://localhost:5001"
    log_info "  - ML Service: http://localhost:5002"
    log_info "  - Nginx: http://localhost"
}

# Main deployment logic
main() {
    log_info "Starting deployment for environment: $ENVIRONMENT"

    check_prerequisites
    setup_environment

    case $CLOUD_PROVIDER in
        "aws")
            deploy_aws
            ;;
        "docker")
            deploy_docker
            ;;
        *)
            log_error "Unsupported cloud provider: $CLOUD_PROVIDER"
            log_info "Supported providers: aws, docker"
            exit 1
            ;;
    esac

    log_success "Deployment completed successfully!"
}

# Show usage
show_usage() {
    echo "Usage: $0 [ENVIRONMENT] [CLOUD_PROVIDER] [REGION] [INSTANCE_TYPE]"
    echo ""
    echo "Parameters:"
    echo "  ENVIRONMENT      Environment to deploy (development, testing, production) [default: production]"
    echo "  CLOUD_PROVIDER   Cloud provider (aws, docker) [default: aws]"
    echo "  REGION          AWS region (for AWS deployments) [default: us-east-1]"
    echo "  INSTANCE_TYPE   AWS instance type [default: t3.medium]"
    echo ""
    echo "Examples:"
    echo "  $0 production aws us-west-2 t3.large"
    echo "  $0 development docker"
    echo "  $0 testing aws eu-west-1"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"
