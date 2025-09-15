export interface Trade {
  id: number;
  trade_id: string;
  symbol: string;
  timeframe: string;
  direction: 'BUY' | 'SELL';
  entry_price: number;
  exit_price: number | null;
  stop_loss: number;
  take_profit: number;
  lot_size: number;
  profit_loss: number | null;
  profit_loss_pips: number | null;
  entry_time: string;
  exit_time: string | null;
  duration_seconds: number | null;
  status: 'OPEN' | 'CLOSED' | 'CANCELLED';
  strategy_name: string;
  strategy_version: string;
  account_id: string;
  created_at: string;
  updated_at: string;
}

export interface MLPrediction {
  id: number;
  trade_id: string;
  model_name: string;
  model_type: 'BUY' | 'SELL' | 'COMBINED';
  prediction_probability: number;
  confidence_score: number;
  features_json: any;
  prediction_time: string;
}

export interface MarketConditions {
  id: number;
  trade_id: string;
  symbol: string;
  timeframe: string;
  rsi: number | null;
  stoch_main: number | null;
  stoch_signal: number | null;
  macd_main: number | null;
  macd_signal: number | null;
  bb_upper: number | null;
  bb_lower: number | null;
  adx: number | null;
  cci: number | null;
  momentum: number | null;
  atr: number | null;
  volume_ratio: number | null;
  price_change: number | null;
  volatility: number | null;
  spread: number | null;
  session_hour: number | null;
  day_of_week: number | null;
  month: number | null;
  breakout_level: number | null;
  retest_level: number | null;
  swing_point: number | null;
  breakout_direction: string | null;
  recorded_at: string;
}

export interface Summary {
  total_trades: number | string;
  winning_trades: number | string;
  losing_trades: number | string;
  win_rate: number | string;
  avg_profit_loss: number | string;
  total_profit_loss: number | string;
}

export interface MLTrainingData {
  trade_id: string;
  symbol: string;
  timeframe: string;
  entry_price: number;
  exit_price: number;
  stop_loss: number;
  take_profit: number;
  lot_size: number;
  profit_loss: number;
  profit_loss_pips: number;
  trade_time: number;
  close_time: number;
  status: string;
  strategy_name: string;
  strategy_version: string;
  features: any;
  prediction_probability: number;
  confidence_score: number;
}

export interface ChartData {
  labels: string[];
  datasets: {
    label: string;
    data: number[];
    borderColor?: string;
    backgroundColor?: string;
    fill?: boolean;
  }[];
}

export interface MLPerformance {
  total_predictions: number;
  correct_predictions: number;
  incorrect_predictions: number;
  accuracy: number;
  avg_prediction_probability: number;
  avg_confidence_score: number;
  avg_profit_loss: number;
  total_profit_loss: number;
  avg_win: number;
  avg_loss: number;
  model_performance: ModelPerformance[];
  confidence_accuracy: ConfidenceAccuracy[];
}

export interface ModelPerformance {
  ml_model_key: string;
  ml_model_type: string;
  total_trades: number;
  winning_trades: number;
  avg_prediction: number;
  avg_confidence: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

export interface ConfidenceAccuracy {
  confidence_bucket: number;
  total_trades: number;
  winning_trades: number;
  avg_profit_loss: number;
}

export interface MLPredictions {
  prediction_by_type: PredictionByType[];
  prediction_by_symbol: PredictionBySymbol[];
  prediction_by_timeframe: PredictionByTimeframe[];
  confidence_buckets: ConfidenceBucket[];
  recent_performance: RecentPerformance[];
}

export interface PredictionByType {
  ml_model_type: string;
  total_predictions: number;
  correct_predictions: number;
  avg_prediction_probability: number;
  avg_confidence_score: number;
  avg_profit_loss: number;
  total_profit_loss: number;
  avg_win: number;
  avg_loss: number;
}

export interface PredictionBySymbol {
  symbol: string;
  total_predictions: number;
  correct_predictions: number;
  avg_prediction_probability: number;
  avg_confidence_score: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

export interface PredictionByTimeframe {
  timeframe: string;
  total_predictions: number;
  correct_predictions: number;
  avg_prediction_probability: number;
  avg_confidence_score: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

export interface ConfidenceBucket {
  confidence_range: string;
  total_predictions: number;
  correct_predictions: number;
  avg_confidence: number;
  avg_prediction: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

export interface RecentPerformance {
  trade_date: string;
  total_predictions: number;
  correct_predictions: number;
  avg_confidence: number;
  avg_profit_loss: number;
  total_profit_loss: number;
}

export interface ModelRetrainingStatus {
  model_key: string;
  symbol: string;
  timeframe: string;
  direction: string;
  last_retrained: string | null;
  training_date: string | null;
  health_score: number | null;
  cv_accuracy: number | null;
  confidence_correlation: number | null;
  training_samples: number | null;
  model_type: string | null;
  retrained_by: string | null;
  model_version: number | null;
  // New fields for UI badges
  used_lenient_threshold?: boolean;
  model_quality?: 'standard' | 'low_accuracy';
}

export interface ModelRetrainingStatusResponse {
  models: ModelRetrainingStatus[];
  summary: {
    total_retrained_models: number;
    retrained_models: number;
    avg_health_score: number;
  };
  timestamp: string;
}
