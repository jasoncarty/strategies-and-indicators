import React from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { Line, Bar, Doughnut } from 'react-chartjs-2';
import { MLPredictions } from '../types/analytics';
import { formatCurrency, formatPercentage } from '../services/api';
import TimeframePerformanceSection from './TimeframePerformanceSection';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

interface MLPredictionsDashboardProps {
  mlPredictions: MLPredictions;
  isLoading: boolean;
}

const MLPredictionsDashboard: React.FC<MLPredictionsDashboardProps> = ({ mlPredictions, isLoading }) => {
  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <div className="h-4 bg-gray-200 rounded w-1/4 mb-4 animate-pulse"></div>
        <div className="h-64 bg-gray-200 rounded animate-pulse"></div>
      </div>
    );
  }

  if (!mlPredictions || !mlPredictions.prediction_by_type.length) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">ML Predictions Analysis</h3>
        <div className="text-center text-gray-500 py-8">No ML prediction data available</div>
      </div>
    );
  }

  // Prediction by Type chart data
  const typeData = {
    labels: mlPredictions.prediction_by_type.map(item => item.ml_model_type.toUpperCase()),
    datasets: [
      {
        label: 'Win Rate %',
        data: mlPredictions.prediction_by_type.map(item =>
          Number(item.total_predictions) > 0 ? (Number(item.correct_predictions) / Number(item.total_predictions) * 100) : 0
        ),
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 1,
      },
      {
        label: 'Avg P&L',
        data: mlPredictions.prediction_by_type.map(item => Number(item.avg_profit_loss)),
        backgroundColor: 'rgba(34, 197, 94, 0.8)',
        borderColor: 'rgb(34, 197, 94)',
        borderWidth: 1,
      }
    ],
  };

  // Prediction by Symbol chart data
  const symbolData = {
    labels: mlPredictions.prediction_by_symbol.map(item => item.symbol),
    datasets: [
      {
        label: 'Win Rate %',
        data: mlPredictions.prediction_by_symbol.map(item =>
          Number(item.total_predictions) > 0 ? (Number(item.correct_predictions) / Number(item.total_predictions) * 100) : 0
        ),
        backgroundColor: 'rgba(168, 85, 247, 0.8)',
        borderColor: 'rgb(168, 85, 247)',
        borderWidth: 1,
      }
    ],
  };

  // Confidence Buckets chart data
  const confidenceData = {
    labels: mlPredictions.confidence_buckets.map(item => item.confidence_range),
    datasets: [
      {
        label: 'Accuracy %',
        data: mlPredictions.confidence_buckets.map(item =>
          Number(item.total_predictions) > 0 ? (Number(item.correct_predictions) / Number(item.total_predictions) * 100) : 0
        ),
        borderColor: 'rgb(59, 130, 246)',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        fill: true,
        tension: 0.1,
      }
    ],
  };

  // Recent Performance chart data
  const recentData = {
    labels: mlPredictions.recent_performance.map(item => item.trade_date),
    datasets: [
      {
        label: 'Daily Win Rate %',
        data: mlPredictions.recent_performance.map(item =>
          Number(item.total_predictions) > 0 ? (Number(item.correct_predictions) / Number(item.total_predictions) * 100) : 0
        ),
        borderColor: 'rgb(34, 197, 94)',
        backgroundColor: 'rgba(34, 197, 94, 0.1)',
        fill: false,
        tension: 0.1,
      }
    ],
  };

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: false,
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        max: 100,
      },
    },
  };

  const confidenceOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: false,
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        max: 100,
        title: {
          display: true,
          text: 'Accuracy %',
        },
      },
      x: {
        title: {
          display: true,
          text: 'Confidence Range',
        },
      },
    },
  };

  return (
    <div className="bg-white rounded-lg shadow p-6 mb-8">
      <h3 className="text-lg font-semibold text-gray-900 mb-6">ML Predictions Analysis</h3>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-blue-50 p-4 rounded-lg border border-blue-200">
          <div className="text-sm font-medium text-blue-600">Total Predictions</div>
          <div className="text-2xl font-bold text-blue-900">
            {mlPredictions.prediction_by_type.reduce((sum, item) => sum + Number(item.total_predictions), 0)}
          </div>
        </div>
        <div className="bg-green-50 p-4 rounded-lg border border-green-200">
          <div className="text-sm font-medium text-green-600">Overall Accuracy</div>
          <div className="text-2xl font-bold text-green-900">
            {(() => {
              const total = mlPredictions.prediction_by_type.reduce((sum, item) => sum + Number(item.total_predictions), 0);
              const correct = mlPredictions.prediction_by_type.reduce((sum, item) => sum + Number(item.correct_predictions), 0);
              return total > 0 ? formatPercentage((correct / total) * 100) : '0%';
            })()}
          </div>
        </div>
        <div className="bg-purple-50 p-4 rounded-lg border border-purple-200">
          <div className="text-sm font-medium text-purple-600">Symbols Traded</div>
          <div className="text-2xl font-bold text-purple-900">{mlPredictions.prediction_by_symbol.length}</div>
        </div>
        <div className="bg-orange-50 p-4 rounded-lg border border-orange-200">
          <div className="text-sm font-medium text-orange-600">Timeframes</div>
          <div className="text-2xl font-bold text-orange-900">{mlPredictions.prediction_by_timeframe.length}</div>
        </div>
      </div>

      {/* Charts Row 1 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Prediction by Type */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Performance by Model Type</h4>
          <div className="h-64">
            <Bar data={typeData} options={chartOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Win rates and average P&L by BUY/SELL predictions
          </p>
        </div>

        {/* Prediction by Symbol */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Performance by Symbol</h4>
          <div className="h-64">
            <Bar data={symbolData} options={chartOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Win rates across different currency pairs and assets
          </p>
        </div>
      </div>

      {/* Charts Row 2 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Confidence vs Accuracy */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Confidence vs Accuracy</h4>
          <div className="h-64">
            <Line data={confidenceData} options={confidenceOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            How prediction accuracy varies with confidence levels
          </p>
        </div>

        {/* Recent Performance */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Daily Performance Trend</h4>
          <div className="h-64">
            <Line data={recentData} options={chartOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Win rate trends over the last 30 days
          </p>
        </div>
      </div>

      {/* Timeframe Performance Section */}
      <TimeframePerformanceSection timeframes={mlPredictions.prediction_by_timeframe} />

      {/* Detailed Tables */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Prediction by Type Table */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Model Type Performance</h4>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg P&L</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mlPredictions.prediction_by_type.map((type, index) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900 font-medium">{type.ml_model_type.toUpperCase()}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{type.total_predictions}</td>
                    <td className="px-3 py-2 text-sm">
                      {formatPercentage(Number(type.total_predictions) > 0 ? (Number(type.correct_predictions) / Number(type.total_predictions) * 100) : 0)}
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={Number(type.avg_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(Number(type.avg_profit_loss))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Prediction by Symbol Table */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Symbol Performance</h4>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Symbol</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Total P&L</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mlPredictions.prediction_by_symbol.map((symbol, index) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900 font-medium">{symbol.symbol}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{symbol.total_predictions}</td>
                    <td className="px-3 py-2 text-sm">
                      {formatPercentage(Number(symbol.total_predictions) > 0 ? (Number(symbol.correct_predictions) / Number(symbol.total_predictions) * 100) : 0)}
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={Number(symbol.total_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(Number(symbol.total_profit_loss))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Timeframe Performance Details Table */}
      <div className="mt-6">
        <h4 className="text-md font-semibold text-gray-800 mb-3">Timeframe Performance Details</h4>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Timeframe</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg P&L</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Total P&L</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg Confidence</th>
                <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg Prediction</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {mlPredictions.prediction_by_timeframe.map((timeframe, index) => {
                const winRate = Number(timeframe.total_predictions) > 0 ?
                  (Number(timeframe.correct_predictions) / Number(timeframe.total_predictions) * 100) : 0;

                return (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900 font-medium">
                      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                        {timeframe.timeframe}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm text-gray-900">{timeframe.total_predictions}</td>
                    <td className="px-3 py-2 text-sm">
                      <span className={`font-semibold ${winRate >= 50 ? 'text-green-600' : 'text-red-600'}`}>
                        {winRate.toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={Number(timeframe.avg_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(Number(timeframe.avg_profit_loss))}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={Number(timeframe.total_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(Number(timeframe.total_profit_loss))}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm text-gray-900">
                      {(Number(timeframe.avg_confidence_score) * 100).toFixed(1)}%
                    </td>
                    <td className="px-3 py-2 text-sm text-gray-900">
                      {(Number(timeframe.avg_prediction_probability) * 100).toFixed(1)}%
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default MLPredictionsDashboard;
