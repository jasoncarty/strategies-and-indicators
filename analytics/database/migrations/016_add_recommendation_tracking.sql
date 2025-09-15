-- Migration: 016_add_recommendation_tracking.sql
-- Description: Add tables for tracking active trade recommendations and their outcomes
-- Date: 2025-01-27

-- Table for tracking active trade recommendations
CREATE TABLE IF NOT EXISTS active_trade_recommendations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    recommendation_id VARCHAR(50) UNIQUE NOT NULL,
    trade_id BIGINT NOT NULL,
    strategy VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    trade_direction ENUM('BUY', 'SELL') NOT NULL,

    -- Trade state at recommendation time
    entry_price DECIMAL(20, 8) NOT NULL,
    current_price DECIMAL(20, 8) NOT NULL,
    trade_duration_minutes INT NOT NULL,
    current_profit_pips DECIMAL(10, 2) NOT NULL,
    current_profit_money DECIMAL(20, 8) NOT NULL,
    account_balance DECIMAL(20, 8) NOT NULL,
    profit_percentage DECIMAL(8, 4) NOT NULL,

    -- ML prediction data
    ml_prediction_available BOOLEAN NOT NULL DEFAULT FALSE,
    ml_confidence DECIMAL(5, 4) NOT NULL DEFAULT 0.0,
    ml_probability DECIMAL(5, 4) NOT NULL DEFAULT 0.0,
    ml_model_key VARCHAR(100) NOT NULL DEFAULT '',
    ml_model_type VARCHAR(50) NOT NULL DEFAULT '',

    -- Trade health analysis
    base_confidence DECIMAL(5, 4) NOT NULL DEFAULT 0.0,
    final_confidence DECIMAL(5, 4) NOT NULL DEFAULT 0.0,
    analysis_method ENUM('ml_enhanced', 'trade_health_only') NOT NULL DEFAULT 'trade_health_only',

    -- Recommendation decision
    should_continue BOOLEAN NOT NULL,
    recommendation ENUM('continue', 'close') NOT NULL,
    reason VARCHAR(100) NOT NULL,
    confidence_threshold DECIMAL(5, 4) NOT NULL DEFAULT 0.5,

    -- Market features at recommendation time
    features_json JSON NOT NULL,

    -- Timestamps
    recommendation_time TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Indexes for performance
    INDEX idx_trade_id (trade_id),
    INDEX idx_recommendation_id (recommendation_id),
    INDEX idx_strategy (strategy),
    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_recommendation_time (recommendation_time),
    INDEX idx_should_continue (should_continue),
    INDEX idx_ml_model (ml_model_key),
    INDEX idx_analysis_method (analysis_method)
);

-- Table for tracking recommendation outcomes
CREATE TABLE IF NOT EXISTS recommendation_outcomes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    recommendation_id VARCHAR(50) NOT NULL,
    trade_id BIGINT NOT NULL,

    -- Outcome tracking
    outcome_status ENUM('pending', 'completed', 'cancelled', 'expired') NOT NULL DEFAULT 'pending',
    final_decision ENUM('continued', 'closed') NOT NULL,
    decision_timestamp TIMESTAMP NULL,

    -- Trade final results
    final_profit_loss DECIMAL(20, 8) NULL,
    final_profit_pips DECIMAL(10, 2) NULL,
    final_profit_percentage DECIMAL(8, 4) NULL,
    close_price DECIMAL(20, 8) NULL,
    close_time TIMESTAMP NULL,
    exit_reason VARCHAR(100) NULL,

    -- Performance metrics
    recommendation_accuracy BOOLEAN NULL, -- Was the recommendation correct?
    profit_if_followed DECIMAL(20, 8) NULL, -- Profit if recommendation was followed
    profit_if_opposite DECIMAL(20, 8) NULL, -- Profit if opposite action was taken
    recommendation_value DECIMAL(20, 8) NULL, -- Value added by following recommendation

    -- Confidence analysis
    confidence_accuracy BOOLEAN NULL, -- Was confidence level accurate?
    confidence_bucket ENUM('low', 'medium', 'high') NULL, -- Confidence level bucket
    prediction_accuracy BOOLEAN NULL, -- Was ML prediction accurate?

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- Foreign key constraint
    FOREIGN KEY (recommendation_id) REFERENCES active_trade_recommendations(recommendation_id) ON DELETE CASCADE,

    -- Indexes for performance
    INDEX idx_recommendation_id (recommendation_id),
    INDEX idx_trade_id (trade_id),
    INDEX idx_outcome_status (outcome_status),
    INDEX idx_final_decision (final_decision),
    INDEX idx_recommendation_accuracy (recommendation_accuracy),
    INDEX idx_confidence_accuracy (confidence_accuracy),
    INDEX idx_confidence_bucket (confidence_bucket)
);

