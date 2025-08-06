# BreakoutStrategy Analytics System

A comprehensive analytics system for tracking and analyzing BreakoutStrategy EA performance, including ML model effectiveness and market conditions.

## 🚀 Features

- **Trade Tracking**: Complete trade lifecycle tracking with entry/exit data
- **ML Model Analytics**: Performance analysis of ML predictions and model accuracy
- **Market Conditions**: Detailed market condition recording for each trade
- **Performance Metrics**: Win rate, profit factor, drawdown, and more
- **Database Storage**: MySQL database with migration system for scalability
- **Cloud Ready**: Easy migration to cloud databases (AWS RDS, Google Cloud SQL, etc.)

## 📊 Database Schema

### Tables

1. **trades** - Complete trade information
2. **ml_predictions** - ML model predictions and confidence scores
3. **market_conditions** - Market indicators and conditions at trade time
4. **strategy_performance** - Aggregated strategy performance metrics
5. **ml_model_performance** - ML model accuracy and performance
6. **daily_statistics** - Daily performance summaries

## 🛠️ Setup Instructions

### 1. Database Setup

#### Option A: Local MySQL Installation
```bash
# Install MySQL (macOS)
brew install mysql
brew services start mysql

# Or on Ubuntu/Debian
sudo apt-get install mysql-server
sudo systemctl start mysql
```

#### Option B: Docker (Recommended)
```bash
# Create docker-compose.yml
version: '3.8'
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: your_root_password
      MYSQL_DATABASE: breakout_analytics
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:

# Start the database
docker-compose up -d
```

### 2. Environment Configuration

Create a `.env` file in the analytics directory:
```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=breakout_analytics
DB_USER=root
DB_PASSWORD=your_password

# For production, use a dedicated user:
# DB_USER=breakout_user
# DB_PASSWORD=secure_password_2024
```

### 3. Install Dependencies

```bash
cd analytics
pip install -r requirements.txt
```

### 4. Run Database Migrations

```bash
# Run migrations to create tables
python database/run_migrations.py

# Create a dedicated database user (optional)
python database/run_migrations.py --create-user
```

### 5. EA Integration

#### Add Analytics to BreakoutStrategy_ML.mq5

1. **Include the analytics integration file**:
```mql5
#include "../../analytics/ea_integration.mqh"
```

2. **Initialize analytics in OnInit()**:
```mql5
// Initialize analytics
InitializeAnalytics("BreakoutStrategy_ML", "1.00");
```

3. **Record trade entry**:
```mql5
// Record trade entry
RecordTradeEntry("BUY", entry, stopLoss, takeProfit, lotSize,
                "BreakoutStrategy_ML", "1.00");
```

4. **Record ML predictions**:
```mql5
// Record ML prediction
RecordMLPrediction("buy_model_improved", "BUY", prediction.probability,
                  prediction.confidence, features_json);
```

5. **Record market conditions**:
```mql5
// Record market conditions
RecordMarketConditions(features, previousDayHigh, previousDayLow,
                      swingPoint, breakoutDirection);
```

6. **Record trade exit**:
```mql5
// Record trade exit
RecordTradeExit(exit_price, profit_loss, profit_loss_pips);
```

## 📈 Analytics Dashboard

### Performance Metrics

The system tracks comprehensive performance metrics:

- **Trade Statistics**: Total trades, win rate, profit factor
- **ML Model Performance**: Prediction accuracy, confidence scores
- **Market Analysis**: Best performing market conditions
- **Time-based Analysis**: Performance by session, day, month
- **Risk Metrics**: Maximum drawdown, Sharpe ratio, average win/loss

### Sample Queries

