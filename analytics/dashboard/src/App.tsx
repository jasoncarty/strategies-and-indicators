import React from 'react';
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { getSummary, getTrades, getMLPerformance, getMLPredictions } from './services/api';
import SummaryCards from './components/SummaryCards';
import ProfitLossChart from './components/ProfitLossChart';
import TradesTable from './components/TradesTable';
import MLPerformanceDashboard from './components/MLPerformanceDashboard';
import ModelHealthDashboard from './components/ModelHealthDashboard';
import MLPredictionsDashboard from './components/MLPredictionsDashboard';
import ModelPerformanceView from './components/ModelPerformanceView';
import ModelCalibrationView from './components/ModelCalibrationView';
import ModelRetrainingDashboard from './components/ModelRetrainingDashboard';
import { Summary, Trade, MLPerformance, MLPredictions } from './types/analytics';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchInterval: 30000, // Refetch every 30 seconds
      staleTime: 10000, // Consider data stale after 10 seconds
    },
  },
});

function Dashboard() {
  const { data: summary, isLoading: summaryLoading, error: summaryError } = useQuery<Summary>({
    queryKey: ['summary'],
    queryFn: getSummary,
  });

  const { data: trades, isLoading: tradesLoading, error: tradesError } = useQuery<Trade[]>({
    queryKey: ['trades'],
    queryFn: () => getTrades({ limit: 1000 }), // Get more trades for better chart data
  });

  const { data: mlPerformance, isLoading: mlPerformanceLoading, error: mlPerformanceError } = useQuery<MLPerformance>({
    queryKey: ['mlPerformance'],
    queryFn: getMLPerformance,
  });

  const { data: mlPredictions, isLoading: mlPredictionsLoading, error: mlPredictionsError } = useQuery<MLPredictions>({
    queryKey: ['mlPredictions'],
    queryFn: getMLPredictions,
  });

  if (summaryError || tradesError || mlPerformanceError || mlPredictionsError) {
    return (
      <div className="min-h-screen bg-gray-100 p-8">
        <div className="max-w-7xl mx-auto">
          <div className="bg-red-50 border border-red-200 rounded-lg p-6">
            <h2 className="text-lg font-semibold text-red-800 mb-2">Error Loading Dashboard</h2>
            <p className="text-red-700">
              {summaryError ? `Summary Error: ${summaryError.message}` : ''}
              {tradesError ? `Trades Error: ${tradesError.message}` : ''}
              {mlPerformanceError ? `ML Performance Error: ${mlPerformanceError.message}` : ''}
              {mlPredictionsError ? `ML Predictions Error: ${mlPredictionsError.message}` : ''}
            </p>
            <p className="text-red-600 mt-2">
              Please check that the analytics server is running and accessible.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">ML Trading Analytics Dashboard</h1>
              <p className="mt-1 text-sm text-gray-500">
                Real-time insights into your ML-powered trading strategies
              </p>
            </div>
            <div className="flex items-center space-x-4">
              <div className="text-sm text-gray-500">
                Last updated: {new Date().toLocaleTimeString()}
              </div>
              <div className="w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
              <a href="/model-health" className="ml-4 inline-flex items-center px-3 py-1.5 rounded-md text-sm font-medium bg-blue-600 text-white hover:bg-blue-700">
                Model Health
              </a>
              <a href="/model-retraining" className="ml-2 inline-flex items-center px-3 py-1.5 rounded-md text-sm font-medium bg-green-600 text-white hover:bg-green-700">
                Retraining
              </a>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Summary Cards */}
        <SummaryCards
          summary={summary || { total_trades: 0, winning_trades: 0, losing_trades: 0, win_rate: 0, avg_profit_loss: 0, total_profit_loss: 0 }}
          isLoading={summaryLoading}
        />

        {/* Charts Row */}
        <div className="grid grid-cols-1">
          <ProfitLossChart trades={trades || []} isLoading={tradesLoading} />

          <MLPerformanceDashboard
            mlPerformance={mlPerformance || {
              total_predictions: 0,
              correct_predictions: 0,
              incorrect_predictions: 0,
              accuracy: 0,
              avg_prediction_probability: 0,
              avg_confidence_score: 0,
              avg_profit_loss: 0,
              total_profit_loss: 0,
              avg_win: 0,
              avg_loss: 0,
              model_performance: [],
              confidence_accuracy: []
            }}
            isLoading={mlPerformanceLoading}
          />
        </div>

        {/* ML Predictions Dashboard */}
        <div className="mb-8">
          <MLPredictionsDashboard
            mlPredictions={mlPredictions || {
              prediction_by_type: [],
              prediction_by_symbol: [],
              prediction_by_timeframe: [],
              confidence_buckets: [],
              recent_performance: []
            }}
            isLoading={mlPredictionsLoading}
          />
        </div>

        {/* Trades Table */}
        <TradesTable trades={trades || []} isLoading={tradesLoading} />
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 mt-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="text-center text-sm text-gray-500">
            <p>ML Trading Analytics Dashboard • Built with React & Chart.js</p>
            <p className="mt-1">Data refreshes automatically every 30 seconds</p>
          </div>
        </div>
      </footer>
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Router>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/model/:modelKey" element={<ModelPerformanceView />} />
          <Route path="/model-health" element={<ModelHealthDashboard />} />
          <Route path="/model-calibration/:modelKey" element={<ModelCalibrationView />} />
          <Route path="/model-retraining" element={<ModelRetrainingDashboard />} />
        </Routes>
      </Router>
    </QueryClientProvider>
  );
}

export default App;
