import React from 'react';
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
import { Line } from 'react-chartjs-2';
import { Trade } from '../types/analytics';
import { formatCurrency } from '../services/api';

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

interface ProfitLossChartProps {
  trades: Trade[];
  isLoading: boolean;
}

const ProfitLossChart: React.FC<ProfitLossChartProps> = ({ trades, isLoading }) => {
  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <div className="h-4 bg-gray-200 rounded w-1/4 mb-4"></div>
        <div className="h-64 bg-gray-200 rounded animate-pulse"></div>
      </div>
    );
  }

  if (!trades || trades.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Profit/Loss Over Time</h3>
        <div className="text-center text-gray-500 py-8">No trade data available</div>
      </div>
    );
  }

  // Process trades to create cumulative P&L data
  const closedTrades = trades.filter(trade => trade.status === 'CLOSED' && trade.profit_loss !== null);

  if (closedTrades.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Profit/Loss Over Time</h3>
        <div className="text-center text-gray-500 py-8">No closed trades available</div>
      </div>
    );
  }

  // Sort trades by exit time and calculate cumulative P&L
  const sortedTrades = closedTrades.sort((a, b) =>
    new Date(a.exit_time!).getTime() - new Date(b.exit_time!).getTime()
  );

  let cumulativePL = 0;
  const chartData = sortedTrades.map(trade => {
    cumulativePL += trade.profit_loss!;
    return {
      date: new Date(trade.exit_time!).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
      cumulativePL,
      tradePL: trade.profit_loss!,
    };
  });

  const data = {
    labels: chartData.map(d => d.date),
    datasets: [
      {
        label: 'Cumulative P&L',
        data: chartData.map(d => d.cumulativePL),
        borderColor: 'rgb(59, 130, 246)',
        backgroundColor: 'rgba(59, 130, 246, 0.1)',
        fill: true,
        tension: 0.1,
        pointBackgroundColor: 'rgb(59, 130, 246)',
        pointBorderColor: '#fff',
        pointBorderWidth: 2,
        pointRadius: 4,
      },
    ],
  };

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: false,
      },
      tooltip: {
        callbacks: {
          label: function(context: any) {
            return `Cumulative P&L: ${formatCurrency(context.parsed.y)}`;
          },
        },
      },
    },
    scales: {
      y: {
        beginAtZero: false,
        ticks: {
          callback: function(value: any) {
            return formatCurrency(value);
          },
        },
        grid: {
          color: 'rgba(0, 0, 0, 0.1)',
        },
      },
      x: {
        grid: {
          color: 'rgba(0, 0, 0, 0.1)',
        },
      },
    },
    interaction: {
      intersect: false,
      mode: 'index' as const,
    },
  };

  return (
    <div className="bg-white rounded-lg shadow p-6 mb-8">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Profit/Loss Over Time</h3>
      <div className="h-64">
        <Line data={data} options={options} />
      </div>
      <div className="mt-4 text-sm text-gray-600">
        <p>Showing {closedTrades.length} closed trades</p>
        <p>Final cumulative P&L: <span className={cumulativePL >= 0 ? 'text-success-600 font-semibold' : 'text-danger-600 font-semibold'}>
          {formatCurrency(cumulativePL)}
        </span></p>
      </div>
    </div>
  );
};

export default ProfitLossChart;
