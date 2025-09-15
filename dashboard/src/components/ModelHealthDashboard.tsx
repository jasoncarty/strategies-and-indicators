import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getModelHealthOverview } from '../services/api';
import {
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon,
  InformationCircleIcon
} from '@heroicons/react/24/outline';

interface ModelHealth {
  model_key: string;
  model_type: string;
  symbol: string;
  timeframe: string;
  status: 'healthy' | 'warning' | 'critical' | 'no_data';
  total_trades: number;
  win_rate: number;
  avg_confidence: number;
  avg_profit_loss: number;
  total_profit_loss: number;
  health_score: number;
  issues: string[];
}

interface ModelHealthSummary {
  total_models: number;
  healthy_models: number;
  warning_models: number;
  critical_models: number;
  overall_health: number;
}

interface ModelHealthData {
  summary: ModelHealthSummary;
  models: ModelHealth[];
  timestamp: string;
}

const ModelHealthDashboard: React.FC = () => {
  const navigate = useNavigate();
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [sortBy, setSortBy] = useState<string>('health_score');

  const { data: healthData, isLoading, error, refetch } = useQuery<ModelHealthData>({
    queryKey: ['modelHealth'],
    queryFn: getModelHealthOverview,
    refetchInterval: 300000, // Refresh every 5 minutes
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-6">
        <div className="flex items-center">
          <XCircleIcon className="h-6 w-6 text-red-400 mr-2" />
          <h3 className="text-lg font-medium text-red-800">Error Loading Model Health</h3>
        </div>
        <p className="mt-2 text-red-700">Failed to load model health data. Please try again.</p>
        <button
          onClick={() => refetch()}
          className="mt-4 px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
        >
          Retry
        </button>
      </div>
    );
  }

  if (!healthData) {
    return <div>No health data available</div>;
  }

  const { summary, models } = healthData;

  // Safely coerce possibly-string numeric fields to numbers
  const toNum = (value: unknown, fallback: number = 0): number => {
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    const parsed = parseFloat(String(value ?? ''));
    return Number.isFinite(parsed) ? parsed : fallback;
  };

  const normalizedModels: ModelHealth[] = (models || []).map((m) => ({
    ...m,
    total_trades: Math.round(toNum((m as any).total_trades, 0)),
    win_rate: toNum((m as any).win_rate, 0),
    avg_confidence: toNum((m as any).avg_confidence, 0),
    avg_profit_loss: toNum((m as any).avg_profit_loss, 0),
    total_profit_loss: toNum((m as any).total_profit_loss, 0),
    health_score: Math.round(toNum((m as any).health_score, 0)),
    issues: Array.isArray((m as any).issues) ? (m as any).issues : [],
  }));

  const overallHealth = toNum((summary as any).overall_health, 0);

  // Filter models by status
  const filteredModels = selectedStatus === 'all'
    ? normalizedModels
    : normalizedModels.filter(model => model.status === selectedStatus);

  // Sort models
  const sortedModels = [...filteredModels].sort((a, b) => {
    switch (sortBy) {
      case 'health_score':
        return a.health_score - b.health_score; // Worst first
      case 'win_rate':
        return a.win_rate - b.win_rate; // Worst first
      case 'avg_profit_loss':
        return a.avg_profit_loss - b.avg_profit_loss; // Worst first
      case 'total_trades':
        return b.total_trades - a.total_trades; // Most trades first
      default:
        return a.health_score - b.health_score;
    }
  });

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircleIcon title="Healthy" className="h-5 w-5 text-green-500" />;
      case 'warning':
        return <ExclamationTriangleIcon title="Warning" className="h-5 w-5 text-yellow-500" />;
      case 'critical':
        return <XCircleIcon title="Critical" className="h-5 w-5 text-red-500" />;
      case 'no_data':
        return <InformationCircleIcon title="No Data" className="h-5 w-5 text-gray-500" />;
      default:
        return <InformationCircleIcon title="Default" className="h-5 w-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy':
        return 'bg-green-100 text-green-800 border-green-200';
      case 'warning':
        return 'bg-yellow-100 text-yellow-800 border-yellow-200';
      case 'critical':
        return 'bg-red-100 text-red-800 border-red-200';
      case 'no_data':
        return 'bg-gray-100 text-gray-800 border-gray-200';
      default:
        return 'bg-gray-100 text-gray-800 border-gray-200';
    }
  };

  const getHealthScoreColor = (score: number) => {
    if (score >= 80) return 'text-green-600';
    if (score >= 60) return 'text-yellow-600';
    return 'text-red-600';
  };

  return (
    <div className="space-y-6 p-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <button
              onClick={() => navigate('/')}
              className="text-blue-600 hover:text-blue-800 mb-2 flex items-center"
            >
            ← Back to Dashboard
          </button>
          <h2 className="text-2xl font-bold text-gray-900">Model Health Dashboard</h2>
          <p className="text-gray-600">Monitor the health and performance of all ML models</p>
        </div>
        <div className="flex items-center space-x-4">
          <button
            onClick={() => refetch()}
            className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
          >
            Refresh
          </button>
          <span className="text-sm text-gray-500">
            Last updated: {new Date(healthData.timestamp).toLocaleString()}
          </span>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="bg-white rounded-lg border p-6">
          <div className="flex items-center">
            <div className="p-2 bg-blue-100 rounded-lg">
              <InformationCircleIcon className="h-6 w-6 text-blue-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Total Models</p>
              <p className="text-2xl font-bold text-gray-900">{summary.total_models}</p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg border p-6">
          <div className="flex items-center">
            <div className="p-2 bg-green-100 rounded-lg">
              <CheckCircleIcon className="h-6 w-6 text-green-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Healthy</p>
              <p className="text-2xl font-bold text-green-600">{summary.healthy_models}</p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg border p-6">
          <div className="flex items-center">
            <div className="p-2 bg-yellow-100 rounded-lg">
              <ExclamationTriangleIcon className="h-6 w-6 text-yellow-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Warning</p>
              <p className="text-2xl font-bold text-yellow-600">{summary.warning_models}</p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg border p-6">
          <div className="flex items-center">
            <div className="p-2 bg-red-100 rounded-lg">
              <XCircleIcon className="h-6 w-6 text-red-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Critical</p>
              <p className="text-2xl font-bold text-red-600">{summary.critical_models}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Overall Health Bar */}
      <div className="bg-white rounded-lg border p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-medium text-gray-900">Overall System Health</h3>
          <span className="text-2xl font-bold text-blue-600">{overallHealth.toFixed(1)}%</span>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-4">
          <div
            className="bg-blue-600 h-4 rounded-full transition-all duration-300"
            style={{ width: `${overallHealth}%` }}
          ></div>
        </div>
      </div>

      {/* Filters and Controls */}
      <div className="bg-white rounded-lg border p-6">
        <div className="flex flex-wrap items-center gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Filter by Status</label>
            <select
              value={selectedStatus}
              onChange={(e) => setSelectedStatus(e.target.value)}
              className="border border-gray-300 rounded-md px-3 py-2"
            >
              <option value="all">All Statuses</option>
              <option value="healthy">Healthy</option>
              <option value="warning">Warning</option>
              <option value="critical">Critical</option>
              <option value="no_data">No Data</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Sort By</label>
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="border border-gray-300 rounded-md px-3 py-2"
            >
              <option value="health_score">Health Score (Worst First)</option>
              <option value="win_rate">Win Rate (Worst First)</option>
              <option value="avg_profit_loss">Avg P&L (Worst First)</option>
              <option value="total_trades">Total Trades (Most First)</option>
            </select>
          </div>

          <div className="ml-auto">
            <span className="text-sm text-gray-500">
              Showing {filteredModels.length} of {models.length} models
            </span>
          </div>
        </div>
      </div>

      {/* Models Table */}
      <div className="bg-white rounded-lg border overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Model
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Health Score
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Performance
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Issues
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {sortedModels.map((model) => (
                <tr key={model.model_key} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div>
                      <div className="text-sm font-medium text-gray-900">
                        {model.symbol} {model.timeframe}
                      </div>
                      <div className="text-sm text-gray-500">
                        {model.model_type} • {model.total_trades} trades
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      {getStatusIcon(model.status)}
                      <span className={`ml-2 inline-flex px-2 py-1 text-xs font-semibold rounded-full border ${getStatusColor(model.status)}`}>
                        {model.status.replace('_', ' ')}
                      </span>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className={`text-lg font-bold ${getHealthScoreColor(model.health_score)}`}>
                      {model.health_score}
                    </div>
                    <div className="text-sm text-gray-500">/ 100</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="space-y-1">
                      <div className="text-sm">
                        <span className="text-gray-500">Win Rate:</span>
                        <span className={`ml-1 font-medium ${model.win_rate >= 50 ? 'text-green-600' : 'text-red-600'}`}>
                          {model.win_rate.toFixed(1)}%
                        </span>
                      </div>
                      <div className="text-sm">
                        <span className="text-gray-500">Avg P&L:</span>
                        <span className={`ml-1 font-medium ${model.avg_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                          ${model.avg_profit_loss.toFixed(2)}
                        </span>
                      </div>
                      <div className="text-sm">
                        <span className="text-gray-500">Confidence:</span>
                        <span className="ml-1 font-medium text-gray-900">
                          {(model.avg_confidence * 100).toFixed(1)}%
                        </span>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="space-y-1">
                      {model.issues.length > 0 ? (
                        model.issues.map((issue, index) => (
                          <div key={index} className="text-sm text-red-600 bg-red-50 px-2 py-1 rounded">
                            {issue}
                          </div>
                        ))
                      ) : (
                        <div className="text-sm text-green-600 bg-green-50 px-2 py-1 rounded">
                          No issues detected
                        </div>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default ModelHealthDashboard;