-- Table for recommendation performance analytics
CREATE TABLE IF NOT EXISTS recommendation_performance (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    analysis_date DATE NOT NULL,
    strategy VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    timeframe VARCHAR(10) NOT NULL,
    ml_model_key VARCHAR(100) NOT NULL,
    analysis_method ENUM('ml_enhanced', 'trade_health_only') NOT NULL,

    -- Recommendation counts
    total_recommendations INT NOT NULL DEFAULT 0,
    continue_recommendations INT NOT NULL DEFAULT 0,
    close_recommendations INT NOT NULL DEFAULT 0,

    -- Accuracy metrics
    correct_recommendations INT NOT NULL DEFAULT 0,
    incorrect_recommendations INT NOT NULL DEFAULT 0,
    accuracy_percentage DECIMAL(5, 2) NOT NULL DEFAULT 0.0,

    -- Confidence analysis
    high_confidence_recommendations INT NOT NULL DEFAULT 0,
    medium_confidence_recommendations INT NOT NULL DEFAULT 0,
    low_confidence_recommendations INT NOT NULL DEFAULT 0,

    high_confidence_accuracy DECIMAL(5, 2) NOT NULL DEFAULT 0.0,
    medium_confidence_accuracy DECIMAL(5, 2) NOT NULL DEFAULT 0.0,
    low_confidence_accuracy DECIMAL(5, 2) NOT NULL DEFAULT 0.0,

    -- Profit analysis
    total_profit_if_followed DECIMAL(20, 8) NOT NULL DEFAULT 0.0,
    total_profit_if_opposite DECIMAL(20, 8) NOT NULL DEFAULT 0.0,
    recommendation_value DECIMAL(20, 8) NOT NULL DEFAULT 0.0,
    avg_profit_per_recommendation DECIMAL(20, 8) NOT NULL DEFAULT 0.0,

    -- ML model performance
    ml_prediction_accuracy DECIMAL(5, 2) NOT NULL DEFAULT 0.0,
    confidence_correlation DECIMAL(5, 4) NOT NULL DEFAULT 0.0,

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- Unique constraint to prevent duplicates
    UNIQUE KEY unique_analysis (analysis_date, strategy, symbol, timeframe, ml_model_key, analysis_method),

    -- Indexes for performance
    INDEX idx_analysis_date (analysis_date),
    INDEX idx_strategy (strategy),
    INDEX idx_symbol_timeframe (symbol, timeframe),
    INDEX idx_ml_model (ml_model_key),
    INDEX idx_analysis_method (analysis_method)
);

-- Add comments for documentation
ALTER TABLE active_trade_recommendations COMMENT = 'Tracks active trade recommendations with ML predictions and trade health analysis';
ALTER TABLE recommendation_outcomes COMMENT = 'Tracks the outcomes of active trade recommendations for performance analysis';
ALTER TABLE recommendation_performance COMMENT = 'Aggregated performance metrics for recommendation analysis and ML model improvement';
