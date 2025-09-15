# Recommendation Tracking Dashboard Setup

## Overview

I've added comprehensive recommendation tracking functionality to your React dashboard. This includes:

- **Recommendation Summary Cards** - High-level metrics
- **Performance Charts** - Visual analysis of recommendation accuracy and profitability
- **Insights Panel** - Actionable insights for ML model improvement
- **Filtering System** - Filter by strategy, symbol, timeframe, and time period

## What's Been Added

### 1. New Components
- `RecommendationSummaryCards.tsx` - Summary metrics cards
- `RecommendationCharts.tsx` - Interactive charts for performance analysis
- `RecommendationInsights.tsx` - Insights and recommendations panel
- `RecommendationTrackingDashboard.tsx` - Main dashboard component

### 2. Updated Files
- `types/analytics.ts` - Added recommendation tracking types
- `services/api.ts` - Added API functions for recommendation data
- `App.tsx` - Added recommendation tracking route and navigation

### 3. New Route
- `/recommendations` - Access the recommendation tracking dashboard

## Setup Instructions

### 1. Database Migration
First, run the database migration to create the recommendation tracking tables:

```bash
# Apply the recommendation tracking migration
mysql -u your_username -p your_database < analytics/database/migrations/016_add_recommendation_tracking.sql
```

### 2. Start the Analytics Service
Make sure your analytics service is running with the new recommendation endpoints:

```bash
cd analytics
python app.py
```

### 3. Start the Dashboard
Start your React dashboard:

```bash
cd dashboard
npm start
```

### 4. Access the Recommendation Dashboard
Navigate to `http://localhost:3000/recommendations` in your browser.

## Features

### Summary Cards
- **Total Recommendations** - Number of recommendations made
- **Overall Accuracy** - Percentage of correct recommendations
- **Total Profit** - Profit from following recommendations
- **Recommendation Value** - Value added by recommendations vs opposite actions

### Performance Charts
- **Accuracy by Model** - Bar chart showing accuracy for each ML model
- **Confidence vs Accuracy** - Dual-axis chart comparing confidence levels with accuracy
- **Profit Analysis** - Comparison of profit if followed vs opposite actions
- **Recommendation Breakdown** - Continue vs close recommendations by model

### Insights Panel
- **Performance Insights** - Automated analysis of recommendation performance
- **Action Items** - Specific recommendations for model improvement
- **Summary Stats** - Key metrics and critical issues count

### Filtering
- **Strategy** - Filter by trading strategy
- **Symbol** - Filter by trading symbol (EURUSD, XAUUSD, etc.)
- **Timeframe** - Filter by timeframe (M5, M15, H1, etc.)
- **Days** - Filter by time period (7, 30, 90, 180, 365 days)

## API Endpoints

The dashboard consumes these new API endpoints:

- `GET /dashboard/recommendations/summary` - Summary metrics
- `GET /dashboard/recommendations/performance` - Performance data and charts
- `GET /dashboard/recommendations/insights` - Insights and recommendations
- `GET /dashboard/recommendations/timeline` - Timeline data (placeholder)

## Data Flow

1. **Recommendation Creation** - When `/active_trade_recommendation` is called, it automatically tracks the recommendation
2. **Outcome Tracking** - When trades close, use the provided scripts to update outcomes
3. **Dashboard Display** - The dashboard fetches and displays the tracked data

## Next Steps

1. **Test the Dashboard** - Navigate to `/recommendations` and verify everything loads
2. **Generate Some Data** - Make some active trade recommendations to populate the dashboard
3. **Update Trade Outcomes** - Use the provided scripts to track recommendation outcomes
4. **Monitor Performance** - Use the insights to improve your ML models

## Troubleshooting

### No Data Showing
- Ensure the analytics service is running
- Check that the database migration was applied
- Verify the API endpoints are accessible

### Charts Not Loading
- Check browser console for errors
- Ensure chart.js dependencies are installed
- Verify the data structure matches the expected format

### API Errors
- Check analytics service logs
- Verify the recommendation tracking endpoints are implemented
- Ensure the database tables exist

## Customization

You can customize the dashboard by:

- **Adding New Charts** - Extend the `RecommendationCharts` component
- **Modifying Insights** - Update the insights logic in the analytics service
- **Adding Filters** - Extend the filter options in the dashboard
- **Styling** - Update the Tailwind CSS classes for different styling

The recommendation tracking system is now fully integrated into your existing dashboard and ready to help you improve your ML models!
