import React from 'react';
import { RecommendationSummary } from '../types/analytics';
import { formatCurrency, formatPercentage } from '../services/api';

interface RecommendationSummaryCardsProps {
  summary: RecommendationSummary;
  isLoading: boolean;
}

const RecommendationSummaryCards: React.FC<RecommendationSummaryCardsProps> = ({ summary, isLoading }) => {
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

  const cards = [
    {
      title: 'Total Recommendations',
      value: summary.total_recommendations.toLocaleString(),
      icon: '📊',
      color: 'text-blue-600',
      bgColor: 'bg-blue-50',
      borderColor: 'border-blue-200'
    },
    {
      title: 'Overall Accuracy',
      value: formatPercentage(summary.overall_accuracy),
      icon: '🎯',
      color: summary.overall_accuracy >= 70 ? 'text-green-600' : summary.overall_accuracy >= 50 ? 'text-yellow-600' : 'text-red-600',
      bgColor: summary.overall_accuracy >= 70 ? 'bg-green-50' : summary.overall_accuracy >= 50 ? 'bg-yellow-50' : 'bg-red-50',
      borderColor: summary.overall_accuracy >= 70 ? 'border-green-200' : summary.overall_accuracy >= 50 ? 'border-yellow-200' : 'border-red-200'
    },
    {
      title: 'Total Profit',
      value: formatCurrency(summary.total_profit),
      icon: '💰',
      color: summary.total_profit >= 0 ? 'text-green-600' : 'text-red-600',
      bgColor: summary.total_profit >= 0 ? 'bg-green-50' : 'bg-red-50',
      borderColor: summary.total_profit >= 0 ? 'border-green-200' : 'border-red-200'
    },
    {
      title: 'Recommendation Value',
      value: formatCurrency(summary.recommendation_value),
      icon: '📈',
      color: summary.recommendation_value >= 0 ? 'text-green-600' : 'text-red-600',
      bgColor: summary.recommendation_value >= 0 ? 'bg-green-50' : 'bg-red-50',
      borderColor: summary.recommendation_value >= 0 ? 'border-green-200' : 'border-red-200'
    }
  ];

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      {cards.map((card, index) => (
        <div key={index} className={`${card.bgColor} ${card.borderColor} border rounded-lg p-6 hover:shadow-md transition-shadow`}>
          <div className="flex items-center">
            <div className="text-2xl mr-3">{card.icon}</div>
            <div>
              <p className="text-sm font-medium text-gray-600 mb-1">{card.title}</p>
              <p className={`text-2xl font-bold ${card.color}`}>{card.value}</p>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};

export default RecommendationSummaryCards;
