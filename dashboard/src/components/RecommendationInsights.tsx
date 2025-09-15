import React from 'react';
import { RecommendationInsights } from '../types/analytics';

interface RecommendationInsightsProps {
  insights: RecommendationInsights;
  isLoading: boolean;
}

const RecommendationInsightsComponent: React.FC<RecommendationInsightsProps> = ({ insights, isLoading }) => {
  if (isLoading) {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <div className="bg-white rounded-lg shadow p-6 animate-pulse">
          <div className="h-6 bg-gray-200 rounded w-1/3 mb-4"></div>
          <div className="space-y-3">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="h-16 bg-gray-200 rounded"></div>
            ))}
          </div>
        </div>
        <div className="bg-white rounded-lg shadow p-6 animate-pulse">
          <div className="h-6 bg-gray-200 rounded w-1/3 mb-4"></div>
          <div className="space-y-3">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="h-16 bg-gray-200 rounded"></div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  const getInsightIcon = (type: string) => {
    switch (type) {
      case 'positive': return '✅';
      case 'warning': return '⚠️';
      case 'critical': return '🚨';
      case 'info': return 'ℹ️';
      default: return '📊';
    }
  };

  const getInsightColor = (type: string) => {
    switch (type) {
      case 'positive': return 'text-green-800 bg-green-50 border-green-200';
      case 'warning': return 'text-yellow-800 bg-yellow-50 border-yellow-200';
      case 'critical': return 'text-red-800 bg-red-50 border-red-200';
      case 'info': return 'text-blue-800 bg-blue-50 border-blue-200';
      default: return 'text-gray-800 bg-gray-50 border-gray-200';
    }
  };

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'high': return 'text-red-600 bg-red-100';
      case 'medium': return 'text-yellow-600 bg-yellow-100';
      case 'low': return 'text-green-600 bg-green-100';
      default: return 'text-gray-600 bg-gray-100';
    }
  };

  const getActionIcon = (type: string) => {
    switch (type) {
      case 'retrain': return '🔄';
      case 'threshold': return '🎯';
      case 'calibration': return '⚖️';
      case 'risk_management': return '🛡️';
      default: return '📋';
    }
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
      {/* Insights Panel */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900">Performance Insights</h3>
          <span className="text-sm text-gray-500">
            {insights.summary.total_insights} insights
          </span>
        </div>

        {insights.insights.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <div className="text-4xl mb-2">📊</div>
            <p>No insights available</p>
          </div>
        ) : (
          <div className="space-y-3">
            {insights.insights.map((insight, index) => (
              <div
                key={index}
                className={`p-4 rounded-lg border ${getInsightColor(insight.type)}`}
              >
                <div className="flex items-start">
                  <div className="text-xl mr-3">{getInsightIcon(insight.type)}</div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between mb-1">
                      <h4 className="font-medium">{insight.title}</h4>
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${getPriorityColor(insight.priority)}`}>
                        {insight.priority}
                      </span>
                    </div>
                    <p className="text-sm opacity-90">{insight.description}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Recommendations Panel */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900">Action Items</h3>
          <span className="text-sm text-gray-500">
            {insights.summary.total_recommendations} recommendations
          </span>
        </div>

        {insights.recommendations.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <div className="text-4xl mb-2">🎯</div>
            <p>No recommendations available</p>
          </div>
        ) : (
          <div className="space-y-3">
            {insights.recommendations.map((recommendation, index) => (
              <div
                key={index}
                className="p-4 rounded-lg border border-gray-200 bg-gray-50"
              >
                <div className="flex items-start">
                  <div className="text-xl mr-3">{getActionIcon(recommendation.type)}</div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between mb-1">
                      <h4 className="font-medium text-gray-900">
                        {recommendation.type.charAt(0).toUpperCase() + recommendation.type.slice(1).replace('_', ' ')}
                      </h4>
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${getPriorityColor(recommendation.priority)}`}>
                        {recommendation.priority}
                      </span>
                    </div>
                    <p className="text-sm text-gray-600 mb-1">
                      <strong>Model:</strong> {recommendation.model}
                    </p>
                    <p className="text-sm text-gray-700">{recommendation.action}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Summary Stats */}
      <div className="lg:col-span-2 bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Summary</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="text-center p-4 bg-blue-50 rounded-lg">
            <div className="text-2xl font-bold text-blue-600">{insights.summary.overall_accuracy}%</div>
            <div className="text-sm text-blue-600">Overall Accuracy</div>
          </div>
          <div className="text-center p-4 bg-yellow-50 rounded-lg">
            <div className="text-2xl font-bold text-yellow-600">{insights.summary.critical_issues}</div>
            <div className="text-sm text-yellow-600">Critical Issues</div>
          </div>
          <div className="text-center p-4 bg-green-50 rounded-lg">
            <div className="text-2xl font-bold text-green-600">{insights.summary.total_recommendations}</div>
            <div className="text-sm text-green-600">Action Items</div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RecommendationInsightsComponent;
