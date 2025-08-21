import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { getModelCalibration } from '../services/api';
import { Line, Bar } from 'react-chartjs-2';
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
  Filler
} from 'chart.js';

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

interface CalibrationBucket {
  confidence_bucket: string;
  total_trades: number;
  winning_trades: number;
  actual_win_rate: number;
  expected_win_rate: number;
  calibration_error: number;
  calibration_status: string;
  avg_confidence: number;
  avg_prediction: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

interface OverallMetrics {
  total_trades: number;
  total_wins: number;
  overall_win_rate: number;
  overall_calibration_score: number;
  overall_calibration_status: string;
  weighted_calibration_error: number;
  confidence_inversion_detected: boolean;
}

interface CalibrationData {
  model_key: string;
  date_range: {
    start: string;
    end: string;
  };
  overall_metrics: OverallMetrics;
  calibration_buckets: CalibrationBucket[];
  timestamp: string;
}

const ModelCalibrationView: React.FC = () => {
  const { modelKey } = useParams<{ modelKey: string }>();
  const navigate = useNavigate();
  const [startDate, setStartDate] = useState<string>('');
  const [endDate, setEndDate] = useState<string>('');

  const { data: calibrationData, isLoading, error, refetch } = useQuery<CalibrationData>({
    queryKey: ['modelCalibration', modelKey, startDate, endDate],
    queryFn: () => getModelCalibration(modelKey!, { start_date: startDate, end_date: endDate }),
    enabled: !!modelKey,
  });

  if (!modelKey) {
    return <div>No model key provided</div>;
  }

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
          <div className="h-6 w-6 text-red-400 mr-2">❌</div>
          <h3 className="text-lg font-medium text-red-800">Error Loading Calibration Data</h3>
        </div>
        <p className="mt-2 text-red-700">Failed to load calibration data. Please try again.</p>
        <button
          onClick={() => refetch()}
          className="mt-4 px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
        >
          Retry
        </button>
      </div>
    );
  }

  if (!calibrationData) {
    return <div>No calibration data available</div>;
  }

  const { overall_metrics, calibration_buckets, date_range } = calibrationData;

  // Prepare data for charts
  const confidenceLabels = calibration_buckets.map(bucket => bucket.confidence_bucket);
  const actualWinRates = calibration_buckets.map(bucket => bucket.actual_win_rate * 100);
  const expectedWinRates = calibration_buckets.map(bucket => bucket.expected_win_rate * 100);
  const calibrationErrors = calibration_buckets.map(bucket => bucket.calibration_error * 100);
  const tradeCounts = calibration_buckets.map(bucket => bucket.total_trades);

  const calibrationChartData = {
    labels: confidenceLabels,
    datasets: [
      {
        label: 'Actual Win Rate (%)',
        data: actualWinRates,
        borderColor: 'rgb(59, 130, 246)',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        fill: true,
        tension: 0.1,
      },
      {
        label: 'Expected Win Rate (%)',
        data: expectedWinRates,
        borderColor: 'rgb(239, 68, 68)',
        backgroundColor: 'rgba(239, 68, 68, 0.1)',
        fill: true,
        tension: 0.1,
      },
    ],
  };

  const errorChartData = {
    labels: confidenceLabels,
    datasets: [
      {
        label: 'Calibration Error (%)',
        data: calibrationErrors,
        backgroundColor: calibrationErrors.map(error =>
          error < 10 ? 'rgba(34, 197, 94, 0.8)' :
          error < 20 ? 'rgba(245, 158, 11, 0.8)' :
          'rgba(239, 68, 68, 0.8)'
        ),
        borderColor: calibrationErrors.map(error =>
          error < 10 ? 'rgb(34, 197, 94)' :
          error < 20 ? 'rgb(245, 158, 11)' :
          'rgb(239, 68, 68)'
        ),
        borderWidth: 1,
      },
    ],
  };

  const tradeCountChartData = {
    labels: confidenceLabels,
    datasets: [
      {
        label: 'Number of Trades',
        data: tradeCounts,
        backgroundColor: 'rgba(99, 102, 241, 0.8)',
        borderColor: 'rgb(99, 102, 241)',
        borderWidth: 1,
      },
    ],
  };

  const getCalibrationStatusColor = (status: string) => {
    switch (status) {
      case 'well_calibrated':
        return 'text-green-600 bg-green-100 border-green-200';
      case 'moderately_calibrated':
        return 'text-yellow-600 bg-yellow-100 border-yellow-200';
      case 'poorly_calibrated':
        return 'text-red-600 bg-red-100 border-red-200';
      default:
        return 'text-gray-600 bg-gray-100 border-gray-200';
    }
  };

  const getCalibrationScoreColor = (score: number) => {
    if (score >= 80) return 'text-green-600';
    if (score >= 60) return 'text-yellow-600';
    return 'text-red-600';
  };

  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">Model Calibration Analysis</h1>
              <p className="mt-1 text-sm text-gray-500">
                {modelKey} • Confidence Calibration & Performance Validation
              </p>
            </div>
            <div className="flex items-center space-x-4">
              <button
                onClick={() => navigate('/')}
                className="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700"
              >
                Back to Dashboard
              </button>
              <button
                onClick={() => refetch()}
                className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
              >
                Refresh
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Date Range Selector */}
        <div className="bg-white rounded-lg border p-6 mb-8">
          <div className="flex items-center space-x-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="border border-gray-300 rounded-md px-3 py-2"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">End Date</label>
              <input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="border border-gray-300 rounded-md px-3 py-2"
              />
            </div>
            <div className="flex items-end">
              <button
                onClick={() => refetch()}
                className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
              >
                Update Range
              </button>
            </div>
            <div className="ml-4 text-sm text-gray-500">
              Current range: {date_range.start} to {date_range.end}
            </div>
          </div>
        </div>

        {/* Overall Metrics */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-lg border p-6">
            <div className="text-center">
              <p className="text-sm font-medium text-gray-600">Total Trades</p>
              <p className="text-2xl font-bold text-gray-900">{overall_metrics.total_trades}</p>
            </div>
          </div>
          <div className="bg-white rounded-lg border p-6">
            <div className="text-center">
              <p className="text-sm font-medium text-gray-600">Overall Win Rate</p>
              <p className="text-2xl font-bold text-green-600">
                {(overall_metrics.overall_win_rate * 100).toFixed(1)}%
              </p>
            </div>
          </div>
          <div className="bg-white rounded-lg border p-6">
            <div className="text-center">
              <p className="text-sm font-medium text-gray-600">Calibration Score</p>
              <p className={`text-2xl font-bold ${getCalibrationScoreColor(overall_metrics.overall_calibration_score)}`}>
                {overall_metrics.overall_calibration_score.toFixed(1)}%
              </p>
            </div>
          </div>
          <div className="bg-white rounded-lg border p-6">
            <div className="text-center">
              <p className="text-sm font-medium text-gray-600">Status</p>
              <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full border ${getCalibrationStatusColor(overall_metrics.overall_calibration_status)}`}>
                {overall_metrics.overall_calibration_status.replace('_', ' ')}
              </span>
            </div>
          </div>
        </div>

        {/* Critical Alerts */}
        {overall_metrics.confidence_inversion_detected && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-6 mb-8">
            <div className="flex items-center">
              <div className="h-6 w-6 text-red-400 mr-2">🚨</div>
              <h3 className="text-lg font-medium text-red-800">Critical Issue Detected</h3>
            </div>
            <p className="mt-2 text-red-700">
              <strong>Confidence Inversion:</strong> Higher confidence trades are performing worse than lower confidence trades.
              This indicates a fundamental problem with the model's confidence calibration.
            </p>
            <div className="mt-4 text-sm text-red-600">
              <p><strong>Recommendation:</strong> This model should be retrained immediately. The confidence system is broken.</p>
            </div>
          </div>
        )}

        {/* Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          {/* Calibration Chart */}
          <div className="bg-white rounded-lg border p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Confidence vs Actual Performance</h3>
            <Line
              data={calibrationChartData}
              options={{
                responsive: true,
                plugins: {
                  legend: {
                    position: 'top' as const,
                  },
                  title: {
                    display: true,
                    text: 'Expected vs Actual Win Rate by Confidence Level',
                  },
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    max: 100,
                    title: {
                      display: true,
                      text: 'Win Rate (%)',
                    },
                  },
                  x: {
                    title: {
                      display: true,
                      text: 'Confidence Level',
                    },
                  },
                },
              }}
            />
          </div>

          {/* Error Chart */}
          <div className="bg-white rounded-lg border p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">Calibration Error by Confidence Level</h3>
            <Bar
              data={errorChartData}
              options={{
                responsive: true,
                plugins: {
                  legend: {
                    position: 'top' as const,
                  },
                  title: {
                    display: true,
                    text: 'Calibration Error (Lower is Better)',
                  },
                },
                scales: {
                  y: {
                    beginAtZero: true,
                    title: {
                      display: true,
                      text: 'Error (%)',
                    },
                  },
                  x: {
                    title: {
                      display: true,
                      text: 'Confidence Level',
                    },
                  },
                },
              }}
            />
          </div>
        </div>

        {/* Trade Distribution Chart */}
        <div className="bg-white rounded-lg border p-6 mb-8">
          <h3 className="text-lg font-medium text-gray-900 mb-4">Trade Distribution by Confidence Level</h3>
          <Bar
            data={tradeCountChartData}
            options={{
              responsive: true,
              plugins: {
                legend: {
                  position: 'top' as const,
                },
                title: {
                  display: true,
                  text: 'Number of Trades in Each Confidence Bucket',
                },
              },
              scales: {
                y: {
                  beginAtZero: true,
                  title: {
                    display: true,
                    text: 'Number of Trades',
                  },
                },
                x: {
                  title: {
                    display: true,
                    text: 'Confidence Level',
                  },
                },
              },
            }}
          />
        </div>

        {/* Detailed Calibration Table */}
        <div className="bg-white rounded-lg border overflow-hidden">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Detailed Calibration Analysis</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Confidence Bucket
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Trades
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Win Rate
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Expected Win Rate
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Calibration Error
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Avg P&L
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {calibration_buckets.map((bucket) => (
                  <tr key={bucket.confidence_bucket} className="hover:bg-gray-50">
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {bucket.confidence_bucket}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {bucket.total_trades}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
                      <span className={`font-medium ${bucket.actual_win_rate >= 0.5 ? 'text-green-600' : 'text-red-600'}`}>
                        {(bucket.actual_win_rate * 100).toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {(bucket.expected_win_rate * 100).toFixed(1)}%
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
                      <span className={`font-medium ${
                        bucket.calibration_error < 0.1 ? 'text-green-600' :
                        bucket.calibration_error < 0.2 ? 'text-yellow-600' :
                        'text-red-600'
                      }`}>
                        {(bucket.calibration_error * 100).toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full border ${getCalibrationStatusColor(bucket.calibration_status)}`}>
                        {bucket.calibration_status.replace('_', ' ')}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
                      <span className={`font-medium ${bucket.avg_profit_loss >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                        ${bucket.avg_profit_loss.toFixed(2)}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
  );
};

export default ModelCalibrationView;
