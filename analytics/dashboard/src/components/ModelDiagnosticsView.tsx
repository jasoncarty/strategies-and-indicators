import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Bar, Line } from 'react-chartjs-2';
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
} from 'chart.js';
import { getModelDiagnostics, formatCurrency, formatPercentage } from '../services/api';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend
);

interface ModelDiagnosticsViewProps {
  modelKey: string;
  dateRange: { start: string; end: string };
}

const ModelDiagnosticsView: React.FC<ModelDiagnosticsViewProps> = ({ modelKey, dateRange }) => {
  const { data: diagnostics, isLoading, error } = useQuery({
    queryKey: ['modelDiagnostics', modelKey, dateRange.start, dateRange.end],
    queryFn: () => getModelDiagnostics(modelKey, {
      start_date: dateRange.start,
      end_date: dateRange.end
    }),
    enabled: !!modelKey,
  });

  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="h-4 bg-gray-200 rounded w-1/4 mb-4 animate-pulse"></div>
        <div className="h-64 bg-gray-200 rounded animate-pulse"></div>
      </div>
    );
  }

  if (error || !diagnostics) {
    return (
      <div className="bg-white rounded-lg shadow p-6">
        <div className="text-center text-red-500 py-8">Failed to load diagnostics data</div>
      </div>
    );
  }

  // 1. Confidence Analysis Chart
  const confidenceChartData = {
    labels: diagnostics.confidence_analysis.map((item: any) => item.confidence_bucket),
    datasets: [
      {
        label: 'Win Rate %',
        data: diagnostics.confidence_analysis.map((item: any) =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 1,
        yAxisID: 'y',
      },
      {
        label: 'Avg P&L',
        data: diagnostics.confidence_analysis.map((item: any) => parseFloat(item.avg_profit_loss)),
        backgroundColor: 'rgba(34, 197, 94, 0.8)',
        borderColor: 'rgb(34, 197, 94)',
        borderWidth: 1,
        yAxisID: 'y1',
      }
    ],
  };

  const confidenceChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'top' as const },
      title: { display: true, text: 'Performance by Confidence Level' },
    },
    scales: {
      y: {
        type: 'linear' as const,
        display: true,
        position: 'left' as const,
        title: { display: true, text: 'Win Rate %' },
        min: 0,
        max: 100,
      },
      y1: {
        type: 'linear' as const,
        display: true,
        position: 'right' as const,
        title: { display: true, text: 'Avg P&L' },
        grid: { drawOnChartArea: false },
      },
    },
  };

  // 2. Prediction Analysis Chart
  const predictionChartData = {
    labels: diagnostics.prediction_analysis.map((item: any) => item.prediction_bucket),
    datasets: [
      {
        label: 'Win Rate %',
        data: diagnostics.prediction_analysis.map((item: any) =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        backgroundColor: 'rgba(168, 85, 247, 0.8)',
        borderColor: 'rgb(168, 85, 247)',
        borderWidth: 1,
      }
    ],
  };

  // 3. Time Analysis Chart
  const timeChartData = {
    labels: diagnostics.time_analysis.map((item: any) =>
      `${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][item.day_of_week - 1]} ${item.hour_of_day}:00`
    ),
    datasets: [
      {
        label: 'Win Rate %',
        data: diagnostics.time_analysis.map((item: any) =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        backgroundColor: 'rgba(251, 146, 60, 0.8)',
        borderColor: 'rgb(251, 146, 60)',
        borderWidth: 1,
      }
    ],
  };

  // 4. Performance Trend Chart
  const trendChartData = {
    labels: diagnostics.performance_trend.map((item: any) =>
      new Date(item.trade_date).toLocaleDateString()
    ),
    datasets: [
      {
        label: 'Win Rate %',
        data: diagnostics.performance_trend.map((item: any) =>
          item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0
        ),
        borderColor: 'rgb(239, 68, 68)',
        backgroundColor: 'rgba(239, 68, 68, 0.1)',
        fill: true,
        tension: 0.1,
      }
    ],
  };

  const trendChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { position: 'top' as const },
      title: { display: true, text: 'Win Rate Trend Over Time' },
    },
    scales: {
      y: {
        title: { display: true, text: 'Win Rate %' },
        min: 0,
        max: 100,
      },
    },
  };

  return (
    <div className="space-y-6">
      {/* Summary Insights */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 className="text-lg font-semibold text-blue-900 mb-2">🔍 Key Insights</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div>
            <strong>Confidence Issue:</strong>
            {diagnostics.confidence_analysis.length > 0 &&
              parseFloat(diagnostics.confidence_analysis[0].avg_profit_loss) < 0 ?
              ' Higher confidence trades are performing worse' : ' Confidence levels look reasonable'
            }
          </div>
          <div>
            <strong>Risk Management:</strong>
            {diagnostics.risk_analysis.find((r: any) => r.exit_type === 'Stop Loss Hit')?.total_trades >
             diagnostics.risk_analysis.find((r: any) => r.exit_type === 'Take Profit Hit')?.total_trades ?
             ' Stop losses being hit more than take profits' : ' Take profits working well'
            }
          </div>
          <div>
            <strong>Time Pattern:</strong>
            {diagnostics.time_analysis.some((t: any) => t.winning_trades === 0) ?
              ' Some time periods have 0% win rate' : ' Win rate consistent across time'
            }
          </div>
        </div>
      </div>

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Confidence Analysis */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Performance by Confidence Level</h4>
          <div className="h-64">
            <Bar data={confidenceChartData} options={confidenceChartOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Shows how win rate and average P&L vary with model confidence
          </p>
        </div>

        {/* Prediction Analysis */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Performance by Prediction Probability</h4>
          <div className="h-64">
            <Bar data={predictionChartData} options={{ responsive: true, maintainAspectRatio: false }} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Shows win rate by prediction probability buckets
          </p>
        </div>

        {/* Time Analysis */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Performance by Time</h4>
          <div className="h-64">
            <Bar data={timeChartData} options={{ responsive: true, maintainAspectRatio: false }} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            Win rate by day of week and hour of day
          </p>
        </div>

        {/* Performance Trend */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Win Rate Trend</h4>
          <div className="h-64">
            <Line data={trendChartData} options={trendChartOptions} />
          </div>
          <p className="text-sm text-gray-600 mt-2">
            How win rate has changed over time
          </p>
        </div>
      </div>

      {/* Detailed Tables */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Confidence Analysis Table */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Confidence Analysis Details</h4>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Confidence</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Win Rate</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg P&L</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Total P&L</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {diagnostics.confidence_analysis.map((item: any, index: number) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900">{item.confidence_bucket}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{item.total_trades}</td>
                    <td className="px-3 py-2 text-sm">
                      {formatPercentage(item.total_trades > 0 ? (item.winning_trades / item.total_trades * 100) : 0)}
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={parseFloat(item.avg_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(parseFloat(item.avg_profit_loss))}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={parseFloat(item.total_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(parseFloat(item.total_profit_loss))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Risk Analysis Table */}
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Risk Analysis</h4>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Exit Type</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Trades</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Avg P&L</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Total P&L</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {diagnostics.risk_analysis.map((item: any, index: number) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900">{item.exit_type}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{item.total_trades}</td>
                    <td className="px-3 py-2 text-sm">
                      <span className={parseFloat(item.avg_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(parseFloat(item.avg_profit_loss))}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm">
                      <span className={parseFloat(item.total_profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(parseFloat(item.total_profit_loss))}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Feature Analysis */}
      {diagnostics.feature_analysis && diagnostics.feature_analysis.length > 0 && (
        <div className="bg-white rounded-lg shadow p-6">
          <h4 className="text-md font-semibold text-gray-800 mb-3">Feature Correlation Analysis</h4>
          <p className="text-sm text-gray-600 mb-4">
            Sample of recent trades showing technical indicators and their correlation with performance
          </p>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">RSI</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Stoch</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">MACD</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">BB Upper</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">BB Lower</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">P&L</th>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">Confidence</th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {diagnostics.feature_analysis.slice(0, 20).map((item: any, index: number) => (
                  <tr key={index} className="hover:bg-gray-50">
                    <td className="px-3 py-2 text-sm text-gray-900">{parseFloat(item.rsi).toFixed(1)}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{parseFloat(item.stoch_main).toFixed(1)}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{parseFloat(item.macd_main).toFixed(6)}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{parseFloat(item.bb_upper).toFixed(5)}</td>
                    <td className="px-3 py-2 text-sm text-gray-900">{parseFloat(item.bb_lower).toFixed(5)}</td>
                    <td className="px-3 py-2 text-sm">
                      <span className={parseFloat(item.profit_loss) >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(parseFloat(item.profit_loss))}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-sm">{formatPercentage(parseFloat(item.ml_confidence))}</td>
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

export default ModelDiagnosticsView;
