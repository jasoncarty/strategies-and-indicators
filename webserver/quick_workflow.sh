#!/bin/bash

# Quick Trading Workflow Script
# Simplifies the automation process with common workflows

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Quick Trading Workflow Script"
    echo "============================="
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  validate          - Validate setup"
    echo "  list-eas          - List available EAs"
    echo "  analyze <EA>      - Analyze results for EA"
    echo "  train <EA>        - Train ML models for EA"
    echo "  quick <EA>        - Quick workflow (analyze + train)"
    echo "  full <EA>         - Full workflow (auto ST + analyze + train)"
    echo "  manual <EA>       - Manual workflow (manual ST + analyze + train)"
    echo "  optimize <EA>     - Optimization workflow"
    echo ""
    echo "Examples:"
    echo "  $0 validate"
    echo "  $0 list-eas"
    echo "  $0 analyze SimpleBreakoutML_EA"
    echo "  $0 train SimpleBreakoutML_EA"
    echo "  $0 quick SimpleBreakoutML_EA"
    echo "  $0 full SimpleBreakoutML_EA"
    echo "  $0 manual SimpleBreakoutML_EA"
    echo "  $0 optimize SimpleBreakoutML_EA"
    echo ""
    echo "Options:"
    echo "  --incremental     - Use incremental ML training"
    echo "  --symbol SYMBOL   - Trading symbol (default: EURUSD+)"
    echo "  --timeframe TF    - Timeframe (default: M5)"
    echo "  --start-date DATE - Start date (default: 2023.10.01)"
    echo "  --end-date DATE   - End date (default: 2023.12.31)"
    echo "  --no-automation   - Disable MT5 automation (manual mode)"
    echo ""
}

# Function to validate setup
validate_setup() {
    print_status "Validating setup..."
    python automated_trading_workflow.py --validate
    if [ $? -eq 0 ]; then
        print_success "Setup validation passed!"
    else
        print_error "Setup validation failed!"
        exit 1
    fi
}

# Function to list EAs
list_eas() {
    print_status "Listing available EAs..."
    python automated_trading_workflow.py --list-eas
}

# Function to analyze results
analyze_results() {
    local ea_name=$1
    print_status "Analyzing results for $ea_name..."
    python automated_trading_workflow.py --ea "$ea_name" --analyze-only
}

# Function to train ML models
train_models() {
    local ea_name=$1
    local incremental=$2
    print_status "Training ML models for $ea_name..."
    
    if [ "$incremental" = "true" ]; then
        python automated_trading_workflow.py --ea "$ea_name" --train-only --incremental
    else
        python automated_trading_workflow.py --ea "$ea_name" --train-only
    fi
}

# Function for quick workflow
quick_workflow() {
    local ea_name=$1
    local incremental=$2
    print_status "Running quick workflow for $ea_name..."
    
    # Analyze existing results
    analyze_results "$ea_name"
    
    # Train ML models
    train_models "$ea_name" "$incremental"
    
    print_success "Quick workflow completed!"
}

# Function for full automated workflow
full_workflow() {
    local ea_name=$1
    local incremental=$2
    local symbol=$3
    local timeframe=$4
    local start_date=$5
    local end_date=$6
    
    print_status "Running full automated workflow for $ea_name..."
    
    # Build command
    cmd="python automated_trading_workflow.py --ea $ea_name"
    
    if [ "$incremental" = "true" ]; then
        cmd="$cmd --incremental"
    fi
    
    if [ -n "$symbol" ]; then
        cmd="$cmd --symbol $symbol"
    fi
    
    if [ -n "$timeframe" ]; then
        cmd="$cmd --timeframe $timeframe"
    fi
    
    if [ -n "$start_date" ]; then
        cmd="$cmd --start-date $start_date"
    fi
    
    if [ -n "$end_date" ]; then
        cmd="$cmd --end-date $end_date"
    fi
    
    print_status "Executing: $cmd"
    eval $cmd
    
    print_success "Full automated workflow completed!"
}

