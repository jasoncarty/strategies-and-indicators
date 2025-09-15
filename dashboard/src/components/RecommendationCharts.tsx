import React from 'react';
import { Chart as ChartJS, CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend, PointElement, LineElement } from 'chart.js';
import { Bar, Line } from 'react-chartjs-2';
import { RecommendationCharts } from '../types/analytics';

ChartJS.register(CategoryScale, LinearScale, BarElement, Title, Tooltip, Legend, PointElement, LineElement);

interface RecommendationChartsProps {
  charts: RecommendationCharts;
  isLoading: boolean;
}

const RecommendationChartsComponent: React.FC<RecommendationChartsProps> = ({ charts, isLoading }) => {
  if (isLoading) {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="bg-white rounded-lg shadow p-6 animate-pulse">
            <div className="h-6 bg-gray-200 rounded w-1/3 mb-4"></div>
            <div className="h-64 bg-gray-200 rounded"></div>
          </div>
        ))}
      </div>
    );
  }

  // Accuracy by Model Chart
  const accuracyChartData = {
    labels: charts.accuracy_by_model.map(item => item.model.split('_')[1] || item.model),
    datasets: [
      {
        label: 'Accuracy %',
        data: charts.accuracy_by_model.map(item => item.accuracy),
        backgroundColor: charts.accuracy_by_model.map(item =>
          item.accuracy >= 70 ? 'rgba(34, 197, 94, 0.6)' :
          item.accuracy >= 50 ? 'rgba(251, 191, 36, 0.6)' :
          'rgba(239, 68, 68, 0.6)'
        ),
        borderColor: charts.accuracy_by_model.map(item =>
          item.accuracy >= 70 ? 'rgba(34, 197, 94, 1)' :
          item.accuracy >= 50 ? 'rgba(251, 191, 36, 1)' :
          'rgba(239, 68, 68, 1)'
        ),
        borderWidth: 1,
      },
    ],
  };

  // Confidence Distribution Chart
  const confidenceChartData = {
    labels: charts.confidence_distribution.map(item => item.model.split('_')[1] || item.model),
    datasets: [
      {
        label: 'Avg Confidence',
        data: charts.confidence_distribution.map(item => item.avg_confidence * 100),
        backgroundColor: 'rgba(59, 130, 246, 0.6)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1,
        yAxisID: 'y',
      },
      {
        label: 'Accuracy %',
        data: charts.confidence_distribution.map(item => item.accuracy),
        backgroundColor: 'rgba(16, 185, 129, 0.6)',
        borderColor: 'rgba(16, 185, 129, 1)',
        borderWidth: 1,
        yAxisID: 'y1',
      },
    ],
  };

  // Profit Trend Chart
  const profitChartData = {
    labels: charts.profit_trend.map(item => item.model.split('_')[1] || item.model),
    datasets: [
      {
        label: 'Profit if Followed',
        data: charts.profit_trend.map(item => item.profit_if_followed),
        backgroundColor: 'rgba(34, 197, 94, 0.6)',
        borderColor: 'rgba(34, 197, 94, 1)',
        borderWidth: 1,
      },
      {
        label: 'Profit if Opposite',
        data: charts.profit_trend.map(item => item.profit_if_opposite),
        backgroundColor: 'rgba(239, 68, 68, 0.6)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 1,
      },
      {
        label: 'Recommendation Value',
        data: charts.profit_trend.map(item => item.recommendation_value),
        backgroundColor: 'rgba(59, 130, 246, 0.6)',
        borderColor: 'rgba(59, 130, 246, 1)',
        borderWidth: 1,
      },
    ],
  };

  // Recommendation Breakdown Chart
  const breakdownChartData = {
    labels: charts.recommendation_breakdown.map(item => item.model.split('_')[1] || item.model),
    datasets: [
      {
        label: 'Continue Recommendations',
        data: charts.recommendation_breakdown.map(item => item.continue_recommendations),
        backgroundColor: 'rgba(34, 197, 94, 0.6)',
        borderColor: 'rgba(34, 197, 94, 1)',
        borderWidth: 1,
      },
      {
        label: 'Close Recommendations',
        data: charts.recommendation_breakdown.map(item => item.close_recommendations),
        backgroundColor: 'rgba(239, 68, 68, 0.6)',
        borderColor: 'rgba(239, 68, 68, 1)',
        borderWidth: 1,
      },
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
        display: true,
        font: {
          size: 16,
          weight: 'bold' as const,
        },
      },
    },
    scales: {
      y: {
        beginAtZero: true,
      },
    },
  };

  const confidenceChartOptions = {
    ...chartOptions,
    scales: {
      y: {
        type: 'linear' as const,
        display: true,
        position: 'left' as const,
        beginAtZero: true,
        max: 100,
      },
      y1: {
        type: 'linear' as const,
        display: true,
        position: 'right' as const,
        beginAtZero: true,
        max: 100,
        grid: {
          drawOnChartArea: false,
        },
      },
    },
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
      {/* Accuracy by Model */}
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Accuracy by Model</h3>
        <div className="h-64">
          <Bar data={accuracyChartData} options={chartOptions} />
        </div>
      </div>

      {/* Confidence Distribution */}
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Confidence vs Accuracy</h3>
        <div className="h-64">
          <Bar data={confidenceChartData} options={confidenceChartOptions} />
        </div>
      </div>

      {/* Profit Trend */}
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Profit Analysis</h3>
        <div className="h-64">
          <Bar data={profitChartData} options={chartOptions} />
        </div>
      </div>

      {/* Recommendation Breakdown */}
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Recommendation Breakdown</h3>
        <div className="h-64">
          <Bar data={breakdownChartData} options={chartOptions} />
        </div>
      </div>
    </div>
  );
};

export default RecommendationChartsComponent;
