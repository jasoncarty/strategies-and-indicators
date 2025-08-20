# ML Trading Analytics Dashboard

A modern React dashboard for visualizing ML trading strategy performance and analytics data.

## Features

- **Real-time Performance Metrics**: Win rate, P&L, trade counts
- **Interactive Charts**: Profit/Loss over time using Chart.js
- **Detailed Trade Analysis**: Sortable, searchable trades table with pagination
- **Auto-refresh**: Data updates every 30 seconds
- **Responsive Design**: Works on desktop and mobile devices
- **Modern UI**: Built with Tailwind CSS and Heroicons

## Prerequisites

- Node.js 16+ and npm
- Analytics server running on port 5001 (default)

## Installation

1. Install dependencies:
```bash
npm install
```

2. Configure the API endpoint (optional):
Create a `.env` file in the dashboard directory:
```bash
REACT_APP_API_URL=http://localhost:5001
```

## Running the Dashboard

1. Start the development server:
```bash
npm start
```

2. Open [http://localhost:3000](http://localhost:3000) in your browser

3. The dashboard will automatically connect to your analytics server and display:
   - Summary performance metrics
   - Profit/Loss chart over time
   - Detailed trades table
   - Real-time data updates

## Building for Production

```bash
npm run build
```

This creates a `build` folder with optimized production files.

## API Endpoints Used

The dashboard connects to these analytics server endpoints:

- `GET /analytics/summary` - Performance summary
- `GET /analytics/trades` - Trade data
- `GET /analytics/ml_training_data` - ML training data
- `GET /ml_trade_log` - ML trade logs
- `GET /ml_trade_close` - ML trade closes

## Customization

### Adding New Charts

1. Create a new chart component in `src/components/`
2. Import and add it to the main dashboard layout
3. Use the existing API service or create new endpoints

### Styling

The dashboard uses Tailwind CSS. Customize colors and styling in `tailwind.config.js`.

### Data Refresh

Modify the refresh interval in `src/App.tsx`:
```typescript
refetchInterval: 30000, // 30 seconds
```

## Troubleshooting

### Connection Issues

- Ensure your analytics server is running on the correct port
- Check CORS settings if running on different domains
- Verify the API endpoint in `.env` file

### Build Issues

- Clear `node_modules` and reinstall: `rm -rf node_modules && npm install`
- Check Node.js version compatibility
- Clear build cache: `npm run build -- --reset-cache`

## Tech Stack

- **React 18** with TypeScript
- **Chart.js** with React wrapper for charts
- **Tailwind CSS** for styling
- **Axios** for API calls
- **React Query** for data fetching and caching
- **Heroicons** for icons

## Contributing

1. Create feature branches for new functionality
2. Follow the existing code style and patterns
3. Test with different data scenarios
4. Update documentation as needed
