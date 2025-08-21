import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import { getModelPerformance, formatCurrency, formatPercentage } from '../services/api';
import ModelDiagnosticsView from './ModelDiagnosticsView';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

interface ModelPerformanceViewProps {}

const ModelPerformanceView: React.FC<ModelPerformanceViewProps> = () => {
  const { modelKey } = useParams<{ modelKey: string }>();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<'performance' | 'diagnostics' | 'calibration'>('performance');
  const [dateRange, setDateRange] = useState<{ start: string; end: string }>({
    start: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
    end: new Date().toISOString().split('T')[0]
  });

  const { data: modelData, isLoading, error } = useQuery({
    queryKey: ['modelPerformance', modelKey, dateRange.start, dateRange.end],
    queryFn: () => getModelPerformance(modelKey!, {
      start_date: dateRange.start,
      end_date: dateRange.end
    }),
    enabled: !!modelKey,
  });

  if (!modelKey) {
    return <div>Model key not provided</div>;
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-100 p-8">
        <div className="max-w-7xl mx-auto">
          <div className="bg-white rounded-lg shadow p-6">
            <div className="h-4 bg-gray-200 rounded w-1/4 mb-4 animate-pulse"></div>
            <div className="h-64 bg-gray-200 rounded animate-pulse"></div>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gray-100 p-8">
        <div className="max-w-7xl mx-auto">
          <div className="bg-red-50 border border-red-200 rounded-lg p-6">
            <h2 className="text-lg font-semibold text-red-800 mb-2">Error Loading Model Performance</h2>
            <p className="text-red-700">Failed to load performance data for this model.</p>
          </div>
        </div>
      </div>
    );
  }

  if (!modelData) {
    return (
      <div className="min-h-screen bg-gray-100 p-8">
        <div className="max-w-7xl mx-auto">
          <div className="bg-white rounded-lg shadow p-6">
            <div className="text-center text-gray-500 py-8">No performance data available for this model</div>
          </div>
        </div>
      </div>
    );
  }

  const { model_info, daily_performance } = modelData;

  // Chart data for cumulative P&L over time
  const cumulativeChartData = {
    labels: daily_performance.map((day: any) => new Date(day.date).toLocaleDateString()),
    datasets: [
      {
        label: 'Cumulative P&L',
        data: daily_performance.map((day: any) => day.cumulative_profit_loss),
        borderColor: 'rgb(59, 130, 246)',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        fill: true,
        tension: 0.1,
      }
    ],
  };

  const cumulativeChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: true,
        text: 'Cumulative Profit/Loss Over Time',
      },
    },
    scales: {
      y: {
        title: {
          display: true,
          text: 'Cumulative P&L ($)',
        },
      },
      x: {
        title: {
          display: true,
          text: 'Date',
        },
      },
    },
  };

  // Chart data for daily P&L
  const dailyChartData = {
    labels: daily_performance.map((day: any) => new Date(day.date).toLocaleDateString()),
    datasets: [
      {
        label: 'Daily P&L',
        data: daily_performance.map((day: any) => day.daily_profit_loss),
        backgroundColor: daily_performance.map((day: any) =>
          day.daily_profit_loss >= 0 ? 'rgba(34, 197, 94, 0.8)' : 'rgba(239, 68, 68, 0.8)'
        ),
        borderColor: daily_performance.map((day: any) =>
          day.daily_profit_loss >= 0 ? 'rgb(34, 197, 94)' : 'rgb(239, 68, 68)'
        ),
        borderWidth: 1,
      }
    ],
  };

  const dailyChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: true,
        text: 'Daily Profit/Loss',
      },
    },
    scales: {
      y: {
        title: {
          display: true,
          text: 'Daily P&L ($)',
        },
      },
      x: {
        title: {
          display: true,
          text: 'Date',
        },
      },
    },
  };

  const renderPerformanceTab = () => (
    <div className="space-y-8">
      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-blue-50 p-4 rounded-lg border border-blue-200">
          <div className="text-sm font-medium text-blue-600">Total Trades</div>
          <div className="text-2xl font-bold text-blue-900">{model_info.total_trades}</div>
        </div>
        <div className="bg-green-50 p-4 rounded-lg border border-green-200">
          <div className="text-sm font-medium text-green-600">Win Rate</div>
          <div className="text-2xl font-bold text-green-900">{formatPercentage(model_info.win_rate)}</div>
        </div>
        <div className="bg-purple-50 p-4 rounded-lg border border-purple-200">
          <div className="text-sm font-medium text-purple-600">Avg Confidence</div>
          <div className="text-2xl font-bold text-purple-900">{formatPercentage(model_info.avg_confidence)}</div>
        </div>
        <div className="bg-orange-50 p-4 rounded-lg border border-orange-200">
          <div className="text-sm font-medium text-orange-600">Total P&L</div>
          <div className={`text-2xl font-bold ${model_info.total_profit_loss >= 0 ? 'text-green-900' : 'text-red-900'}`}>
            {formatCurrency(model_info.total_profit_loss)}
          </div>
        </div>
      </div>

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Cumulative P&L Chart */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Cumulative P&L Over Time</h4>
          <div className="h-64">
            <Line data={cumulativeChartData} options={cumulativeChartOptions} />
          </div>
        </div>

        {/* Daily P&L Chart */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Daily P&L</h4>
          <div className="h-64">
            <Line data={dailyChartData} options={dailyChartOptions} />
          </div>
        </div>
      </div>

      {/* Performance Table */}
      <div className="bg-white rounded-lg shadow p-6">
        <h4 className="text-md font-semibold text-gray-800 mb-3">Daily Performance Details</h4>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Daily P&L</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Cumulative P&L</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Avg Confidence</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {daily_performance.map((day: any, index: number) => (
                <tr key={index} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-sm text-gray-900">
                    {new Date(day.date).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-900">{day.total_trades}</td>
                  <td className="px-4 py-3 text-sm">
                    {formatPercentage(day.win_rate)}
                  </td>
                  <td className="px-4 py-3 text-sm">
                    <span className={day.daily_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}>
                      {formatCurrency(day.daily_profit_loss)}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm">
                    <span className={day.cumulative_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}>
                      {formatCurrency(day.cumulative_profit_loss)}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm">
                    {formatPercentage(day.avg_confidence)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div>
              <button
                onClick={() => navigate('/')}
                className="text-blue-600 hover:text-blue-800 mb-2 flex items-center"
              >
                ← Back to Dashboard
              </button>
              <h1 className="text-3xl font-bold text-gray-900">{model_info.ml_model_key}</h1>
              <p className="mt-1 text-sm text-gray-500">
                {model_info.symbol} • {model_info.timeframe} • {model_info.ml_model_type}
              </p>
            </div>
            <div className="flex items-center space-x-4">
              <div className="text-sm text-gray-500">
                Last updated: {new Date().toLocaleTimeString()}
              </div>
              <div className="w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Date Range Selector */}
        <div className="bg-white rounded-lg shadow p-6 mb-8">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Date Range</h3>
          <div className="flex space-x-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
              <input
                type="date"
                value={dateRange.start}
                onChange={(e) => setDateRange(prev => ({ ...prev, start: e.target.value }))}
                className="border border-gray-300 rounded-md px-3 py-2"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">End Date</label>
              <input
                type="date"
                value={dateRange.end}
                onChange={(e) => setDateRange(prev => ({ ...prev, end: e.target.value }))}
                className="border border-gray-300 rounded-md px-3 py-2"
              />
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="bg-white rounded-lg shadow mb-8">
          <div className="border-b border-gray-200">
            <nav className="-mb-px flex space-x-8 px-6">
              <button
                onClick={() => setActiveTab('performance')}
                className={`py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'performance'
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Performance Overview
              </button>
              <button
                onClick={() => setActiveTab('diagnostics')}
                className={`py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'diagnostics'
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Root Cause Analysis
              </button>
              <button
                onClick={() => setActiveTab('calibration')}
                className={`py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === 'calibration'
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                Confidence Calibration
              </button>
            </nav>
          </div>
          <div className="p-6">
            {activeTab === 'performance' && renderPerformanceTab()}
            {activeTab === 'diagnostics' && (
              <ModelDiagnosticsView modelKey={modelKey} dateRange={dateRange} />
            )}
            {activeTab === 'calibration' && (
              <div className="text-center py-8">
                <h3 className="text-lg font-medium text-gray-900 mb-4">Confidence Calibration Analysis</h3>
                <p className="text-gray-600 mb-4">
                  View detailed confidence calibration analysis for this model.
                </p>
                <button
                  onClick={() => navigate(`/model-calibration/${encodeURIComponent(modelKey)}`)}
                  className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
                >
                  Open Calibration View
                </button>
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
};

export default ModelPerformanceView;