```sql
-- Get strategy performance for last 30 days
SELECT * FROM strategy_performance
WHERE strategy_name = 'BreakoutStrategy_ML'
AND period_start >= DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Get ML model accuracy
SELECT model_name, model_type,
       COUNT(*) as total_predictions,
       AVG(prediction_probability) as avg_probability,
       AVG(confidence_score) as avg_confidence
FROM ml_predictions
GROUP BY model_name, model_type;

-- Get best performing market conditions
SELECT rsi_range, win_rate, avg_profit
FROM (
    SELECT
        CASE
            WHEN rsi BETWEEN 30 AND 70 THEN '30-70'
            WHEN rsi < 30 THEN 'Oversold'
            ELSE 'Overbought'
        END as rsi_range,
        COUNT(*) as total_trades,
        SUM(CASE WHEN t.profit_loss > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100 as win_rate,
        AVG(t.profit_loss) as avg_profit
    FROM market_conditions mc
    JOIN trades t ON mc.trade_id = t.trade_id
    WHERE t.status = 'CLOSED'
    GROUP BY rsi_range
) performance;
```

## 🔄 Data Processing

### Automatic Data Import

The analytics system can automatically process JSON files created by the EA:

```bash
# Process analytics data files
python process_analytics_data.py --data-path "Analytics/" --import-to-db
```

### Manual Data Import

```python
from analytics.collector import AnalyticsCollector
from analytics.database.manager import analytics_db

# Initialize collector
collector = AnalyticsCollector("BreakoutStrategy_ML", "1.00", "12345")

# Get performance summary
performance = collector.get_performance_summary(
    "XAUUSD+", "H1",
    datetime(2024, 1, 1),
    datetime(2024, 12, 31)
)

print(f"Win Rate: {performance['win_rate']:.2f}%")
print(f"Profit Factor: {performance['profit_factor']:.2f}")
```

## ☁️ Cloud Deployment

### AWS RDS Setup

1. **Create RDS Instance**:
```bash
aws rds create-db-instance \
    --db-instance-identifier breakout-analytics \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --master-username admin \
    --master-user-password your_password \
    --allocated-storage 20
```

2. **Update Environment**:
```bash
DB_HOST=breakout-analytics.xxxxx.region.rds.amazonaws.com
DB_PORT=3306
DB_NAME=breakout_analytics
DB_USER=admin
DB_PASSWORD=your_password
```

3. **Run Migrations**:
```bash
python database/run_migrations.py
```

### Google Cloud SQL

1. **Create Cloud SQL Instance**:
```bash
gcloud sql instances create breakout-analytics \
    --database-version=MYSQL_8_0 \
    --tier=db-f1-micro \
    --region=us-central1
```

2. **Create Database**:
```bash
gcloud sql databases create breakout_analytics \
    --instance=breakout-analytics
```

## 📊 Monitoring and Alerts

### Performance Alerts

Set up alerts for:
- Win rate drops below threshold
- Maximum drawdown exceeds limit
- ML model accuracy declines
- Unusual trading patterns

### Example Alert Script

```python
from analytics.collector import AnalyticsCollector
import smtplib

def check_performance_alerts():
    collector = AnalyticsCollector("BreakoutStrategy_ML", "1.00", "12345")

    # Get recent performance
    performance = collector.get_performance_summary(
        "XAUUSD+", "H1",
        datetime.now() - timedelta(days=7),
        datetime.now()
    )

    # Check alerts
    if performance['win_rate'] < 40:
        send_alert("Low win rate detected: {:.1f}%".format(performance['win_rate']))

    if performance['profit_factor'] < 1.0:
        send_alert("Negative profit factor: {:.2f}".format(performance['profit_factor']))

def send_alert(message):
    # Email alert implementation
    pass
```

## 🔧 Troubleshooting

### Common Issues

1. **Database Connection Failed**:
   - Check MySQL service is running
   - Verify credentials in .env file
   - Ensure database exists

2. **EA Can't Write Files**:
   - Check file permissions in MT5 Common Files directory
   - Verify analytics directory path

3. **Migration Errors**:
   - Ensure MySQL user has CREATE privileges
   - Check for existing tables with same names

### Debug Mode

Enable debug logging:
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

## 📝 Future Enhancements

- **Real-time Dashboard**: Web-based dashboard for live monitoring
- **Advanced ML Analytics**: Model comparison and optimization suggestions
- **Risk Management**: Automated risk alerts and position sizing recommendations
- **Backtesting Integration**: Import historical backtest results
- **API Endpoints**: REST API for external integrations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
