import React from 'react';
import { useNavigate } from 'react-router-dom';
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
import { Line, Bar } from 'react-chartjs-2';
import { MLPerformance } from '../types/analytics';
import { formatCurrency, formatPercentage } from '../services/api';

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

interface MLPerformanceDashboardProps {
  mlPerformance: MLPerformance;
  isLoading: boolean;
}

const MLPerformanceDashboard: React.FC<MLPerformanceDashboardProps> = ({ mlPerformance, isLoading }) => {
  const navigate = useNavigate();

  const handleModelClick = (modelKey: string) => {
    navigate(`/model/${encodeURIComponent(modelKey)}`);
  };

  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <div className="h-4 bg-gray-200 rounded w-1/4 mb-4 animate-pulse"></div>
        <div className="h-64 bg-gray-200 rounded animate-pulse"></div>
      </div>
    );
  }

  if (!mlPerformance || !mlPerformance.total_predictions) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">ML Performance Metrics</h3>
        <div className="text-center text-gray-500 py-8">No ML performance data available</div>
      </div>
    );
  }

  // Confidence vs Accuracy chart data
  const confidenceData = {
    labels: mlPerformance.confidence_accuracy.map(item => `${(item.confidence_bucket * 100).toFixed(0)}%`),
    datasets: [
      {
        label: 'Accuracy %',
        data: mlPerformance.confidence_accuracy.map(item =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        borderColor: 'rgb(59, 130, 246)',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        fill: true,
        tension: 0.1,
        yAxisID: 'y',
      },
      {
        label: 'Avg P&L',
        data: mlPerformance.confidence_accuracy.map(item => item.avg_profit_loss),
        borderColor: 'rgb(34, 197, 94)',
        backgroundColor: 'rgba(34, 197, 94, 0.1)',
        fill: false,
        tension: 0.1,
        yAxisID: 'y1',
      }
    ],
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
        type: 'linear' as const,
        display: true,
        position: 'left' as const,
        title: {
          display: true,
          text: 'Accuracy %',
        },
        min: 0,
        max: 100,
      },
      y1: {
        type: 'linear' as const,
        display: true,
        position: 'right' as const,
        title: {
          display: true,
          text: 'Avg P&L',
        },
        grid: {
          drawOnChartArea: false,
        },
      },
      x: {
        title: {
          display: true,
          text: 'Confidence Level',
        },
      },
    },
  };

  // Model Performance chart data
  const modelData = {
    labels: mlPerformance.model_performance.map(item =>
      item.ml_model_key.length > 20 ? item.ml_model_key.substring(0, 20) + '...' : item.ml_model_key
    ),
    datasets: [
      {
        label: 'Win Rate %',
        data: mlPerformance.model_performance.map(item =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 1,
      },
      {
        label: 'Avg P&L',
        data: mlPerformance.model_performance.map(item => item.avg_profit_loss),
        backgroundColor: 'rgba(34, 197, 94, 0.8)',
        borderColor: 'rgb(34, 197, 94)',
        borderWidth: 1,
      }
    ],
  };

  const modelOptions = {
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
      },
    },
  };

  return (
    <div className="bg-white rounded-lg shadow p-6 mb-8">
      <h3 className="text-lg font-semibold text-gray-900 mb-6">ML Performance Metrics</h3>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-blue-50 p-4 rounded-lg border border-blue-200">
          <div className="text-sm font-medium text-blue-600">Total Predictions</div>
          <div className="text-2xl font-bold text-blue-900">{mlPerformance.total_predictions}</div>
        </div>
        <div className="bg-green-50 p-4 rounded-lg border border-green-200">
          <div className="text-sm font-medium text-green-600">Accuracy</div>
          <div className="text-2xl font-bold text-green-900">{formatPercentage(mlPerformance.accuracy)}</div>
        </div>
        <div className="bg-purple-50 p-4 rounded-lg border border-purple-200">
          <div className="text-sm font-medium text-purple-600">Avg Confidence</div>
          <div className="text-2xl font-bold text-purple-900">{formatPercentage(mlPerformance.avg_confidence_score)}</div>
        </div>
        <div className="bg-orange-50 p-4 rounded-lg border border-orange-200">
          <div className="text-sm font-medium text-orange-600">Total P&L</div>
          <div className={`text-2xl font-bold ${mlPerformance.total_profit_loss >= 0 ? 'text-green-900' : 'text-red-900'}`}>
            {formatCurrency(mlPerformance.total_profit_loss)}
          </div>
        </div>
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Confidence vs Accuracy Chart */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Confidence vs Accuracy</h4>
          <div className="h-64">
            <Line data={confidenceData} options={confidenceOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Shows how prediction accuracy and average P&L vary with confidence levels
          </p>
        </div>

        {/* Model Performance Chart */}
        <div>
          <h4 className="text-md font-semibold text-gray-800 mb-3">Model Performance</h4>
          <div className="h-64">
            <Bar data={modelData} options={modelOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Win rates and average P&L by ML model
          </p>
        </div>
      </div>

      {/* Model Performance Table */}
      {mlPerformance.model_performance.length > 0 && (
        <div className="mt-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">
            Model Performance Details
            <span className="text-sm font-normal text-gray-500 ml-2">(Click any row to view detailed performance)</span>
          </h4>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Model</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Avg P&L</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Total P&L</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {mlPerformance.model_performance.map((model, index) => (
                  <tr
                    key={index}
                    className="hover:bg-gray-50 cursor-pointer transition-colors duration-150"
                    onClick={() => handleModelClick(model.ml_model_key)}
                  >
                    <td className="px-4 py-3 text-sm text-gray-900 font-mono">{model.ml_model_key}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{model.ml_model_type}</td>
                    <td className="px-4 py-3 text-sm text-gray-900">{model.total_trades}</td>
                    <td className="px-4 py-3 text-sm">
                      {formatPercentage(model.total_trades > 0 ? (model.winning_trades / model.total_trades * 100) : 0)}
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <span className={model.avg_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(model.avg_profit_loss)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm">
                      <span className={model.avg_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(model.total_profit_loss)}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default MLPerformanceDashboard;
