import React from 'react';
import { Summary } from '../types/analytics';
import { formatCurrency, formatPercentage } from '../services/api';
import {
  ChartBarIcon,
  CurrencyDollarIcon,
  ArrowTrendingUpIcon,
  XCircleIcon,
} from '@heroicons/react/24/outline';

interface SummaryCardsProps {
  summary: Summary;
  isLoading: boolean;
}

const SummaryCards: React.FC<SummaryCardsProps> = ({ summary, isLoading }) => {
  if (isLoading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="bg-white rounded-lg shadow p-6 animate-pulse">
            <div className="h-4 bg-gray-200 rounded w-3/4 mb-2"></div>
            <div className="h-8 bg-gray-200 rounded w-1/2"></div>
          </div>
        ))}
      </div>
    );
  }

  // Convert string values to numbers for safe operations
  const totalTrades = typeof summary.total_trades === 'string' ? parseInt(summary.total_trades) : summary.total_trades;
  const winningTrades = typeof summary.winning_trades === 'string' ? parseInt(summary.winning_trades) : summary.winning_trades;
  const losingTrades = typeof summary.losing_trades === 'string' ? parseInt(summary.losing_trades) : summary.losing_trades;
  const winRate = typeof summary.win_rate === 'string' ? parseFloat(summary.win_rate) : summary.win_rate;
  const avgProfitLoss = typeof summary.avg_profit_loss === 'string' ? parseFloat(summary.avg_profit_loss) : summary.avg_profit_loss;
  const totalProfitLoss = typeof summary.total_profit_loss === 'string' ? parseFloat(summary.total_profit_loss) : summary.total_profit_loss;

  const cards = [
    {
      title: 'Total Trades',
      value: totalTrades,
      icon: ChartBarIcon,
      color: 'text-blue-600',
      bgColor: 'bg-blue-50',
    },
    {
      title: 'Win Rate',
      value: formatPercentage(winRate),
      icon: ArrowTrendingUpIcon,
      color: 'text-success-600',
      bgColor: 'bg-success-50',
    },
    {
      title: 'Total P&L',
      value: formatCurrency(totalProfitLoss),
      icon: CurrencyDollarIcon,
      color: totalProfitLoss >= 0 ? 'text-success-600' : 'text-danger-600',
      bgColor: totalProfitLoss >= 0 ? 'bg-success-50' : 'bg-danger-50',
    },
    {
      title: 'Avg P&L per Trade',
      value: formatCurrency(avgProfitLoss),
      icon: XCircleIcon,
      color: avgProfitLoss >= 0 ? 'text-success-600' : 'text-danger-600',
      bgColor: avgProfitLoss >= 0 ? 'bg-success-50' : 'bg-danger-50',
    },
  ];

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      {cards.map((card, index) => (
        <div
          key={index}
          className={`bg-white rounded-lg shadow p-6 border-l-4 ${card.bgColor} border-l-${card.color.split('-')[1]}-400`}
        >
          <div className="flex items-center">
            <div className={`p-2 rounded-lg ${card.bgColor}`}>
              <card.icon className={`h-6 w-6 ${card.color}`} />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">{card.title}</p>
              <p className={`text-2xl font-bold ${card.color}`}>{card.value}</p>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};

export default SummaryCards;
