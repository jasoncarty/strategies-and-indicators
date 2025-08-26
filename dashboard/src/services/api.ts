import axios from 'axios';
import { Trade, MLPrediction, MarketConditions, Summary, MLTrainingData, MLPerformance, MLPredictions, ModelRetrainingStatusResponse } from '../types/analytics';

console.log(process.env);
const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5001';

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
});

// Health check
export const checkHealth = async () => {
  const response = await api.get('/health');
  return response.data;
};

// Analytics endpoints
export const getSummary = async (): Promise<Summary> => {
  const response = await api.get('/analytics/summary');
  return response.data;
};

export const getTrades = async (params?: {
  symbol?: string;
  timeframe?: string;
  status?: string;
  limit?: number;
  offset?: number;
}): Promise<Trade[]> => {
  const response = await api.get('/analytics/dashboard/trades', { params });
  return response.data;
};

export const getMLTrainingData = async (params?: {
  symbol?: string;
  timeframe?: string;
  limit?: number;
}): Promise<MLTrainingData[]> => {
  const response = await api.get('/analytics/ml_training_data', { params });
  return response.data;
};

export const getMLPerformance = async (): Promise<MLPerformance> => {
  const response = await api.get('/analytics/ml_performance');
  return response.data;
};

export const getMLPredictions = async (): Promise<MLPredictions> => {
  const response = await api.get('/analytics/ml_predictions');
  return response.data;
};

export const getModelPerformance = async (modelKey: string, params?: {
  start_date?: string;
  end_date?: string;
}): Promise<any> => {
  const response = await api.get(`/analytics/model/${encodeURIComponent(modelKey)}/performance`, { params });
  return response.data;
};

export const getModelDiagnostics = async (modelKey: string, params?: {
  start_date?: string;
  end_date?: string;
}): Promise<any> => {
  const response = await api.get(`/analytics/model/${encodeURIComponent(modelKey)}/diagnostics`, { params });
  return response.data;
};

export const getModelHealthOverview = async (): Promise<any> => {
  const response = await api.get('/analytics/model_health');
  return response.data;
};

export const getModelCalibration = async (modelKey: string, params?: {
  start_date?: string;
  end_date?: string;
}): Promise<any> => {
  const response = await api.get(`/analytics/model/${encodeURIComponent(modelKey)}/calibration`, { params });
  return response.data;
};

export const getModelAlerts = async (): Promise<any> => {
  const response = await api.get('/analytics/model_alerts');
  return response.data;
};

export const getModelRetrainingStatus = async (): Promise<ModelRetrainingStatusResponse> => {
  const response = await api.get('/analytics/model_retraining_status');
  return response.data;
};

// ML Trade Log endpoints
export const getMLTradeLogs = async (params?: {
  symbol?: string;
  timeframe?: string;
  limit?: number;
}): Promise<any[]> => {
  const response = await api.get('/ml_trade_log', { params });
  return response.data;
};

export const getMLTradeCloses = async (params?: {
  symbol?: string;
  timeframe?: string;
  limit?: number;
}): Promise<any[]> => {
  const response = await api.get('/ml_trade_close', { params });
  return response.data;
};

// Helper function to format currency
export const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
};

// Helper function to format percentage
export const formatPercentage = (value: number | string): string => {
  const numValue = typeof value === 'string' ? parseFloat(value) : value;
  return `${numValue.toFixed(2)}%`;
};

// Helper function to format date
export const formatDate = (dateString: string): string => {
  const date = new Date(dateString);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');

  return `${year}-${month}-${day} ${hour}:${minute}`;
};

// Helper function to get color based on profit/loss
export const getProfitLossColor = (value: number): string => {
  if (value > 0) return 'text-success-600';
  if (value < 0) return 'text-danger-600';
  return 'text-gray-600';
};

// Helper function to get background color based on profit/loss
export const getProfitLossBgColor = (value: number): string => {
  if (value > 0) return 'bg-success-50 border-success-200';
  if (value < 0) return 'bg-danger-50 border-danger-200';
  return 'bg-gray-50 border-gray-200';
};