# Function for manual workflow
manual_workflow() {
    local ea_name=$1
    local incremental=$2
    local symbol=$3
    local timeframe=$4
    local start_date=$5
    local end_date=$6
    
    print_status "Running manual workflow for $ea_name..."
    
    # Build command with no-automation flag
    cmd="python automated_trading_workflow.py --ea $ea_name --no-automation"
    
    if [ "$incremental" = "true" ]; then
        cmd="$cmd --incremental"
    fi
    
    if [ -n "$symbol" ]; then
        cmd="$cmd --symbol $symbol"
    fi
    
    if [ -n "$timeframe" ]; then
        cmd="$cmd --timeframe $timeframe"
    fi
    
    if [ -n "$start_date" ]; then
        cmd="$cmd --start-date $start_date"
    fi
    
    if [ -n "$end_date" ]; then
        cmd="$cmd --end-date $end_date"
    fi
    
    print_status "Executing: $cmd"
    eval $cmd
    
    print_success "Manual workflow completed!"
}

# Function for optimization workflow
optimization_workflow() {
    local ea_name=$1
    local incremental=$2
    local symbol=$3
    local timeframe=$4
    local start_date=$5
    local end_date=$6
    
    print_status "Running optimization workflow for $ea_name..."
    
    # Build command
    cmd="python automated_trading_workflow.py --ea $ea_name --optimize --optimization-passes 20"
    
    if [ "$incremental" = "true" ]; then
        cmd="$cmd --incremental"
    fi
    
    if [ -n "$symbol" ]; then
        cmd="$cmd --symbol $symbol"
    fi
    
    if [ -n "$timeframe" ]; then
        cmd="$cmd --timeframe $timeframe"
    fi
    
    if [ -n "$start_date" ]; then
        cmd="$cmd --start-date $start_date"
    fi
    
    if [ -n "$end_date" ]; then
        cmd="$cmd --end-date $end_date"
    fi
    
    print_status "Executing: $cmd"
    eval $cmd
    
    print_success "Optimization workflow completed!"
}

# Parse command line arguments
COMMAND=""
EA_NAME=""
INCREMENTAL="false"
SYMBOL=""
TIMEFRAME=""
START_DATE=""
END_DATE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        validate|list-eas|analyze|train|quick|full|manual|optimize)
            COMMAND=$1
            shift
            ;;
        --incremental)
            INCREMENTAL="true"
            shift
            ;;
        --symbol)
            SYMBOL=$2
            shift 2
            ;;
        --timeframe)
            TIMEFRAME=$2
            shift 2
            ;;
        --start-date)
            START_DATE=$2
            shift 2
            ;;
        --end-date)
            END_DATE=$2
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$EA_NAME" ] && [ "$COMMAND" != "validate" ] && [ "$COMMAND" != "list-eas" ]; then
                EA_NAME=$1
            else
                print_error "Unknown argument: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if command is provided
if [ -z "$COMMAND" ]; then
    print_error "No command specified"
    show_usage
    exit 1
fi

# Execute command
case $COMMAND in
    validate)
        validate_setup
        ;;
    list-eas)
        list_eas
        ;;
    analyze)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for analyze command"
            exit 1
        fi
        analyze_results "$EA_NAME"
        ;;
    train)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for train command"
            exit 1
        fi
        train_models "$EA_NAME" "$INCREMENTAL"
        ;;
    quick)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for quick command"
            exit 1
        fi
        quick_workflow "$EA_NAME" "$INCREMENTAL"
        ;;
    full)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for full command"
            exit 1
        fi
        full_workflow "$EA_NAME" "$INCREMENTAL" "$SYMBOL" "$TIMEFRAME" "$START_DATE" "$END_DATE"
        ;;
    manual)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for manual command"
            exit 1
        fi
        manual_workflow "$EA_NAME" "$INCREMENTAL" "$SYMBOL" "$TIMEFRAME" "$START_DATE" "$END_DATE"
        ;;
    optimize)
        if [ -z "$EA_NAME" ]; then
            print_error "EA name required for optimize command"
            exit 1
        fi
        optimization_workflow "$EA_NAME" "$INCREMENTAL" "$SYMBOL" "$TIMEFRAME" "$START_DATE" "$END_DATE"
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

print_success "Workflow completed successfully!" 