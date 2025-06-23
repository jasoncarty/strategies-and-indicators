# MT5 Strategy Tester Web Server

A local web server and database system for storing and analyzing MT5 strategy tester results.

## Features

- **RESTful API** for storing strategy test results
- **SQLite Database** for local data storage
- **Web Dashboard** for viewing and analyzing results
- **MQL5 Integration** with ready-to-use include file
- **Statistics Tracking** with comprehensive metrics

## Quick Start

### 1. Start the Web Server

```bash
cd strategies-and-indicators/webserver
python start_server.py
```

The server will be available at: http://localhost:5000

### 2. Configure MT5

1. Open MT5
2. Go to **Tools → Options → Expert Advisors**
3. Check **"Allow WebRequest for listed URL"**
4. Add `http://localhost:5000` to the list
5. Click **OK**

### 3. Use in Your EA

Include the `WebServerAPI.mqh` file in your EA:

```mql5
#include "WebServerAPI.mqh"

// In your EA's OnTester() function:
double OnTester()
{
    // Extract test results
    StrategyTestResult result;
    result.strategy_name = "My Strategy";
    result.symbol = _Symbol;
    result.timeframe = EnumToString(_Period);
    result.start_date = 0; // Set to actual start date
    result.end_date = 0;   // Set to actual end date
    result.initial_deposit = 10000;
    result.final_balance = 0; // Set to actual final balance
    result.profit = 0;        // Set to actual profit
    result.profit_factor = 0; // Set to actual profit factor
    result.max_drawdown = 0;  // Set to actual max drawdown
    result.total_trades = 0;  // Set to actual total trades
    result.winning_trades = 0; // Set to actual winning trades
    result.losing_trades = 0;  // Set to actual losing trades
    result.win_rate = 0;       // Set to actual win rate
    result.sharpe_ratio = 0;   // Set to actual Sharpe ratio
    result.parameters = "{}";  // JSON string of parameters

    TradeData trades[];
    ArrayResize(trades, 0); // Initialize empty array

    // Send to web server
    SendTestResultsToServer(result, trades);

    return 0;
}
```

## API Endpoints

### POST /api/test
Save strategy test results

**Request Body:**
```json
{
    "strategy_name": "My Strategy",
    "symbol": "EURUSD",
    "timeframe": "H1",
    "start_date": "2024-01-01T00:00:00",
    "end_date": "2024-12-31T23:59:59",
    "initial_deposit": 10000.0,
    "final_balance": 11500.0,
    "profit": 1500.0,
    "profit_factor": 1.5,
    "max_drawdown": 5.2,
    "total_trades": 100,
    "winning_trades": 65,
    "losing_trades": 35,
    "win_rate": 65.0,
    "sharpe_ratio": 1.2,
    "parameters": "{\"param1\": \"value1\"}",
    "trades": [
        {
            "ticket": 12345,
            "symbol": "EURUSD",
            "type": "BUY",
            "volume": 0.1,
            "open_price": 1.0850,
            "close_price": 1.0870,
            "open_time": "2024-01-01T10:00:00",
            "close_time": "2024-01-01T12:00:00",
            "profit": 20.0,
            "swap": 0.0,
            "commission": -1.0,
            "net_profit": 19.0
        }
    ]
}
```

### GET /api/tests
Get all strategy tests

### GET /api/test/{id}
Get specific test with trades

### DELETE /api/test/{id}
Delete a test

### GET /api/stats
Get overall statistics

## Database Schema

### StrategyTest Table
- `id` - Primary key
- `strategy_name` - Name of the strategy
- `symbol` - Trading symbol
- `timeframe` - Timeframe used
- `start_date` - Test start date
- `end_date` - Test end date
- `initial_deposit` - Initial deposit amount
- `final_balance` - Final balance
- `profit` - Total profit/loss
- `profit_factor` - Profit factor
- `max_drawdown` - Maximum drawdown
- `total_trades` - Total number of trades
- `winning_trades` - Number of winning trades
- `losing_trades` - Number of losing trades
- `win_rate` - Win rate percentage
- `sharpe_ratio` - Sharpe ratio
- `test_date` - When the test was saved
- `parameters` - JSON string of strategy parameters

### Trade Table
- `id` - Primary key
- `strategy_test_id` - Foreign key to StrategyTest
- `ticket` - Trade ticket number
- `symbol` - Trading symbol
- `type` - BUY or SELL
- `volume` - Trade volume
- `open_price` - Open price
- `close_price` - Close price
- `open_time` - Open time
- `close_time` - Close time
- `profit` - Trade profit
- `swap` - Swap charges
- `commission` - Commission
- `net_profit` - Net profit

## Web Dashboard

Access the dashboard at http://localhost:5000 to:

- View all strategy tests in a table format
- See overall statistics
- View detailed test information
- Delete tests
- Refresh data

## Installation

### Prerequisites
- Python 3.7 or higher
- MT5 with WebRequest enabled

### Setup
1. Clone or download the webserver folder
2. Run `python start_server.py`
3. The script will automatically:
   - Create a virtual environment
   - Install required packages
   - Start the web server

### Manual Setup
```bash
cd strategies-and-indicators/webserver
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

## Troubleshooting

### WebRequest Error -1
- Make sure `http://localhost:5000` is added to MT5's Allow WebRequest list
- Check that the web server is running

### Import Errors
- Make sure all requirements are installed: `pip install -r requirements.txt`
- Use a virtual environment to avoid conflicts

### Database Issues
- The database file `strategy_tester.db` will be created automatically
- If corrupted, delete the file and restart the server

## Development

### Adding New Features
1. Modify `app.py` for new API endpoints
2. Update `WebServerAPI.mqh` for new MQL5 functions
3. Enhance the dashboard in `templates/index.html`

### Database Migrations
The current setup uses SQLite for simplicity. For production, consider:
- PostgreSQL for better performance
- Database migrations for schema changes
- Backup strategies

## License

This project is open source and available under the MIT License.
