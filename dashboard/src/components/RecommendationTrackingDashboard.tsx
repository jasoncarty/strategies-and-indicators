import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  getRecommendationSummary,
  getRecommendationPerformance,
  getRecommendationInsights,
  getRecommendationTimeline
} from '../services/api';
import { RecommendationFilters } from '../types/analytics';
import RecommendationSummaryCards from './RecommendationSummaryCards';
import RecommendationCharts from './RecommendationCharts';
import RecommendationInsights from './RecommendationInsights';

const RecommendationTrackingDashboard: React.FC = () => {
  const [filters, setFilters] = useState<RecommendationFilters>({
    days: 30
  });

  // Fetch recommendation data
  const { data: summary, isLoading: summaryLoading, error: summaryError } = useQuery({
    queryKey: ['recommendationSummary', filters],
    queryFn: () => getRecommendationSummary(filters),
  });

  const { data: performance, isLoading: performanceLoading, error: performanceError } = useQuery({
    queryKey: ['recommendationPerformance', filters],
    queryFn: () => getRecommendationPerformance(filters),
  });

  const { data: insights, isLoading: insightsLoading, error: insightsError } = useQuery({
    queryKey: ['recommendationInsights', filters],
    queryFn: () => getRecommendationInsights(filters),
  });

  const { data: timeline, isLoading: timelineLoading, error: timelineError } = useQuery({
    queryKey: ['recommendationTimeline', filters],
    queryFn: () => getRecommendationTimeline(filters),
  });

  const handleFilterChange = (newFilters: Partial<RecommendationFilters>) => {
    setFilters(prev => ({ ...prev, ...newFilters }));
  };

  if (summaryError || performanceError || insightsError || timelineError) {
    return (
      <div className="min-h-screen bg-gray-100 p-8">
        <div className="max-w-7xl mx-auto">
          <div className="bg-red-50 border border-red-200 rounded-lg p-6">
            <h2 className="text-lg font-semibold text-red-800 mb-2">Error Loading Recommendation Data</h2>
            <p className="text-red-700">
              {summaryError ? `Summary Error: ${summaryError.message}` : ''}
              {performanceError ? `Performance Error: ${performanceError.message}` : ''}
              {insightsError ? `Insights Error: ${insightsError.message}` : ''}
              {timelineError ? `Timeline Error: ${timelineError.message}` : ''}
            </p>
            <p className="text-red-600 mt-2">
              Please check that the analytics server is running and the recommendation tracking endpoints are available.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900">Recommendation Tracking</h1>
              <p className="mt-1 text-sm text-gray-500">
                Track and analyze active trade recommendations for ML model improvement
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

      {/* Filters */}
      <div className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex flex-wrap items-center gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Strategy</label>
              <select
                value={filters.strategy || ''}
                onChange={(e) => handleFilterChange({ strategy: e.target.value || undefined })}
                className="border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">All Strategies</option>
                <option value="active_trade_analysis">Active Trade Analysis</option>
                <option value="BreakoutStrategy">Breakout Strategy</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Symbol</label>
              <select
                value={filters.symbol || ''}
                onChange={(e) => handleFilterChange({ symbol: e.target.value || undefined })}
                className="border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">All Symbols</option>
                <option value="EURUSD">EURUSD</option>
                <option value="EURUSD+">EURUSD+</option>
                <option value="XAUUSD">XAUUSD</option>
                <option value="XAUUSD+">XAUUSD+</option>
                <option value="BTCUSD">BTCUSD</option>
                <option value="ETHUSD">ETHUSD</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Timeframe</label>
              <select
                value={filters.timeframe || ''}
                onChange={(e) => handleFilterChange({ timeframe: e.target.value || undefined })}
                className="border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="">All Timeframes</option>
                <option value="M5">M5</option>
                <option value="M15">M15</option>
                <option value="M30">M30</option>
                <option value="H1">H1</option>
                <option value="H4">H4</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Days</label>
              <select
                value={filters.days || 30}
                onChange={(e) => handleFilterChange({ days: parseInt(e.target.value) })}
                className="border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value={7}>Last 7 days</option>
                <option value={30}>Last 30 days</option>
                <option value={90}>Last 90 days</option>
                <option value={180}>Last 6 months</option>
                <option value={365}>Last year</option>
              </select>
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Summary Cards */}
        <RecommendationSummaryCards
          summary={summary || {
            total_recommendations: 0,
            overall_accuracy: 0,
            total_profit: 0,
            avg_confidence: 0,
            recommendation_value: 0,
            correct_recommendations: 0,
            incorrect_recommendations: 0
          }}
          isLoading={summaryLoading}
        />

        {/* Charts */}
        <RecommendationCharts
          charts={performance?.charts || {
            accuracy_by_model: [],
            confidence_distribution: [],
            profit_trend: [],
            recommendation_breakdown: []
          }}
          isLoading={performanceLoading}
        />

        {/* Insights */}
        <RecommendationInsights
          insights={insights || {
            insights: [],
            recommendations: [],
            summary: {
              total_insights: 0,
              total_recommendations: 0,
              critical_issues: 0,
              overall_accuracy: 0
            }
          }}
          isLoading={insightsLoading}
        />
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 mt-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="text-center text-sm text-gray-500">
            <p>Recommendation Tracking Dashboard • Built with React & Chart.js</p>
            <p className="mt-1">Data refreshes automatically every 30 seconds</p>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default RecommendationTrackingDashboard;
