# Centralized Virtual Environment Setup

This project now uses a centralized virtual environment located at the root of the project (`strategies-and-indicators/venv/`) instead of separate virtual environments in each subdirectory.

## Quick Start

### 1. Setup the Environment (First Time Only)

```bash
# From the project root directory
python3 setup_environment.py
```

This will:
- Create a virtual environment at `./venv/`
- Install all dependencies from the consolidated `requirements.txt`
- Verify the installation

### 2. Activate and Start All Servers

```bash
# Option 1: Use the convenience script
./activate_and_start.sh

# Option 2: Manual activation and startup
source venv/bin/activate
python start_all_servers.py
```

### 3. Test the Environment

```bash
source venv/bin/activate
python test_environment.py
```

## What's Included

The centralized environment includes all dependencies from:
- `analytics/requirements.txt` (Flask, PyMySQL, python-dotenv)
- `ML_Webserver/requirements.txt` (numpy, pandas, scikit-learn, etc.)
- `webserver/requirements.txt` (Flask, SQLAlchemy, CORS, etc.)
- `tests/requirements.txt` (pytest, testing utilities)

## Server Ports

- **Analytics Server**: http://localhost:5001
- **ML Prediction Service**: http://localhost:5002
- **Live Retraining Service**: Background monitoring service

## Prerequisites

Before starting the servers, ensure:
1. Docker is running (for the analytics database)
2. The database is started: `cd analytics && docker compose up -d`

## Troubleshooting

### Port Already in Use
If you get "Address already in use" errors:
```bash
# Find what's using the port
lsof -i :5001  # or :5002

# Kill the process
kill -9 <PID>
```

### Missing Dependencies
If you get import errors:
```bash
# Reinstall dependencies
source venv/bin/activate
pip install -r requirements.txt
```

### Database Connection Issues
```bash
# Start the database
cd analytics
docker compose up -d

# Check database status
docker compose ps
```

## Manual Server Startup

If you prefer to start servers individually:

```bash
# Activate the environment
source venv/bin/activate

# Start analytics server
cd analytics && python app.py

# Start ML service (in another terminal)
cd ML_Webserver && python start_ml_service.py

# Start live retraining (in another terminal)
cd ML_Webserver && python live_retraining_service.py
```

## Benefits of Centralized Environment

1. **No more pymysql import errors** - All dependencies are in one place
2. **Easier management** - Single virtual environment to maintain
3. **Consistent versions** - All services use the same package versions
4. **Simplified startup** - One command to start all services
5. **Better isolation** - Project dependencies are separate from system Python

## File Structure

```
strategies-and-indicators/
├── venv/                    # Centralized virtual environment
├── requirements.txt         # Consolidated dependencies
├── setup_environment.py    # Environment setup script
├── start_all_servers.py    # Multi-server startup script
├── activate_and_start.sh   # Convenience shell script
├── test_environment.py     # Environment verification
├── analytics/              # Analytics server
├── ML_Webserver/          # ML prediction service
├── webserver/             # Web server
└── tests/                 # Test suite
```
