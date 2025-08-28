import React from 'react';
import { Bar } from 'react-chartjs-2';
import { PredictionByTimeframe } from '../types/analytics';
import { formatCurrency } from '../services/api';

interface TimeframePerformanceSectionProps {
  timeframes: PredictionByTimeframe[];
}

const TimeframePerformanceSection: React.FC<TimeframePerformanceSectionProps> = ({ timeframes }) => {
  if (!timeframes || timeframes.length === 0) {
    return null;
  }

  // Timeframe performance chart data
  const chartData = {
    labels: timeframes.map(item => item.timeframe),
    datasets: [
      {
        label: 'Win Rate %',
        data: timeframes.map(item =>
          Number(item.total_predictions) > 0 ? (Number(item.correct_predictions) / Number(item.total_predictions) * 100) : 0
        ),
        backgroundColor: 'rgba(16, 185, 129, 0.8)',
        borderColor: 'rgb(16, 185, 129)',
        borderWidth: 2,
        borderRadius: 4,
      },
      {
        label: 'Avg P&L',
        data: timeframes.map(item => Number(item.avg_profit_loss)),
        backgroundColor: 'rgba(59, 130, 246, 0.8)',
        borderColor: 'rgb(59, 130, 246)',
        borderWidth: 2,
        borderRadius: 4,
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
      },
    },
  };

  return (
    <div className="mb-6">
      <h4 className="text-lg font-semibold text-gray-900 mb-4">Timeframe Performance Analysis</h4>

      {/* Timeframe Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {timeframes.map((timeframe, index) => {
          const winRate = Number(timeframe.total_predictions) > 0 ?
            (Number(timeframe.correct_predictions) / Number(timeframe.total_predictions) * 100) : 0;

          return (
            <div key={index} className="bg-gradient-to-br from-blue-50 to-indigo-100 p-4 rounded-lg border border-blue-200">
              <div className="text-sm font-medium text-blue-600 mb-1">Timeframe {timeframe.timeframe}</div>
              <div className="text-2xl font-bold text-blue-900 mb-2">{timeframe.total_predictions} trades</div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>
                  <span className="text-gray-600">Win Rate:</span>
                  <span className="ml-1 font-semibold text-green-700">{winRate.toFixed(1)}%</span>
                </div>
                <div>
                  <span className="text-gray-600">Avg P&L:</span>
                  <span className={`ml-1 font-semibold ${Number(timeframe.avg_profit_loss) >= 0 ? 'text-green-700' : 'text-red-700'}`}>
                    {formatCurrency(Number(timeframe.avg_profit_loss))}
                  </span>
                </div>
              </div>
              <div className="mt-2 text-xs text-blue-600">
                Confidence: {(Number(timeframe.avg_confidence_score) * 100).toFixed(1)}%
              </div>
            </div>
          );
        })}
      </div>

      {/* Timeframe Performance Chart */}
      <div className="h-64 mb-4">
        <Bar data={chartData} options={chartOptions} />
      </div>
      <p className="text-sm text-gray-600 mb-4">
        Win rates and average P&L by different timeframes (H1, M30, M15, M5)
      </p>
    </div>
  );
};

export default TimeframePerformanceSection;
