//+------------------------------------------------------------------+
//| MLHttpInterface.mqh                                               |
//| HTTP-based ML interface for communicating with Flask API server  |
//| Replaces file-based communication with HTTP requests             |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024"
#property link      ""
#property version   "2.00"
#property strict

// Include JSON library for robust JSON parsing
#include "JAson.mqh"

//+------------------------------------------------------------------+
//| ML Configuration Structure                                        |
//+------------------------------------------------------------------+
struct MLConfig {
    string strategy_name;           // Name of the strategy (e.g., "BreakoutStrategy")
    string symbol;                  // Trading symbol (e.g., "EURUSD")
    string timeframe;               // Timeframe (e.g., "H1", "M15")
    bool enabled;                   // Whether ML is enabled
    double min_confidence;          // Minimum confidence threshold
    double max_confidence;          // Maximum confidence threshold
    bool use_directional_models;    // Use buy/sell specific models
    bool use_combined_models;       // Use combined models
    int prediction_timeout;         // Timeout for ML predictions (ms)
    string api_url;                 // URL of ML API server
};

//+------------------------------------------------------------------+
//| ML Prediction Structure                                           |
//+------------------------------------------------------------------+
struct MLPrediction {
    double confidence;              // Prediction confidence (0.0 - 1.0)
    double probability;             // Success probability (0.0 - 1.0)
    string direction;               // Predicted direction ("buy", "sell", "hold")
    string model_type;              // Model used ("buy", "sell", "combined")
    string model_key;               // Model key/identifier
    bool is_valid;                  // Whether prediction is valid
    string error_message;           // Error message if prediction failed
    datetime timestamp;             // When prediction was made

    // Enhanced fields for trade decision endpoint
    bool should_trade;              // Whether we should execute a trade
    double confidence_threshold;    // Dynamic confidence threshold based on model health

    // Copy constructor to avoid deprecated assignment warnings
    MLPrediction(const MLPrediction& other) {
        confidence = other.confidence;
        probability = other.probability;
        direction = other.direction;
        model_type = other.model_type;
        model_key = other.model_key;
        is_valid = other.is_valid;
        error_message = other.error_message;
        timestamp = other.timestamp;
        should_trade = other.should_trade;
        confidence_threshold = other.confidence_threshold;
    }

    // Default constructor
    MLPrediction() {
        confidence = 0.0;
        probability = 0.0;
        direction = "";
        model_type = "";
        model_key = "";
        is_valid = false;
        error_message = "";
        timestamp = 0;
        should_trade = false;
        confidence_threshold = 0.3;
    }
};

//+------------------------------------------------------------------+
//| ML Feature Structure                                              |
//+------------------------------------------------------------------+
struct MLFeatures {
    // Technical indicators
    double rsi;
    double stoch_main;
    double stoch_signal;
    double macd_main;
    double macd_signal;
    double bb_upper;
    double bb_lower;
    double williams_r;
    double cci;
    double momentum;
    double force_index;

    // Market conditions
    double volume_ratio;
    double price_change;
    double volatility;
    double spread;

    // Time-based features
    int session_hour;
    bool is_news_time;
    int day_of_week;
    int month;

    // Engineered features (9 features)
    int rsi_regime;           // 0=oversold, 1=neutral, 2=overbought
    int stoch_regime;         // 0=oversold, 1=neutral, 2=overbought
    int volatility_regime;    // 0=low, 1=medium, 2=high
    int hour;                 // Current hour (0-23)
    int session;              // 0=other, 1=london, 2=ny, 3=asian
    bool is_london_session;   // True if London session (8-16)
    bool is_ny_session;       // True if NY session (13-22)
    bool is_asian_session;    // True if Asian session (1-10)
    bool is_session_overlap;  // True if London/NY overlap

    // Trade calculation features (required for enhanced endpoint)
    double current_price;            // Current market price
    double atr;                     // Average True Range for stop loss calculation
    double account_balance;         // Account balance for lot size calculation
    double risk_per_pip;            // Risk per pip for lot size calculation

    // Additional features can be added as needed
};

//+------------------------------------------------------------------+
//| Unified Trade Data Structure                                     |
//+------------------------------------------------------------------+
struct UnifiedTradeData {
    ulong ticket;                    // MT5 position ticket (0 if not yet opened)
    string direction;                 // BUY/SELL
    string timeframe;                 // Timeframe this trade was opened on
    double entry_price;              // Entry price
    double stop_loss;                // Stop loss
    double take_profit;              // Take profit
    double lot_size;                 // Lot size
    MLPrediction prediction;         // ML prediction data
    MLFeatures features;             // Market features
    bool is_logged;                  // Whether ML data was logged to database
    bool is_open;                    // Whether position is currently open
    datetime created_time;           // When trade was created
    datetime opened_time;            // When position was opened
    datetime last_monitoring_check;  // When this trade was last monitored
    bool monitoring_enabled;         // Whether monitoring is enabled for this trade
};

//+------------------------------------------------------------------+
//| HTTP-based Machine Learning Interface Class                       |
//+------------------------------------------------------------------+
class MLHttpInterface {
public:
    MLConfig config;  // Make config public for easy access
private:
    MLPrediction last_prediction;

    // Unified trade tracking (replaces both pending trades and position tracking)
    // Array size: 1000 slots (large enough for any reasonable EA capacity setting)
    UnifiedTradeData unified_trades[1000];  // Large default size to accommodate any EA capacity setting
    int unified_trade_count;
    bool api_connected;
    datetime last_connection_check;
    int request_timeout;

    // Cache for performance
    MLPrediction prediction_cache[10];
    int cache_index;

public:
    // Constructor
    MLHttpInterface() {
        config.strategy_name = "BreakoutStrategy";
        config.symbol = "";
        config.timeframe = "";
        config.enabled = true;
        config.min_confidence = 0.30;
        config.max_confidence = 0.85;
        config.use_directional_models = true;
        config.use_combined_models = true;
        config.prediction_timeout = 5000;
        config.api_url = "http://localhost:5003";  // Updated to port 5003
        api_connected = false;
        last_connection_check = 0;
        request_timeout = 5000;
        cache_index = 0;
        unified_trade_count = 0;  // Initialize unified trade counter
    }

    // Initialize the interface
    bool Initialize(string strategy_name = "BreakoutStrategy") {
        config.strategy_name = strategy_name;
        config.symbol = _Symbol;
        config.timeframe = GetCurrentTimeframeString();

        Print("🔧 Initializing ML HTTP Interface");
        Print("   Strategy: ", config.strategy_name);
        Print("   Symbol: ", config.symbol);
        Print("   Timeframe: ", config.timeframe);
        Print("   API URL: ", config.api_url);

        // Test connection to API server
        if(!TestConnection()) {
            Print("❌ Failed to connect to ML API server");
            return false;
        }

        Print("✅ ML HTTP Interface initialized successfully");
        return true;
    }

    // Test connection to API server
    bool TestConnection() {
        if(TimeCurrent() - last_connection_check < 60) { // Cache for 1 minute
            return api_connected;
        }

        string url = config.api_url + "/health";
        string headers = "Content-Type: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        int res = WebRequest("GET", url, headers, 0, post_data, result, result_headers);

        if(res == 200) {
            string response = CharArrayToString(result);
            if(StringFind(response, "healthy") >= 0) {
                api_connected = true;
                last_connection_check = TimeCurrent();
                Print("✅ ML API server connection successful");
                return true;
            }
        }

        api_connected = false;
        last_connection_check = TimeCurrent();
        Print("❌ ML API server connection failed. Response: ", res);
        return false;
    }

    // Get ML prediction via HTTP API
    MLPrediction GetPrediction(MLFeatures &features, string direction = "") {
        MLPrediction prediction;
        prediction.is_valid = false;
        prediction.timestamp = TimeCurrent();

        Print("🔮 ML Prediction Request - Direction: ", direction, ", Symbol: ", config.symbol, ", Timeframe: ", config.timeframe);

        if(!config.enabled) {
            prediction.error_message = "ML is disabled";
            Print("❌ ML is disabled");
            return prediction;
        }

        if(!TestConnection()) {
            prediction.error_message = "API server not connected";
            Print("❌ API server not connected");
            return prediction;
        }

        // Prepare JSON request
        string json_request = PrepareJsonRequest(features, direction);

        // Validate JSON request
        if(StringLen(json_request) == 0) {
            prediction.error_message = "Failed to prepare JSON request";
            Print("❌ Failed to prepare JSON request");
            return prediction;
        }

        Print("📤 JSON Request length: ", StringLen(json_request), " characters");
        Print("📤 JSON Request preview: ", StringSubstr(json_request, 0, 200), "...");
        Print("📤 JSON Request end: ", StringSubstr(json_request, StringLen(json_request) - 50, 50));

        // Send HTTP request
        string url = config.api_url + "/predict";
        string headers = "Content-Type: application/json\r\nAccept: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        // Convert JSON to UTF-8 uchar array (fix for WebRequest buffer issue)
        StringToCharArray(json_request, post_data, 0, WHOLE_ARRAY, CP_UTF8);
        // Remove the null terminator that StringToCharArray adds
        ArrayRemove(post_data, ArraySize(post_data)-1);
        Print("🌐 Sending HTTP request to: ", url);
        Print("   Headers: ", headers);
        Print("   Data length: ", ArraySize(post_data), " bytes");
        Print("   JSON length: ", StringLen(json_request), " characters");
        Print("   JSON content: ", json_request);

        int res = WebRequest("POST", url, headers, request_timeout, post_data, result, result_headers);

        Print("📥 HTTP Response Code: ", res);
        Print("📥 Response data size: ", ArraySize(result), " bytes");
        Print("📥 Request data size sent: ", ArraySize(post_data), " bytes");

        if(res == 200) {
            string response = CharArrayToString(result);
            Print("📥 HTTP Response: ", response);
            prediction = ParseJsonResponse(response);

            // Cache the prediction
            prediction_cache[cache_index] = prediction;
            cache_index = (cache_index + 1) % 10;

            last_prediction = prediction;

            if(prediction.is_valid) {
                Print("✅ ML Prediction: ", prediction.direction, " (",
                      DoubleToString(prediction.probability, 3), " confidence: ",
                      DoubleToString(prediction.confidence, 3), ")");
            } else {
                Print("❌ ML Prediction failed: ", prediction.error_message);
            }
        } else {
            string response = CharArrayToString(result);
            Print("❌ HTTP Response (Error): ", response);

            // Provide more specific error messages based on response code
            switch(res) {
                case -1:
                    prediction.error_message = "WebRequest failed - check internet connection and URL";
                    break;
                case 400:
                    prediction.error_message = "Bad request - check JSON format and data";
                    break;
                case 404:
                    prediction.error_message = "API endpoint not found - check URL";
                    break;
                case 500:
                    prediction.error_message = "Server error - check ML service logs";
                    break;
                case 502:
                case 503:
                case 504:
                    prediction.error_message = "Service unavailable - ML server may be down";
                    break;
                default:
                    prediction.error_message = "HTTP error " + IntegerToString(res) + " - " + response;
                    break;
            }
        }

        return prediction;
    }

    // Get enhanced trade decision via HTTP API (new /trade_decision endpoint)
    MLPrediction GetEnhancedTradeDecision(MLFeatures &features, string direction = "") {
        MLPrediction prediction;
        prediction.is_valid = false;
        prediction.timestamp = TimeCurrent();

        Print("🚀 Enhanced Trade Decision Request - Direction: ", direction, ", Symbol: ", config.symbol, ", Timeframe: ", config.timeframe);

        if(!config.enabled) {
            prediction.error_message = "ML is disabled";
            Print("❌ ML is disabled");
            return prediction;
        }

        if(!TestConnection()) {
            prediction.error_message = "API server not connected";
            Print("❌ API server not connected");
            return prediction;
        }

        // Prepare JSON request
        string json_request = PrepareJsonRequest(features, direction);

        // Validate JSON request
        if(StringLen(json_request) == 0) {
            prediction.error_message = "Failed to prepare JSON request";
            Print("❌ Failed to prepare JSON request");
            return prediction;
        }

        Print("📤 Enhanced JSON Request length: ", StringLen(json_request), " characters");

        // Send HTTP request to enhanced endpoint
        string url = config.api_url + "/trade_decision";
        string headers = "Content-Type: application/json\r\nAccept: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        // Convert JSON to UTF-8 uchar array
        StringToCharArray(json_request, post_data, 0, WHOLE_ARRAY, CP_UTF8);
        ArrayRemove(post_data, ArraySize(post_data)-1);

        Print("🌐 Sending enhanced request to: ", url);
        Print("   Data length: ", ArraySize(post_data), " bytes");

        int res = WebRequest("POST", url, headers, request_timeout, post_data, result, result_headers);

        Print("📥 Enhanced Response Code: ", res);
        Print("📥 Response data size: ", ArraySize(result), " bytes");

        if(res == 200) {
            string response = CharArrayToString(result);
            Print("📥 Enhanced Response: ", response);
            prediction = ParseEnhancedJsonResponse(response);

            // Cache the prediction
            prediction_cache[cache_index] = prediction;
            cache_index = (cache_index + 1) % 10;

            last_prediction = prediction;

            if(prediction.is_valid) {
                Print("✅ Enhanced Trade Decision: ", prediction.direction, " (",
                      DoubleToString(prediction.probability, 3), " confidence: ",
                      DoubleToString(prediction.confidence, 3), ")");
                Print("   Should Trade: ", prediction.should_trade ? "Yes" : "No");
                Print("   Confidence Threshold: ", DoubleToString(prediction.confidence_threshold, 3));
            } else {
                Print("❌ Enhanced Trade Decision failed: ", prediction.error_message);
            }
        } else {
            string response = CharArrayToString(result);
            Print("❌ Enhanced Response (Error): ", response);

            // Provide more specific error messages based on response code
            switch(res) {
                case -1:
                    prediction.error_message = "WebRequest failed - check internet connection and URL";
                    break;
                case 400:
                    prediction.error_message = "Bad request - check JSON format and data";
                    break;
                case 404:
                    prediction.error_message = "Enhanced endpoint not found - check if ML service is updated";
                    break;
                case 500:
                    prediction.error_message = "Server error - check ML service logs";
                    break;
                case 502:
                case 503:
                case 504:
                    prediction.error_message = "Service unavailable - ML server may be down";
                    break;
                default:
                    prediction.error_message = "HTTP error " + IntegerToString(res) + " - " + response;
                    break;
            }
        }

        return prediction;
    }

    // Get active trade recommendation via HTTP API
    MLPrediction GetActiveTradeRecommendation(MLFeatures &features, string trade_direction,
                                            double entry_price, double current_price,
                                            int trade_duration_minutes, double current_profit_pips,
                                            double account_balance, double current_profit_money) {
        MLPrediction prediction;
        prediction.is_valid = false;
        prediction.timestamp = TimeCurrent();

        Print("🔍 Active Trade Recommendation Request - Direction: ", trade_direction,
              ", Symbol: ", config.symbol, ", Timeframe: ", config.timeframe);

        if(!config.enabled) {
            prediction.error_message = "ML is disabled";
            Print("❌ ML is disabled");
            return prediction;
        }

        if(!TestConnection()) {
            prediction.error_message = "API server not connected";
            Print("❌ API server not connected");
            return prediction;
        }

        // Prepare JSON request with trade-specific data
        string json_request = PrepareActiveTradeJsonRequest(features, trade_direction,
                                                         entry_price, current_price,
                                                         trade_duration_minutes, current_profit_pips,
                                                         account_balance, current_profit_money);

        // Validate JSON request
        if(StringLen(json_request) == 0) {
            prediction.error_message = "Failed to prepare JSON request";
            Print("❌ Failed to prepare JSON request");
            return prediction;
        }

        Print("📤 Active Trade JSON Request length: ", StringLen(json_request), " characters");

        // Send HTTP request to active trade endpoint
        string url = config.api_url + "/active_trade_recommendation";
        string headers = "Content-Type: application/json\r\nAccept: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        // Convert JSON to UTF-8 uchar array
        StringToCharArray(json_request, post_data, 0, WHOLE_ARRAY, CP_UTF8);
        ArrayRemove(post_data, ArraySize(post_data)-1);

        Print("🌐 Sending active trade request to: ", url);
        Print("   Data length: ", ArraySize(post_data), " bytes");

        int res = WebRequest("POST", url, headers, request_timeout, post_data, result, result_headers);

        Print("📥 Active Trade Response Code: ", res);
        Print("📥 Response data size: ", ArraySize(result), " bytes");

        if(res == 200) {
            string response = CharArrayToString(result);
            Print("📥 Active Trade Response: ", response);
            prediction = ParseActiveTradeResponse(response);

            if(prediction.is_valid) {
                Print("✅ Active Trade Recommendation: ", prediction.direction, " (",
                      DoubleToString(prediction.probability, 3), " confidence: ",
                      DoubleToString(prediction.confidence, 3), ")");
            } else {
                Print("❌ Active Trade Recommendation failed: ", prediction.error_message);
            }
        } else {
            string response = CharArrayToString(result);
            Print("❌ Active Trade Response (Error): ", response);

            // Provide specific error messages
            switch(res) {
                case -1:
                    prediction.error_message = "WebRequest failed - check internet connection and URL";
                    break;
                case 400:
                    prediction.error_message = "Bad request - check trade data format";
                    break;
                case 404:
                    prediction.error_message = "Active trade endpoint not found - check if ML service is updated";
                    break;
                case 500:
                    prediction.error_message = "Server error - check ML service logs";
                    break;
                default:
                    prediction.error_message = "HTTP error " + IntegerToString(res) + " - " + response;
                    break;
            }
        }

        return prediction;
    }

public:
    // Check if a signal is valid based on confidence thresholds
    bool IsSignalValid(MLPrediction &prediction) {
        if(!prediction.is_valid) {
            return false;
        }

        if(prediction.confidence < config.min_confidence || prediction.confidence > config.max_confidence) {
            return false;
        }

        return true;
    }

    // Adjust stop loss distance based on ML prediction (more reasonable than price adjustment)
    double AdjustStopDistance(double base_stop_distance, MLPrediction &prediction) {
        if(!prediction.is_valid) {
            return base_stop_distance;
        }

        // Small adjustment based on confidence (±20% max)
        // Higher confidence = slightly wider stops, lower confidence = tighter stops
        double adjustment_factor = 1.0 + (prediction.confidence - 0.5) * 0.4; // ±20% adjustment

        // Ensure adjustment factor stays within reasonable bounds
        adjustment_factor = MathMax(0.8, MathMin(1.2, adjustment_factor));

        double adjusted_distance = base_stop_distance * adjustment_factor;

        Print("🔧 ML Stop Distance Adjustment:");
        Print("   Base distance: ", DoubleToString(base_stop_distance, 5), " points");
        Print("   ML confidence: ", DoubleToString(prediction.confidence, 3));
        Print("   Adjustment factor: ", DoubleToString(adjustment_factor, 3));
        Print("   Adjusted distance: ", DoubleToString(adjusted_distance, 5), " points");

        return adjusted_distance;
    }

    // Calculate final stop loss price from entry and adjusted distance
    double CalculateAdjustedStopLoss(double entry_price, double base_stop_loss, MLPrediction &prediction, string direction) {
        if(!prediction.is_valid) {
            return base_stop_loss;
        }

        // Calculate base stop distance
        double base_stop_distance = MathAbs(base_stop_loss - entry_price);

        // Adjust the distance (not the price)
        double adjusted_distance = AdjustStopDistance(base_stop_distance, prediction);

        // Apply adjusted distance back to get final stop price
        double adjusted_stop_loss;
        if(direction == "buy") {
            adjusted_stop_loss = entry_price - adjusted_distance;
        } else if(direction == "sell") {
            adjusted_stop_loss = entry_price + adjusted_distance;
        } else {
            return base_stop_loss; // Invalid direction
        }

        Print("🎯 Final Stop Loss Calculation:");
        Print("   Entry: ", DoubleToString(entry_price, _Digits));
        Print("   Base stop: ", DoubleToString(base_stop_loss, _Digits));
        Print("   Adjusted stop: ", DoubleToString(adjusted_stop_loss, _Digits));
        Print("   Direction: ", direction);

        return adjusted_stop_loss;
    }

    // DEPRECATED: Keep old function for backward compatibility but mark as deprecated
    double AdjustStopLoss(double base_stop_loss, MLPrediction &prediction, string direction) {
        Print("⚠️ DEPRECATED: AdjustStopLoss() - Use CalculateAdjustedStopLoss() instead");
        return base_stop_loss; // Just return base value to avoid breaking existing code
    }

    // Adjust position size based on ML prediction
    double AdjustPositionSize(double base_lot_size, MLPrediction &prediction) {
        if(!prediction.is_valid) {
            return base_lot_size;
        }

        // Adjust based on confidence and probability
        double adjustment_factor = 1.0;

        if(prediction.confidence > 0.7) {
            adjustment_factor = 1.2; // Increase size for high confidence
        } else if(prediction.confidence < 0.4) {
            adjustment_factor = 0.8; // Decrease size for low confidence
        }

        return base_lot_size * adjustment_factor;
    }

    // Get service status
    string GetStatus() {
        if(!TestConnection()) {
            return "Disconnected";
        }

        string url = config.api_url + "/status";
        string headers = "Content-Type: application/json\r\n";
        char post_data[];
        char result[];

        int res = WebRequest("GET", url, headers, 0, post_data, result, headers);

        if(res == 200) {
            string response = CharArrayToString(result);
            return "Connected - " + response;
        }

        return "Error - HTTP " + IntegerToString(res);
    }

public:
    //+------------------------------------------------------------------+
    //| Register a pending trade for ML logging                           |
    //+------------------------------------------------------------------+
    void RegisterPendingTrade(string direction, double entry_price, double stop_loss, double take_profit,
                                             double lot_size, MLPrediction& prediction, MLFeatures& features, int maxCapacity) {
        // Check capacity BEFORE allowing trade registration
        if(!CanTrackMoreTrades(maxCapacity)) {
            Print("❌ Cannot register pending trade - unified trade array is full (", unified_trade_count, "/", maxCapacity, ")");
            Print("⚠️ Trade execution should be prevented when capacity is exhausted");
            Print("🔍 Remaining capacity: ", GetRemainingTradeCapacity(maxCapacity), " slots");
            PrintUnifiedTradeArrayStatus(maxCapacity);
            return;
        }

        UnifiedTradeData new_trade;
        new_trade.ticket = 0;  // Will be set when actual ticket is known
        new_trade.direction = direction;
        new_trade.timeframe = config.timeframe;  // Set the timeframe for this trade
        new_trade.entry_price = entry_price;
        new_trade.stop_loss = stop_loss;
        new_trade.take_profit = take_profit;
        new_trade.lot_size = lot_size;
        new_trade.prediction = prediction;
        new_trade.features = features;
        new_trade.is_logged = false;
        new_trade.is_open = false;
        new_trade.created_time = TimeCurrent();
        new_trade.opened_time = 0;
        new_trade.last_monitoring_check = 0;  // Initialize monitoring timestamp
        new_trade.monitoring_enabled = false;  // Will be enabled when monitoring starts

        AddUnifiedTrade(unified_trades, unified_trade_count, new_trade, maxCapacity);
        PrintUnifiedTrades(unified_trades, unified_trade_count, "After registering new pending trade");
    }

    //+------------------------------------------------------------------+
    //| Log trade data for ML retraining                                  |
    //+------------------------------------------------------------------+
    void LogTradeForRetraining(string trade_id, string direction, double entry, double sl, double tp, double lot, MLPrediction &prediction, MLFeatures &features) {
        if(!config.enabled) return;

        Print("📊 Logging trade data for ML retraining...");

        // Use the provided trade_id (should be MT5 ticket number)
        // Don't generate unique IDs - wait for actual MT5 ticket
        if(trade_id == "0" || trade_id == "" || trade_id == "null") {
            Print("⚠️ Trade ID is placeholder - waiting for actual MT5 ticket number");
            return; // Skip logging until we have a real ticket number
        }

        // Validate prediction data
        if(prediction.model_key == "" || prediction.model_key == "null") {
            Print("❌ Cannot log trade for ML retraining - missing model_key");
            Print("   Trade ID: ", trade_id);
            Print("   Direction: ", direction);
            Print("   Model Key: '", prediction.model_key, "'");
            Print("   Prediction Valid: ", prediction.is_valid ? "Yes" : "No");
            return;
        }

        // Create JSON object using the library
        CJAVal json_request;

        // Set main properties
        json_request["trade_id"] = trade_id;
        json_request["strategy"] = config.strategy_name;
        json_request["symbol"] = config.symbol;
        json_request["timeframe"] = config.timeframe;
        json_request["direction"] = direction;
        json_request["entry_price"] = entry;
        json_request["stop_loss"] = sl;
        json_request["take_profit"] = tp;
        json_request["lot_size"] = lot;
        json_request["ml_prediction"] = prediction.probability;
        json_request["ml_confidence"] = prediction.confidence;
        json_request["ml_model_type"] = direction;
        json_request["ml_model_key"] = prediction.model_key;
        json_request["trade_time"] = (long)TimeCurrent();

        // Add all features for ML training (flat structure)
        json_request["rsi"] = features.rsi;
        json_request["stoch_main"] = features.stoch_main;
        json_request["stoch_signal"] = features.stoch_signal;
        json_request["macd_main"] = features.macd_main;
        json_request["macd_signal"] = features.macd_signal;
        json_request["bb_upper"] = features.bb_upper;
        json_request["bb_lower"] = features.bb_lower;
        json_request["williams_r"] = features.williams_r;
        json_request["cci"] = features.cci;
        json_request["momentum"] = features.momentum;
        json_request["force_index"] = features.force_index;
        json_request["volume_ratio"] = features.volume_ratio;
        json_request["price_change"] = features.price_change;
        json_request["volatility"] = features.volatility;
        json_request["spread"] = features.spread;
        json_request["session_hour"] = features.session_hour;
        json_request["is_news_time"] = features.is_news_time;
        json_request["day_of_week"] = features.day_of_week;
        json_request["month"] = features.month;

        // Add trade status (will be updated when trade closes)
        json_request["status"] = "OPEN";
        json_request["profit_loss"] = 0.0;
        json_request["close_price"] = 0.0;
        json_request["close_time"] = 0;
        json_request["exit_reason"] = "";
        json_request["timestamp"] = (long)TimeCurrent();

        // Serialize to string
        string json_string;
        json_request.Serialize(json_string);

        Print("📊 JSON length: ", StringLen(json_string), " characters");
        Print("✅ JSON created successfully using JSON library");

        // Send to analytics server for ML retraining
        string url = "http://127.0.0.1:5001/ml_trade_log"; // Analytics server URL
        string headers = "Content-Type: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        StringToCharArray(json_string, post_data, 0, WHOLE_ARRAY, CP_UTF8);
        ArrayRemove(post_data, ArraySize(post_data)-1);

        int res = WebRequest("POST", url, headers, 5000, post_data, result, result_headers);

        if(res == 200 || res == 201) {
            Print("✅ Trade data logged for ML retraining (HTTP ", res, ")");
        } else {
            Print("❌ Failed to log trade data for ML retraining - HTTP ", res);
        }
    }

    //+------------------------------------------------------------------+
    //| Log trade close data for ML retraining                            |
    //+------------------------------------------------------------------+
    void LogTradeCloseForRetraining(string trade_id, double closePrice, double profitLoss, double profitLossPips, datetime closeTime) {
        Print("🔍 LogTradeCloseForRetraining() called with:");
        Print("   Trade ID: ", trade_id);
        Print("   Close Price: ", DoubleToString(closePrice, _Digits));
        Print("   Profit/Loss: $", DoubleToString(profitLoss, 2));
        Print("   Profit/Loss Pips: ", DoubleToString(profitLossPips, 1));
        Print("   Close Time: ", TimeToString(closeTime));
        Print("   Config enabled: ", config.enabled ? "true" : "false");

        if(!config.enabled) {
            Print("❌ ML interface disabled - skipping trade close logging");
            return;
        }

        Print("📊 Logging trade close data for ML retraining...");

        // Determine exit reason based on profit/loss
        string exitReason = "unknown";
        if(profitLoss > 0) {
            exitReason = "take_profit";
        } else if(profitLoss < 0) {
            exitReason = "stop_loss";
        } else {
            exitReason = "manual_close";
        }

        // Create JSON object using the library
        CJAVal json_request;

        // Set main properties
        json_request["trade_id"] = trade_id;
        json_request["strategy"] = config.strategy_name;
        json_request["symbol"] = config.symbol;
        json_request["timeframe"] = config.timeframe;
        json_request["close_price"] = closePrice;
        json_request["profit_loss"] = profitLoss;
        json_request["profit_loss_pips"] = profitLossPips;
        json_request["close_time"] = (long)closeTime;
        json_request["trade_time"] = (long)closeTime; // Will be updated by server to actual trade time
        json_request["exit_reason"] = exitReason;
        json_request["status"] = "CLOSED";
        json_request["success"] = (profitLoss > 0);
        json_request["timestamp"] = (long)TimeCurrent();

        // Serialize to string
        string json_string;
        json_request.Serialize(json_string);

        Print("📊 JSON length: ", StringLen(json_string), " characters");
        Print("✅ JSON created successfully using JSON library");

        // Send to analytics server for ML retraining
        string url = "http://127.0.0.1:5001/ml_trade_close"; // Analytics server URL
        string headers = "Content-Type: application/json\r\n";
        uchar post_data[];
        uchar result[];
        string result_headers;

        Print("🔍 Sending HTTP request to: ", url);
        Print("🔍 JSON payload: ", json_string);

        StringToCharArray(json_string, post_data, 0, WHOLE_ARRAY, CP_UTF8);
        ArrayRemove(post_data, ArraySize(post_data)-1);

        int res = WebRequest("POST", url, headers, 5000, post_data, result, result_headers);

        Print("🔍 HTTP response code: ", res);
        Print("🔍 Response headers: ", result_headers);
        if(ArraySize(result) > 0) {
            string response_text = CharArrayToString(result);
            Print("🔍 Response body: ", response_text);
        }

        if(res == 200 || res == 201) {
            Print("✅ Trade close data logged for ML retraining (HTTP ", res, ")");
            Print("   Profit/Loss: $", DoubleToString(profitLoss, 2), " (", DoubleToString(profitLossPips, 1), " pips)");
            Print("   Exit Reason: ", exitReason);
        } else {
            Print("❌ Failed to log trade close data for ML retraining - HTTP ", res);
        }
    }

    //+------------------------------------------------------------------+
    //| Create JSON string from features for analytics                   |
    //+------------------------------------------------------------------+
    string CreateFeatureJSON(MLFeatures &features, string direction) {
        // Create JSON object using the library for robust JSON construction
        CJAVal json_obj;

        // Add top-level fields
        json_obj["strategy"] = config.strategy_name;
        json_obj["symbol"] = config.symbol;
        json_obj["timeframe"] = config.timeframe;
        json_obj["direction"] = direction;
        json_obj["timestamp"] = (long)TimeCurrent();

        // Add all features as flat fields (no nesting)
        json_obj["rsi"] = features.rsi;
        json_obj["stoch_main"] = features.stoch_main;
        json_obj["stoch_signal"] = features.stoch_signal;
        json_obj["macd_main"] = features.macd_main;
        json_obj["macd_signal"] = features.macd_signal;
        json_obj["bb_upper"] = features.bb_upper;
        json_obj["bb_lower"] = features.bb_lower;
        json_obj["williams_r"] = features.williams_r;
        json_obj["cci"] = features.cci;
        json_obj["momentum"] = features.momentum;
        json_obj["force_index"] = features.force_index;
        json_obj["volume_ratio"] = features.volume_ratio;
        json_obj["price_change"] = features.price_change;
        json_obj["volatility"] = features.volatility;
        json_obj["spread"] = features.spread;
        json_obj["session_hour"] = features.session_hour;
        json_obj["is_news_time"] = features.is_news_time;
        json_obj["day_of_week"] = features.day_of_week;
        json_obj["month"] = features.month;

        // Serialize to string
        string json_string;
        json_obj.Serialize(json_string);

        // Escape the JSON string for use within another JSON structure
        string escaped_json = EscapeJsonString(json_string);

        return escaped_json;
    }

        //+------------------------------------------------------------------+
    //| Escape JSON string for use within another JSON structure         |
    //+------------------------------------------------------------------+
    string EscapeJsonString(string json_str) {
        string escaped = "";
        int len = StringLen(json_str);

        for(int i = 0; i < len; i++) {
            ushort char_code = StringGetCharacter(json_str, i);

            if(char_code == 34) {  // Double quote "
                escaped += "\\\"";
            } else if(char_code == 92) {  // Backslash \
                escaped += "\\\\";
            } else if(char_code == 10) {  // Newline \n
                escaped += "\\n";
            } else if(char_code == 13) {  // Carriage return \r
                escaped += "\\r";
            } else if(char_code == 9) {   // Tab \t
                escaped += "\\t";
            } else {
                // Convert character code back to string and append
                string char_str = "";
                StringSetCharacter(char_str, 0, char_code);
                escaped += char_str;
            }
        }
        return escaped;
    }

    //+------------------------------------------------------------------+
    //| Analytics callback function type definitions                     |
    //+------------------------------------------------------------------+
    typedef void (*TradeEntryCallback)(string direction, double entry_price, double stop_loss, double take_profit, double lot_size, string strategy_name, string version);
    typedef void (*MarketConditionsCallback)(MLFeatures& features);
    typedef void (*MLPredictionCallback)(string model_name, string model_type, double probability, double confidence, string features_json);
    typedef void (*SetTradeIDCallback)(ulong position_ticket);
    typedef void (*TradeExitCallback)(double close_price, double profit, double profitLossPips);

public:
    //+------------------------------------------------------------------+
    //| Collect market features - unified function for all EAs           |
    //+------------------------------------------------------------------+
    void CollectMarketFeatures(MLFeatures &features) {
        Print("📊 Collecting market features...");

        // Technical indicators
        int rsi_handle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
        if(rsi_handle == INVALID_HANDLE) {
            Print("❌ Failed to create RSI indicator handle");
            features.rsi = 50.0;
        } else {
            double rsi_buffer[];
            ArraySetAsSeries(rsi_buffer, true);
            if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) <= 0) {
                Print("❌ Failed to copy RSI data");
                features.rsi = 50.0;
            } else {
                features.rsi = rsi_buffer[0];
            }
        }

        int stoch_handle = iStochastic(_Symbol, _Period, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
        if(stoch_handle == INVALID_HANDLE) {
            Print("❌ Failed to create Stochastic indicator handle");
            features.stoch_main = 50.0;
            features.stoch_signal = 50.0;
        } else {
            double stoch_main_buffer[], stoch_signal_buffer[];
            ArraySetAsSeries(stoch_main_buffer, true);
            ArraySetAsSeries(stoch_signal_buffer, true);
            if(CopyBuffer(stoch_handle, 0, 0, 1, stoch_main_buffer) <= 0 ||
               CopyBuffer(stoch_handle, 1, 0, 1, stoch_signal_buffer) <= 0) {
                Print("❌ Failed to copy Stochastic data");
                features.stoch_main = 50.0;
                features.stoch_signal = 50.0;
            } else {
                features.stoch_main = stoch_main_buffer[0];
                features.stoch_signal = stoch_signal_buffer[0];
            }
        }

        int macd_handle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
        if(macd_handle == INVALID_HANDLE) {
            Print("❌ Failed to create MACD indicator handle");
            features.macd_main = 0.0;
            features.macd_signal = 0.0;
        } else {
            double macd_main_buffer[], macd_signal_buffer[];
            ArraySetAsSeries(macd_main_buffer, true);
            ArraySetAsSeries(macd_signal_buffer, true);
            if(CopyBuffer(macd_handle, 0, 0, 1, macd_main_buffer) <= 0 ||
               CopyBuffer(macd_handle, 1, 0, 1, macd_signal_buffer) <= 0) {
                Print("❌ Failed to copy MACD data");
                features.macd_main = 0.0;
                features.macd_signal = 0.0;
            } else {
                features.macd_main = macd_main_buffer[0];
                features.macd_signal = macd_signal_buffer[0];
            }
        }

        // Bollinger Bands
        int bb_handle = iBands(_Symbol, _Period, 20, 2, 0, PRICE_CLOSE);
        if(bb_handle == INVALID_HANDLE) {
            Print("❌ Failed to create Bollinger Bands indicator handle");
            features.bb_upper = 0.0;
            features.bb_lower = 0.0;
        } else {
            double bb_upper_buffer[], bb_lower_buffer[];
            ArraySetAsSeries(bb_upper_buffer, true);
            ArraySetAsSeries(bb_lower_buffer, true);
            if(CopyBuffer(bb_handle, 1, 0, 1, bb_upper_buffer) <= 0 ||
               CopyBuffer(bb_handle, 2, 0, 1, bb_lower_buffer) <= 0) {
                Print("❌ Failed to copy Bollinger Bands data");
                features.bb_upper = 0.0;
                features.bb_lower = 0.0;
            } else {
                features.bb_upper = bb_upper_buffer[0];
                features.bb_lower = bb_lower_buffer[0];
            }
        }

        // Williams %R
        int williams_handle = iWPR(_Symbol, _Period, 14);
        if(williams_handle == INVALID_HANDLE) {
            Print("❌ Failed to create Williams %R indicator handle");
            features.williams_r = 50.0;
        } else {
            double williams_buffer[];
            ArraySetAsSeries(williams_buffer, true);
            if(CopyBuffer(williams_handle, 0, 0, 1, williams_buffer) <= 0) {
                Print("❌ Failed to copy Williams %R data");
                features.williams_r = 50.0;
            } else {
                features.williams_r = williams_buffer[0];
            }
        }

        int cci_handle = iCCI(_Symbol, _Period, 14, PRICE_TYPICAL);
        if(cci_handle == INVALID_HANDLE) {
            Print("❌ Failed to create CCI indicator handle");
            features.cci = 0.0;
        } else {
            double cci_buffer[];
            ArraySetAsSeries(cci_buffer, true);
            if(CopyBuffer(cci_handle, 0, 0, 1, cci_buffer) <= 0) {
                Print("❌ Failed to copy CCI data");
                features.cci = 0.0;
            } else {
                features.cci = cci_buffer[0];
            }
        }

        int momentum_handle = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);
        if(momentum_handle == INVALID_HANDLE) {
            Print("❌ Failed to create Momentum indicator handle");
            features.momentum = 100.0;
        } else {
            double momentum_buffer[];
            ArraySetAsSeries(momentum_buffer, true);
            if(CopyBuffer(momentum_handle, 0, 0, 1, momentum_buffer) <= 0) {
                Print("❌ Failed to copy Momentum data");
                features.momentum = 100.0;
            } else {
                features.momentum = momentum_buffer[0];
            }
        }

        // Market conditions
        long volume_array[];
        ArraySetAsSeries(volume_array, true);
        if(CopyTickVolume(_Symbol, _Period, 0, 2, volume_array) < 2) {
            Print("❌ Failed to copy volume data");
            features.volume_ratio = 1.0;
        } else {
            features.volume_ratio = (volume_array[0] > 0) ? (double)volume_array[0] / volume_array[1] : 1.0;
        }

        double close_array[];
        ArraySetAsSeries(close_array, true);
        if(CopyClose(_Symbol, _Period, 0, 2, close_array) < 2) {
            Print("❌ Failed to copy close price data");
            features.price_change = 0.0;
            features.volatility = 0.001;
        } else {
            features.price_change = (close_array[0] - close_array[1]) / close_array[1];
            features.volatility = MathAbs(features.price_change);
        }

        features.spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Time-based features
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        features.session_hour = dt.hour;
        features.is_news_time = false;
        features.day_of_week = dt.day_of_week;
        features.month = dt.mon;

        // Force Index calculation
        if(volume_array[0] > 0 && close_array[1] != 0) {
            features.force_index = volume_array[0] * (close_array[0] - close_array[1]);
        } else {
            features.force_index = 0.0;
        }

        // Trade calculation features (required for enhanced endpoint)
        features.current_price = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;

        // Calculate ATR
        int atr_handle = iATR(_Symbol, _Period, 14);
        if(atr_handle == INVALID_HANDLE) {
            Print("❌ Failed to create ATR indicator handle");
            features.atr = features.current_price * 0.001; // Default to 0.1% of price
        } else {
            double atr_buffer[];
            ArraySetAsSeries(atr_buffer, true);
            if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) <= 0) {
                Print("❌ Failed to copy ATR data");
                features.atr = features.current_price * 0.001; // Default to 0.1% of price
            } else {
                features.atr = atr_buffer[0];
            }
        }

        // Account balance and risk per pip
        features.account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        features.risk_per_pip = 1.0; // Default $1 per pip (can be made configurable later)

        // Validate features
        ValidateFeatures(features);

        Print("✅ Features collected - RSI: ", DoubleToString(features.rsi, 2),
              ", MACD: ", DoubleToString(features.macd_main, 2),
              ", BB_Upper: ", DoubleToString(features.bb_upper, _Digits),
              ", Price Change: ", DoubleToString(features.price_change * 100, 3), "%");
        Print("   Trade Calc - Price: ", DoubleToString(features.current_price, _Digits),
              ", ATR: ", DoubleToString(features.atr, _Digits),
              ", Balance: $", DoubleToString(features.account_balance, 2),
              ", Risk/Pip: $", DoubleToString(features.risk_per_pip, 2));
    }

    //+------------------------------------------------------------------+
    //| Validate and fix feature values                                  |
    //+------------------------------------------------------------------+
    void ValidateFeatures(MLFeatures &features) {
        if(!MathIsValidNumber(features.rsi) || !MathIsValidNumber(features.stoch_main) ||
           !MathIsValidNumber(features.stoch_signal) || !MathIsValidNumber(features.macd_main) ||
           !MathIsValidNumber(features.macd_signal) || !MathIsValidNumber(features.bb_upper) ||
           !MathIsValidNumber(features.bb_lower) || !MathIsValidNumber(features.williams_r) ||
           !MathIsValidNumber(features.cci) || !MathIsValidNumber(features.momentum) ||
           !MathIsValidNumber(features.volume_ratio) || !MathIsValidNumber(features.price_change) ||
           !MathIsValidNumber(features.volatility) || !MathIsValidNumber(features.force_index) ||
           !MathIsValidNumber(features.spread) || !MathIsValidNumber(features.current_price) ||
           !MathIsValidNumber(features.atr) || !MathIsValidNumber(features.account_balance) ||
           !MathIsValidNumber(features.risk_per_pip)) {

            Print("❌ Invalid feature values detected - using fallback values");
            Print("   RSI: ", features.rsi, " (valid: ", MathIsValidNumber(features.rsi), ")");
            Print("   Stoch Main: ", features.stoch_main, " (valid: ", MathIsValidNumber(features.stoch_main), ")");
            Print("   Stoch Signal: ", features.stoch_signal, " (valid: ", MathIsValidNumber(features.stoch_signal), ")");
            Print("   MACD Main: ", features.macd_main, " (valid: ", MathIsValidNumber(features.macd_main), ")");
            Print("   MACD Signal: ", features.macd_signal, " (valid: ", MathIsValidNumber(features.macd_signal), ")");
            Print("   BB Upper: ", features.bb_upper, " (valid: ", MathIsValidNumber(features.bb_upper), ")");
            Print("   BB Lower: ", features.bb_lower, " (valid: ", MathIsValidNumber(features.bb_lower), ")");
            Print("   Williams R: ", features.williams_r, " (valid: ", MathIsValidNumber(features.williams_r), ")");
            Print("   CCI: ", features.cci, " (valid: ", MathIsValidNumber(features.cci), ")");
            Print("   Momentum: ", features.momentum, " (valid: ", MathIsValidNumber(features.momentum), ")");
            Print("   Volume Ratio: ", features.volume_ratio, " (valid: ", MathIsValidNumber(features.volume_ratio), ")");
            Print("   Price Change: ", features.price_change, " (valid: ", MathIsValidNumber(features.price_change), ")");
            Print("   Volatility: ", features.volatility, " (valid: ", MathIsValidNumber(features.volatility), ")");
            Print("   Force Index: ", features.force_index, " (valid: ", MathIsValidNumber(features.force_index), ")");
            Print("   Spread: ", features.spread, " (valid: ", MathIsValidNumber(features.spread), ")");
            Print("   Current Price: ", features.current_price, " (valid: ", MathIsValidNumber(features.current_price), ")");
            Print("   ATR: ", features.atr, " (valid: ", MathIsValidNumber(features.atr), ")");
            Print("   Account Balance: ", features.account_balance, " (valid: ", MathIsValidNumber(features.account_balance), ")");
            Print("   Risk Per Pip: ", features.risk_per_pip, " (valid: ", MathIsValidNumber(features.risk_per_pip), ")");

            // Set fallback values for invalid features
            if(!MathIsValidNumber(features.rsi)) features.rsi = 50.0;
            if(!MathIsValidNumber(features.stoch_main)) features.stoch_main = 50.0;
            if(!MathIsValidNumber(features.stoch_signal)) features.stoch_signal = 50.0;
            if(!MathIsValidNumber(features.macd_main)) features.macd_main = 0.0;
            if(!MathIsValidNumber(features.macd_signal)) features.macd_signal = 0.0;
            if(!MathIsValidNumber(features.bb_upper)) features.bb_upper = 0.0;
            if(!MathIsValidNumber(features.bb_lower)) features.bb_lower = 0.0;
            if(!MathIsValidNumber(features.williams_r)) features.williams_r = 50.0;
            if(!MathIsValidNumber(features.cci)) features.cci = 0.0;
            if(!MathIsValidNumber(features.momentum)) features.momentum = 100.0;
            if(!MathIsValidNumber(features.volume_ratio)) features.volume_ratio = 1.0;
            if(!MathIsValidNumber(features.price_change)) features.price_change = 0.0;
            if(!MathIsValidNumber(features.volatility)) features.volatility = 0.001;
            if(!MathIsValidNumber(features.force_index)) features.force_index = 0.0;
            if(!MathIsValidNumber(features.spread)) features.spread = 1.0;
            if(!MathIsValidNumber(features.current_price)) features.current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(!MathIsValidNumber(features.atr)) features.atr = features.current_price * 0.001;
            if(!MathIsValidNumber(features.account_balance)) features.account_balance = 10000.0;
            if(!MathIsValidNumber(features.risk_per_pip)) features.risk_per_pip = 1.0;
        }
    }

    //+------------------------------------------------------------------+
    //| Unified analytics handler using individual callbacks             |
    //+------------------------------------------------------------------+
    void HandleTradeAnalytics(double entry_price, double lot_size, string direction, string strategy_name,
                             MLFeatures& param_lastMarketFeatures, string& param_lastTradeDirection, MLPrediction& param_lastMLPrediction,
                             SetTradeIDCallback setTradeIDCallback,
                             TradeEntryCallback tradeEntryCallback,
                             MarketConditionsCallback marketConditionsCallback,
                             MLPredictionCallback mlPredictionCallback,
                             ulong position_ticket) {

        Print("📊 Recording trade entry analytics...");

        // For now, use placeholder values for SL/TP (can be enhanced later)
        double stop_loss = 0.0;
        double take_profit = 0.0;

        // Set the analytics trade ID (EA-specific)
        if(setTradeIDCallback != NULL) {
            setTradeIDCallback(position_ticket);
        }

        // Record trade entry
        if(tradeEntryCallback != NULL) {
            tradeEntryCallback(direction, entry_price, stop_loss, take_profit, lot_size, strategy_name, "1.00");
            Print("✅ Recorded trade entry analytics");
        }

        // Record market conditions for every trade (regardless of ML prediction)
        if(param_lastMarketFeatures.rsi != 0 && marketConditionsCallback != NULL) {
            marketConditionsCallback(param_lastMarketFeatures);
            Print("✅ Recorded market conditions analytics");
        }

        // Record ML prediction if we have stored data
        if(param_lastTradeDirection != "" && mlPredictionCallback != NULL) {
            // Record ML prediction with features JSON - use standardized model names and types
            string model_name = (direction == "BUY") ? "buy_model_improved" : "sell_model_improved";
            string model_type = direction;
            string features_json = CreateFeatureJSON(param_lastMarketFeatures, direction);

            // Debug logging to track parameter types
            Print("🔍 HandleTradeAnalytics - About to call MLPredictionCallback:");
            Print("   model_name: '", model_name, "' (type: string, length: ", StringLen(model_name), ")");
            Print("   model_type: '", model_type, "' (type: string, length: ", StringLen(model_type), ")");
            Print("   probability: ", param_lastMLPrediction.probability, " (type: double)");
            Print("   confidence: ", param_lastMLPrediction.confidence, " (type: double)");
            Print("   features_json length: ", StringLen(features_json));

            mlPredictionCallback(model_name, model_type, param_lastMLPrediction.probability, param_lastMLPrediction.confidence, features_json);
            Print("✅ Recorded ML prediction analytics with features");

            // Clear stored data
            param_lastTradeDirection = "";
        }
    }

public:
    //+------------------------------------------------------------------+
    //| Check if we can track more trades (unified system)                |
    //+------------------------------------------------------------------+
    bool CanTrackMoreTrades(int maxCapacity) {
        if(unified_trade_count >= maxCapacity) {
            Print("❌ Unified trade array is full (", unified_trade_count, "/", maxCapacity, ")");
            return false;
        }
        return true;
    }

    //+------------------------------------------------------------------+
    //| Get remaining capacity for unified trade tracking                 |
    //+------------------------------------------------------------------+
    int GetRemainingTradeCapacity(int maxCapacity) {
        return MathMax(0, maxCapacity - unified_trade_count);
    }

    //+------------------------------------------------------------------+
    //| Get current unified trade count for debugging                     |
    //+------------------------------------------------------------------+
    int GetCurrentUnifiedTradeCount() {
        return unified_trade_count;
    }

    //+------------------------------------------------------------------+
    //| Print unified trade array status for debugging                    |
    //+------------------------------------------------------------------+
    void PrintUnifiedTradeArrayStatus(int maxCapacity) {
        Print("🔍 Unified Trade Array Status:");
        Print("   Current count: ", unified_trade_count);
        Print("   Max capacity: ", maxCapacity);
        Print("   Remaining slots: ", GetRemainingTradeCapacity(maxCapacity));
        Print("   Array utilization: ", DoubleToString((double)unified_trade_count / maxCapacity * 100, 1), "%");
    }

    //+------------------------------------------------------------------+
    //| Check if EA has open positions (unified system)                   |
    //+------------------------------------------------------------------+
    bool HasOpenPositionForThisEAUnified(bool allowMultipleOrders) {
        // If multiple simultaneous orders are allowed, don't check for existing positions
        if(allowMultipleOrders) {
            Print("🔍 Multiple simultaneous orders allowed - skipping position check");
            return false;
        }

        // Check if we're tracking any open positions in unified array
        int openPositionCount = 0;
        for(int i = 0; i < unified_trade_count; i++) {
            if(unified_trades[i].is_open) {
                openPositionCount++;
            }
        }

        if(openPositionCount > 0) {
            Print("✅ Found ", openPositionCount, " open position(s) for this EA in unified array");
            return true;
        }

        Print("❌ No open positions found for this EA in unified array");
        return false;
    }

    //+------------------------------------------------------------------+
    //| Helper functions for managing unified trade data arrays          |
    //+------------------------------------------------------------------+
    void AddUnifiedTrade(UnifiedTradeData& trades[], int& tradeCount, const UnifiedTradeData& newTrade, int maxCapacity) {
        if(tradeCount >= maxCapacity) {
            Print("❌ Cannot add unified trade - array is full (", tradeCount, "/", maxCapacity, ")");
            return;
        }

        trades[tradeCount] = newTrade;
        tradeCount++;
        Print("✅ Added unified trade ", tradeCount, " - Direction: ", newTrade.direction, ", Lot: ", DoubleToString(newTrade.lot_size, 2));
    }

    void RemoveUnifiedTrade(int index, UnifiedTradeData& trades[], int& tradeCount) {
        if(index < 0 || index >= tradeCount) {
            Print("❌ Invalid unified trade index: ", index);
            return;
        }

        // Shift remaining elements down
        for(int i = index; i < tradeCount - 1; i++) {
            trades[i] = trades[i + 1];
        }

        // Clear the last element
        UnifiedTradeData empty_trade;
        trades[tradeCount - 1] = empty_trade;
        tradeCount--;

        Print("✅ Removed unified trade at index ", index, " - Remaining: ", tradeCount);
    }

    int FindUnifiedTradeByTicket(ulong ticket, const UnifiedTradeData& trades[], int tradeCount) {
        for(int i = 0; i < tradeCount; i++) {
            if(trades[i].ticket == ticket || trades[i].ticket == 0) {
                // Match by ticket or find first unassigned pending trade
                if(trades[i].ticket == 0) {
                    Print("🔍 Found unassigned unified trade at index ", i, " - assigning to ticket ", ticket);
                } else {
                    Print("🔍 Found unified trade for ticket ", ticket, " at index ", i);
                }
                return i;
            }
        }
        Print("⚠️ No unified trade found for ticket ", ticket);
        return -1;
    }

    void PrintUnifiedTrades(const UnifiedTradeData& trades[], int tradeCount, string context = "") {
        if(context != "") Print("🔍 ", context);
        Print("🔍 Currently tracking ", tradeCount, " unified trades:");
        for(int i = 0; i < tradeCount; i++) {
            Print("   [", i, "] Ticket: ", trades[i].ticket,
                  ", Direction: ", trades[i].direction,
                  ", Lot: ", DoubleToString(trades[i].lot_size, 2),
                  ", Open: ", trades[i].is_open ? "Yes" : "No",
                  ", Logged: ", trades[i].is_logged ? "Yes" : "No");
        }
    }



    //+------------------------------------------------------------------+
    //| Handle complete trade transaction - UNIFIED SYSTEM (no legacy params) |
    //+------------------------------------------------------------------+
    void HandleCompleteTradeTransactionUnified(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result,
                            datetime& param_lastPositionOpenTime,
                            string& param_lastTradeID,
                            bool enableHttpAnalytics,
                            string eaIdentifier,
                            string strategyName,
                            MLPrediction& param_lastMLPrediction,
                            MLFeatures& param_lastMarketFeatures,
                            string& param_lastTradeDirection,
                            SetTradeIDCallback setTradeIDCallback,
                            TradeEntryCallback tradeEntryCallback,
                            MarketConditionsCallback marketConditionsCallback,
                            MLPredictionCallback mlPredictionCallback,
                            TradeExitCallback tradeExitCallback,
                            int maxCapacity) {

        Print("🔄 OnTradeTransaction() called - UNIFIED SYSTEM - Transaction type: ", EnumToString(trans.type));
        Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);
        PrintUnifiedTrades(unified_trades, unified_trade_count, "Before processing transaction");

        // Debug logging to track parameter values
        Print("🔍 HandleCompleteTradeTransactionUnified received:");
        Print("   param_lastTradeDirection: '", param_lastTradeDirection, "' (type: string, length: ", StringLen(param_lastTradeDirection), ")");
        Print("   param_lastMLPrediction.is_valid: ", param_lastMLPrediction.is_valid ? "true" : "false");
        Print("   param_lastMLPrediction.direction: '", param_lastMLPrediction.direction, "'");

        // Handle trade open transactions using unified system
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0) {
            Print("🔍 Position opening transaction detected - Position: ", trans.position);

            // Verify this is our position by checking the deal
            if(HistoryDealSelect(trans.deal)) {
                string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
                string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
                ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

                Print("🔍 Deal symbol: ", deal_symbol, ", Comment: ", deal_comment);
                Print("🔍 EA identifier: ", eaIdentifier);
                Print("🔍 Deal entry type: ", EnumToString(deal_entry));

                // More flexible EA identifier matching to handle truncated comments
                bool comment_matches = false;
                if(StringFind(deal_comment, eaIdentifier) >= 0) {
                    comment_matches = true;
                } else {
                    // Check for partial match if comment might be truncated
                    string comment_prefix = StringSubstr(eaIdentifier, 0, MathMin(StringLen(eaIdentifier), StringLen(deal_comment)));
                    if(StringLen(deal_comment) >= StringLen(comment_prefix) - 2 && // Allow some tolerance
                       StringFind(deal_comment, comment_prefix) == 0) {
                        comment_matches = true;
                    }
                }

                if(comment_matches && deal_entry == DEAL_ENTRY_IN) {
                    Print("✅ Position confirmed as ours - updating unified array");
                    // Find the pending trade and assign the ticket
                    int pendingIndex = FindUnifiedTradeByTicket(0, unified_trades, unified_trade_count);
                    if(pendingIndex >= 0) {
                        unified_trades[pendingIndex].ticket = trans.position;
                        unified_trades[pendingIndex].is_open = true;
                        unified_trades[pendingIndex].opened_time = TimeCurrent();
                        Print("✅ Assigned ticket ", trans.position, " to pending trade at index ", pendingIndex);

                        // Log trade for ML retraining (pending trade that was just opened)
                        string trade_id = IntegerToString(trans.position);

                        // Get actual SL/TP from the position
                        double actual_sl = 0.0;
                        double actual_tp = 0.0;
                        if(PositionSelectByTicket(trans.position)) {
                            actual_sl = PositionGetDouble(POSITION_SL);
                            actual_tp = PositionGetDouble(POSITION_TP);
                        }

                        // Use the prediction data stored with this specific trade
                        LogTradeForRetraining(trade_id, unified_trades[pendingIndex].direction, unified_trades[pendingIndex].entry_price, actual_sl, actual_tp, unified_trades[pendingIndex].lot_size, unified_trades[pendingIndex].prediction, unified_trades[pendingIndex].features);
                        Print("📊 Logged pending trade for ML retraining with SL: ", DoubleToString(actual_sl, _Digits), ", TP: ", DoubleToString(actual_tp, _Digits));
                    } else {
                        Print("⚠️ No pending trade found for new position - creating new entry");
                        // Create new unified trade entry
                        UnifiedTradeData newTrade;
                        newTrade.ticket = trans.position;
                        newTrade.direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
                        newTrade.entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                        newTrade.lot_size = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                        newTrade.stop_loss = 0.0;  // Will be updated from position
                        newTrade.take_profit = 0.0; // Will be updated from position
                        newTrade.prediction = param_lastMLPrediction;  // Store current prediction
                        newTrade.features = param_lastMarketFeatures; // Store current features
                        newTrade.is_open = true;
                        newTrade.is_logged = false;
                        newTrade.created_time = TimeCurrent();
                        newTrade.opened_time = TimeCurrent();

                        AddUnifiedTrade(unified_trades, unified_trade_count, newTrade, maxCapacity);

                        // Log trade for ML retraining
                        string trade_id = IntegerToString(trans.position);

                        // Get actual SL/TP from the position
                        double actual_sl = 0.0;
                        double actual_tp = 0.0;
                        if(PositionSelectByTicket(trans.position)) {
                            actual_sl = PositionGetDouble(POSITION_SL);
                            actual_tp = PositionGetDouble(POSITION_TP);
                        }

                        // Use the prediction data stored with this specific trade
                        LogTradeForRetraining(trade_id, newTrade.direction, newTrade.entry_price, actual_sl, actual_tp, newTrade.lot_size, newTrade.prediction, newTrade.features);
                        Print("📊 Logged trade for ML retraining with SL: ", DoubleToString(actual_sl, _Digits), ", TP: ", DoubleToString(actual_tp, _Digits));
                    }
                    param_lastPositionOpenTime = TimeCurrent();
                    PrintUnifiedTrades(unified_trades, unified_trade_count, "After processing position open");

                    // Handle unified analytics for trade open
                    if(enableHttpAnalytics) {
                        double entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                        double lot_size = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                        string direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";

                        // Use unified analytics handler
                        HandleTradeAnalytics(entry_price, lot_size, direction, strategyName,
                                           param_lastMarketFeatures, param_lastTradeDirection, param_lastMLPrediction,
                                           setTradeIDCallback, tradeEntryCallback, marketConditionsCallback, mlPredictionCallback,
                                           trans.position);

                        Print("📊 Recorded analytics for trade open (unified system)");
                    }
                } else {
                    Print("⚠️ Position not ours or not entry deal - skipping");
                }
            }
        }

        // Store original trade count to detect if a position was closed
        int originalTradeCount = unified_trade_count;

        // Handle trade close transactions using unified system
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0) {
            // Find the trade in unified array
            int tradeIndex = FindUnifiedTradeByTicket(trans.position, unified_trades, unified_trade_count);
            if(tradeIndex >= 0 && unified_trades[tradeIndex].is_open) {
                Print("🔍 Position closing transaction detected - Position: ", trans.position);

                // Verify this is a closing deal
                if(HistoryDealSelect(trans.deal)) {
                    ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

                    if(deal_entry == DEAL_ENTRY_OUT) {
                        Print("✅ Position closing confirmed - processing analytics before removal");

                        // Get closing deal details for analytics and retraining
                        double close_price = 0.0;
                        double profit = 0.0;
                        double profitLossPips = 0.0;
                        datetime close_time = TimeCurrent();

                        if(HistoryDealSelect(trans.deal)) {
                            close_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                            profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                            close_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
                            // Calculate profit/loss in pips
                            if(profit != 0) {
                                double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                                profitLossPips = profit / (pointValue * 10); // Convert to pips
                            }
                        }

                        // Log trade close for ML retraining BEFORE removing from array
                        string trade_id = IntegerToString(unified_trades[tradeIndex].ticket);
                        LogTradeCloseForRetraining(trade_id, close_price, profit, profitLossPips, close_time);
                        Print("📊 Logged trade close for ML retraining");

                        // Handle trade exit analytics
                        if(enableHttpAnalytics && tradeExitCallback != NULL) {
                            tradeExitCallback(close_price, profit, profitLossPips);
                            Print("📊 Recorded trade exit analytics (unified system)");
                        }

                        // NOW remove from unified array after all processing is complete
                        RemoveUnifiedTrade(tradeIndex, unified_trades, unified_trade_count);
                        PrintUnifiedTrades(unified_trades, unified_trade_count, "After removing closed position");
                    }
                }
            }
        }

        // Handle TRADE_TRANSACTION_HISTORY_ADD for when position is moved to history after closing
        if(trans.type == TRADE_TRANSACTION_HISTORY_ADD && trans.position != 0) {
            Print("🔍 Position history add detected - Position: ", trans.position);

            // CRITICAL: Before assuming fast close, verify the position is actually closed
            // Check if position still exists in the active positions list
            bool position_still_open = false;
            int total_positions = PositionsTotal();
            for(int pos_idx = 0; pos_idx < total_positions; pos_idx++) {
                ulong pos_ticket = PositionGetTicket(pos_idx);
                if(pos_ticket == trans.position) {
                    position_still_open = true;
                    break;
                }
            }

            if(position_still_open) {
                Print("✅ Position ", trans.position, " is still OPEN - this is not a close transaction");
                Print("🔍 This was likely a TRADE_TRANSACTION_HISTORY_ADD for position tracking, not closure");
                return; // Exit early - don't process as a close
            }

            // Position has been moved to history, which means it's closed
            // Add a small delay to ensure all deals are written to history
            Sleep(100); // 100ms delay to allow deal history to be written

            // Find the trade in unified array
            int tradeIndex = FindUnifiedTradeByTicket(trans.position, unified_trades, unified_trade_count);
            if(tradeIndex >= 0 && unified_trades[tradeIndex].is_open) {
                Print("✅ Position confirmed as closed (moved to history) - removing from unified array");

                // Get closing deal information from history
                if(HistorySelectByPosition(trans.position)) {
                    int total_deals = HistoryDealsTotal();
                    Print("🔍 Found ", total_deals, " deals in history for position ", trans.position);

                    // Look for the closing deal
                    bool found_closing_deal = false;
                    for(int i = total_deals - 1; i >= 0; i--) { // Search backwards for most recent closing deal
                        ulong deal_ticket = HistoryDealGetTicket(i);
                        if(deal_ticket > 0) {
                            ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                            if(deal_entry == DEAL_ENTRY_OUT) {
                                double close_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                                double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                                datetime close_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);

                                Print("🔍 Closing deal found - Price: ", DoubleToString(close_price, _Digits),
                                      ", Profit: $", DoubleToString(profit, 2), ", Time: ", TimeToString(close_time));

                                // Handle trade exit analytics with actual closing data
                                if(enableHttpAnalytics && tradeExitCallback != NULL) {
                                    // Calculate profit/loss in pips
                                    double profitLossPips = 0.0;
                                    if(profit != 0) {
                                        double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                                        profitLossPips = profit / (pointValue * 10); // Convert to pips
                                    }

                                    tradeExitCallback(close_price, profit, profitLossPips);
                                    Print("📊 Recorded trade exit analytics from history (unified system)");
                                }

                                found_closing_deal = true;
                                break;
                            }
                        }
                    }

                    // If we still haven't found a closing deal, try to estimate from position history
                    if(!found_closing_deal) {
                        Print("⚠️ No closing deal found - attempting to estimate from position history");

                        // Get the last known position details
                        if(HistorySelectByPosition(trans.position)) {
                            int total_deals = HistoryDealsTotal();
                            if(total_deals >= 1) { // Need at least opening deal
                                // Get the opening deal (first deal)
                                ulong open_deal = HistoryDealGetTicket(0);
                                if(open_deal > 0) {
                                    double open_price = HistoryDealGetDouble(open_deal, DEAL_PRICE);
                                    double lot_size = HistoryDealGetDouble(open_deal, DEAL_VOLUME);
                                    ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(open_deal, DEAL_TYPE);

                                    // Estimate close price and profit based on deal type
                                    double close_price = 0;
                                    double profit = 0;

                                    if(deal_type == DEAL_TYPE_BUY) {
                                        // For buy deals, estimate close at current bid
                                        close_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                                        profit = (close_price - open_price) * lot_size / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                                    } else {
                                        // For sell deals, estimate close at current ask
                                        close_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                                        profit = (open_price - close_price) * lot_size / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                                    }

                                    datetime close_time = TimeCurrent();

                                    Print("🔍 Fast close estimated - Price: ", DoubleToString(close_price, _Digits), ", Profit: $", DoubleToString(profit, 2));

                                    // Handle trade exit analytics with estimated values
                                    if(enableHttpAnalytics && tradeExitCallback != NULL) {
                                        // Calculate profit/loss in pips
                                        double profitLossPips = 0.0;
                                        if(profit != 0) {
                                            double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                                            profitLossPips = profit / (pointValue * 10); // Convert to pips
                                        }

                                        tradeExitCallback(close_price, profit, profitLossPips);
                                        Print("📊 Recorded trade exit analytics with fast close estimation (unified system)");
                                    }

                                    found_closing_deal = true;
                                }
                            }
                        }

                        if(!found_closing_deal) {
                            Print("⚠️ Unable to process trade close - no closing deal found and estimation failed");
                            // Handle trade exit analytics with fallback
                            if(enableHttpAnalytics && tradeExitCallback != NULL) {
                                // Use fallback values for analytics
                                double close_price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Use current bid as estimate
                                double profit = 0.0; // Unknown profit
                                double profitLossPips = 0.0; // Unknown pips

                                tradeExitCallback(close_price, profit, profitLossPips);
                                Print("📊 Recorded trade exit analytics with fallback (unified system)");
                            }
                        }
                    }
                }

                // Remove the closed position from unified array
                RemoveUnifiedTrade(tradeIndex, unified_trades, unified_trade_count);
                PrintUnifiedTrades(unified_trades, unified_trade_count, "After removing position moved to history");
            } else {
                Print("⚠️ Position ", trans.position, " not found in unified array or already closed");
            }
        }

        // Check if any position was closed and handle analytics cleanup
        if(originalTradeCount > unified_trade_count) {
            Print("🔄 Trade count decreased from ", originalTradeCount, " to ", unified_trade_count);
            PrintUnifiedTrades(unified_trades, unified_trade_count, "After position closure");
        }
    }

private:
    //+------------------------------------------------------------------+
    //| Prepare JSON request for API using JSON library                  |
    //+------------------------------------------------------------------+
    string PrepareJsonRequest(MLFeatures &features, string direction) {
        Print("📋 Preparing JSON request - Strategy: ", config.strategy_name, ", Symbol: ", config.symbol, ", Timeframe: ", config.timeframe, ", Direction: ", direction);

                // Create JSON object using the library
        CJAVal json_request;

        // Set main properties
        json_request["strategy"] = config.strategy_name;
        json_request["symbol"] = config.symbol;
        json_request["timeframe"] = config.timeframe;
        json_request["direction"] = direction;

        // Add features directly to main request (avoiding nested object issue)
        json_request["rsi"] = features.rsi;
        json_request["stoch_main"] = features.stoch_main;
        json_request["stoch_signal"] = features.stoch_signal;
        json_request["macd_main"] = features.macd_main;
        json_request["macd_signal"] = features.macd_signal;
        json_request["bb_upper"] = features.bb_upper;
        json_request["bb_lower"] = features.bb_lower;
        json_request["williams_r"] = features.williams_r;
        json_request["cci"] = features.cci;
        json_request["momentum"] = features.momentum;
        json_request["force_index"] = features.force_index;
        json_request["volume_ratio"] = features.volume_ratio;
        json_request["price_change"] = features.price_change;
        json_request["volatility"] = features.volatility;
        json_request["spread"] = features.spread;
        json_request["session_hour"] = features.session_hour;
        json_request["is_news_time"] = features.is_news_time;
        json_request["day_of_week"] = features.day_of_week;
        json_request["month"] = features.month;

        // Add trade calculation features (required for enhanced endpoint)
        json_request["current_price"] = features.current_price;
        json_request["atr"] = features.atr;
        json_request["account_balance"] = features.account_balance;
        json_request["risk_per_pip"] = features.risk_per_pip;

        // Serialize to string
        string json_string;
        json_request.Serialize(json_string);

        Print("📊 JSON length: ", StringLen(json_string), " characters");
        Print("✅ JSON created successfully using JSON library");

        return json_string;
    }

    // Parse JSON response from API using JSON library
    MLPrediction ParseJsonResponse(string response) {
        Print("🔍 Parsing JSON response using JSON library");

        MLPrediction prediction;
        prediction.is_valid = false;
        prediction.timestamp = TimeCurrent();

        // Parse JSON using the library
        CJAVal json_response;
        if(!json_response.Deserialize(response)) {
            prediction.error_message = "Failed to deserialize JSON response";
            return prediction;
        }

        // Check status
        if(json_response["status"].ToStr() != "success") {
            prediction.error_message = "API returned status: " + json_response["status"].ToStr();
            if(json_response["message"].ToStr() != "") {
                prediction.error_message += " - " + json_response["message"].ToStr();
            }
            return prediction;
        }

        // Extract prediction data
        CJAVal prediction_obj = json_response["prediction"];

        prediction.direction = prediction_obj["direction"].ToStr();
        prediction.probability = prediction_obj["probability"].ToDbl();
        prediction.confidence = prediction_obj["confidence"].ToDbl();
        prediction.model_type = prediction_obj["model_type"].ToStr();
        prediction.model_key = prediction_obj["model_key"].ToStr();

        // Validate essential fields
        if(StringLen(prediction.direction) > 0 &&
           prediction.confidence > 0 &&
           prediction.probability > 0) {
            prediction.is_valid = true;
            prediction.error_message = "";

            Print("✅ JSON parsing successful using library");
            Print("   Direction: ", prediction.direction);
            Print("   Probability: ", DoubleToString(prediction.probability, 4));
            Print("   Confidence: ", DoubleToString(prediction.confidence, 4));
            Print("   Model Type: ", prediction.model_type);
            Print("   Model Key: ", prediction.model_key);
        } else {
            prediction.error_message = "Missing essential prediction fields";
            Print("❌ JSON parsing failed: ", prediction.error_message);
        }

        return prediction;
    }

    // Parse enhanced JSON response from /trade_decision endpoint
    MLPrediction ParseEnhancedJsonResponse(string response) {
        Print("🔍 Parsing enhanced JSON response using JSON library");

        MLPrediction prediction;
        prediction.is_valid = false;
        prediction.timestamp = TimeCurrent();

        // Parse JSON using the library
        CJAVal json_response;
        if(!json_response.Deserialize(response)) {
            prediction.error_message = "Failed to deserialize enhanced JSON response";
            return prediction;
        }

        // Check status
        if(json_response["status"].ToStr() != "success") {
            prediction.error_message = "API returned status: " + json_response["status"].ToStr();
            if(json_response["message"].ToStr() != "") {
                prediction.error_message += " - " + json_response["message"].ToStr();
            }
            return prediction;
        }

                // Extract enhanced prediction data
        CJAVal prediction_obj = json_response["prediction"];

        prediction.direction = prediction_obj["direction"].ToStr();
        prediction.probability = prediction_obj["probability"].ToDbl();
        prediction.confidence = prediction_obj["confidence"].ToDbl();
        prediction.model_type = prediction_obj["model_type"].ToStr();
        prediction.model_key = prediction_obj["model_key"].ToStr();

        // Extract enhanced fields
        prediction.should_trade = json_response["should_trade"].ToInt() == 1;  // Convert int (0/1) to bool
        prediction.confidence_threshold = json_response["confidence_threshold"].ToDbl();

        // Validate essential fields
        if(StringLen(prediction.direction) > 0 &&
           prediction.confidence > 0 &&
           prediction.probability > 0) {
            prediction.is_valid = true;
            prediction.error_message = "";

            Print("✅ Enhanced JSON parsing successful using library");
            Print("   Direction: ", prediction.direction);
            Print("   Probability: ", DoubleToString(prediction.probability, 4));
            Print("   Confidence: ", DoubleToString(prediction.confidence, 4));
            Print("   Model Type: ", prediction.model_type);
            Print("   Model Key: ", prediction.model_key);
            Print("   Should Trade: ", prediction.should_trade ? "Yes" : "No");
            Print("   Confidence Threshold: ", DoubleToString(prediction.confidence_threshold, 4));
        } else {
            prediction.error_message = "Missing essential prediction fields";
            Print("❌ Enhanced JSON parsing failed: ", prediction.error_message);
        }

        return prediction;
    }

    //+------------------------------------------------------------------+
    //| Get current timeframe as string                                  |
    //| This is the inverse of StringToTimeframe()                       |
    //+------------------------------------------------------------------+
    string GetCurrentTimeframeString() {
        switch(_Period) {
            case PERIOD_M1:  return "M1";
            case PERIOD_M5:  return "M5";
            case PERIOD_M15: return "M15";
            case PERIOD_M30: return "M30";
            case PERIOD_H1:  return "H1";
            case PERIOD_H4:  return "H4";
            case PERIOD_D1:  return "D1";
            case PERIOD_W1:  return "W1";
            case PERIOD_MN1: return "MN1";
            default:         return "H1";
        }
    }

public:
    //+------------------------------------------------------------------+
    //| Scan for existing open positions and add to tracking system      |
    //+------------------------------------------------------------------+
    void ScanForExistingOpenPositions(string ea_identifier, int maxCapacity,
                                     TradeEntryCallback tradeEntryCallback,
                                     MarketConditionsCallback marketConditionsCallback,
                                     bool enableAnalytics = true,
                                     string strategy_name = "Unknown",
                                     SetTradeIDCallback setTradeIDCallback = NULL) {
        Print("🔍 Scanning for existing open positions with EA identifier: '", ea_identifier, "'");

        int total_positions = PositionsTotal();
        int found_positions = 0;

        for(int pos_idx = 0; pos_idx < total_positions; pos_idx++) {
            ulong pos_ticket = PositionGetTicket(pos_idx);
            if(pos_ticket <= 0) continue;

            // Get position details
            if(PositionSelectByTicket(pos_ticket)) {
                string comment = PositionGetString(POSITION_COMMENT);
                string symbol = PositionGetString(POSITION_SYMBOL);
                double volume = PositionGetDouble(POSITION_VOLUME);
                double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
                ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

                // Check if this position belongs to our EA
                if(StringFind(comment, ea_identifier) >= 0) {
                    Print("✅ Found existing position: Ticket ", pos_ticket, ", Symbol: ", symbol,
                          ", Type: ", (pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          ", Volume: ", DoubleToString(volume, 2),
                          ", Open Price: ", DoubleToString(open_price, _Digits),
                          ", Open Time: ", TimeToString(open_time));

                    // Check if we can track more trades
                    if(!CanTrackMoreTrades(maxCapacity)) {
                        Print("❌ Cannot track position ", pos_ticket, " - array is full (", unified_trade_count, "/", maxCapacity, ")");
                        continue;
                    }

                    // Create unified trade data for this existing position
                    UnifiedTradeData existing_trade;
                    existing_trade.ticket = pos_ticket;
                    existing_trade.direction = (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                    existing_trade.timeframe = config.timeframe;  // Set current timeframe
                    existing_trade.entry_price = open_price;
                    existing_trade.lot_size = volume;
                    existing_trade.opened_time = open_time;
                    existing_trade.is_open = true;
                    existing_trade.stop_loss = 0.0; // Unknown for existing positions
                    existing_trade.take_profit = 0.0; // Unknown for existing positions
                    existing_trade.is_logged = false; // Not logged yet
                    existing_trade.created_time = open_time; // Use open time as created time
                    existing_trade.last_monitoring_check = 0; // Initialize monitoring timestamp
                    existing_trade.monitoring_enabled = false; // Will be enabled when monitoring starts

                    // For existing positions, we don't have the original ML prediction/features
                    // Create default/empty prediction and features
                    MLPrediction default_prediction;
                    default_prediction.model_key = "existing_position_no_ml_data";
                    default_prediction.direction = (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                    default_prediction.probability = 0.5; // Neutral
                    default_prediction.confidence = 0.0; // No confidence
                    default_prediction.is_valid = false;

                    MLFeatures default_features;
                    // Initialize with current market features if possible
                    CollectMarketFeatures(default_features);

                    existing_trade.prediction = default_prediction;
                    existing_trade.features = default_features;

                    // Add to unified tracking system
                    AddUnifiedTrade(unified_trades, unified_trade_count, existing_trade, maxCapacity);
                    found_positions++;

                                        // Try to record analytics for this existing position
                    if(enableAnalytics) {
                        Print("📊 Attempting to record analytics for existing position ", pos_ticket);

                        // Set the analytics trade ID to the position ticket before recording analytics
                        if(setTradeIDCallback != NULL) {
                            setTradeIDCallback(pos_ticket);
                            Print("🔧 Set analytics trade ID to position ticket: ", pos_ticket);
                        } else {
                            Print("⚠️ No SetTradeIDCallback available - analytics may fail");
                        }

                        // Record trade entry analytics
                        if(tradeEntryCallback != NULL) {
                            // Use current market data for SL/TP estimates
                            double current_bid = SymbolInfoDouble(symbol, SYMBOL_BID);
                            double current_ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
                            double estimated_sl = (pos_type == POSITION_TYPE_BUY) ? current_bid * 0.99 : current_ask * 1.01; // Rough estimate
                            double estimated_tp = (pos_type == POSITION_TYPE_BUY) ? current_ask * 1.01 : current_bid * 0.99; // Rough estimate

                            tradeEntryCallback(existing_trade.direction, existing_trade.entry_price,
                                             estimated_sl, estimated_tp, existing_trade.lot_size,
                                             strategy_name, "1.00"); // Use passed strategy name
                            Print("✅ Recorded trade entry analytics for existing position");
                        }

                        // Try to collect and record market conditions
                        if(marketConditionsCallback != NULL) {
                            MLFeatures features;
                            CollectMarketFeatures(features);
                            marketConditionsCallback(features);
                            Print("✅ Recorded market conditions for existing position");
                        }
                    }
                }
            }
        }

        Print("🔍 Scan complete: Found ", found_positions, " existing positions for EA '", ea_identifier, "'");
        Print("📊 Total tracked positions: ", unified_trade_count, "/", maxCapacity);

        if(found_positions > 0) {
            PrintUnifiedTradeArrayStatus(maxCapacity);
            PrintDetailedTrackedPositions();
        }
    }

    //+------------------------------------------------------------------+
    //| Print detailed status of all tracked positions                   |
    //+------------------------------------------------------------------+
    void PrintDetailedTrackedPositions() {
        Print("🔍 Detailed Tracked Positions Status:");
        Print("   Total tracked: ", unified_trade_count);

        if(unified_trade_count == 0) {
            Print("   No positions currently tracked");
            return;
        }

        for(int i = 0; i < unified_trade_count; i++) {
            Print("   [", i, "] Ticket: ", unified_trades[i].ticket,
                  ", Direction: ", unified_trades[i].direction,
                  ", Lot: ", DoubleToString(unified_trades[i].lot_size, 2),
                  ", Entry: ", DoubleToString(unified_trades[i].entry_price, _Digits),
                  ", Open Time: ", TimeToString(unified_trades[i].opened_time),
                  ", Status: ", unified_trades[i].is_open ? "OPEN" : "CLOSED",
                  ", Created: ", TimeToString(unified_trades[i].created_time),
                  ", Model: ", unified_trades[i].prediction.model_key,
                  ", ML Valid: ", unified_trades[i].prediction.is_valid ? "Yes" : "No");
        }
    }

};

    //+------------------------------------------------------------------+
    //| Prepare JSON request for active trade recommendation              |
    //+------------------------------------------------------------------+
    string PrepareActiveTradeJsonRequest(MLFeatures &features, string trade_direction,
                                       double entry_price, double current_price,
                                       int trade_duration_minutes, double current_profit_pips,
                                       double account_balance, double current_profit_money) {
        string json = "{";

        // Add trade-specific data
        json += "\"trade_direction\":\"" + trade_direction + "\",";
        json += "\"entry_price\":" + DoubleToString(entry_price, _Digits) + ",";
        json += "\"current_price\":" + DoubleToString(current_price, _Digits) + ",";
        json += "\"trade_duration_minutes\":" + IntegerToString(trade_duration_minutes) + ",";
        json += "\"current_profit_pips\":" + DoubleToString(current_profit_pips, 1) + ",";
        json += "\"account_balance\":" + DoubleToString(account_balance, 2) + ",";
        json += "\"current_profit_money\":" + DoubleToString(current_profit_money, 2) + ",";

        // Add market features
        json += "\"features\":{";
        json += "\"symbol\":\"" + config.symbol + "\",";
        json += "\"timeframe\":\"" + config.timeframe + "\",";
        json += "\"current_price\":" + DoubleToString(current_price, _Digits) + ",";
        json += "\"atr\":" + DoubleToString(features.atr, _Digits) + ",";
        json += "\"rsi\":" + DoubleToString(features.rsi, 2) + ",";
        json += "\"macd\":" + DoubleToString(features.macd, _Digits) + ",";
        json += "\"macd_signal\":" + DoubleToString(features.macd_signal, _Digits) + ",";
        json += "\"macd_histogram\":" + DoubleToString(features.macd_histogram, _Digits) + ",";
        json += "\"bollinger_upper\":" + DoubleToString(features.bollinger_upper, _Digits) + ",";
        json += "\"bollinger_middle\":" + DoubleToString(features.bollinger_middle, _Digits) + ",";
        json += "\"bollinger_lower\":" + DoubleToString(features.bollinger_lower, _Digits) + ",";
        json += "\"volume\":" + DoubleToString(features.volume, 0) + ",";
        json += "\"spread\":" + DoubleToString(features.spread, _Digits);
        json += "}";

        json += "}";

        return json;
    }

    //+------------------------------------------------------------------+
    //| Parse response from active trade recommendation endpoint          |
    //+------------------------------------------------------------------+
    MLPrediction ParseActiveTradeResponse(string response) {
        MLPrediction prediction;
        prediction.is_valid = false;

        // Reset prediction
        prediction.model_key = "";
        prediction.direction = "";
        prediction.probability = 0.0;
        prediction.confidence = 0.0;
        prediction.error_message = "";

        if(StringLen(response) == 0) {
            prediction.error_message = "Empty response received";
            return prediction;
        }

        // Use JSON library for proper parsing
        CJAVal json_response;
        if(!json_response.Deserialize(response)) {
            prediction.error_message = "Failed to deserialize JSON response";
            Print("❌ JSON deserialization failed for response: ", response);
            return prediction;
        }

        // Check status
        if(json_response["status"].ToStr() != "success") {
            prediction.error_message = "API returned status: " + json_response["status"].ToStr();
            if(json_response["message"].ToStr() != "") {
                prediction.error_message += " - " + json_response["message"].ToStr();
            }
            return prediction;
        }

        // Extract should_trade value
        if(json_response["should_trade"].ToInt() == 0) {
            prediction.error_message = "Trade not recommended";
            return prediction;
        }

        // Extract prediction data
        CJAVal prediction_obj = json_response["prediction"];
        if(prediction_obj.IsValid()) {
            prediction.probability = prediction_obj["probability"].ToDbl();
            prediction.confidence = prediction_obj["confidence"].ToDbl();
            prediction.model_key = prediction_obj["model_key"].ToStr();
            prediction.model_type = prediction_obj["model_type"].ToStr();
            prediction.direction = prediction_obj["direction"].ToStr();

            // Debug logging
            Print("🔍 Parsed prediction data:");
            Print("   Probability: ", DoubleToString(prediction.probability, 3));
            Print("   Confidence: ", DoubleToString(prediction.confidence, 3));
            Print("   Model Key: ", prediction.model_key);
            Print("   Model Type: ", prediction.model_type);
            Print("   Direction: ", prediction.direction);
        } else {
            prediction.error_message = "Missing prediction object in response";
            Print("❌ Prediction object not found in JSON response");
            return prediction;
        }

        // Extract ML analysis data if available
        CJAVal ml_analysis = json_response["ml_analysis"];
        bool ml_available = false;
        string analysis_method = "unknown";

        if(ml_analysis.IsValid()) {
            ml_available = ml_analysis["ml_prediction_available"].ToBool();
            analysis_method = ml_analysis["analysis_method"].ToStr();

            // Debug logging
            Print("🔍 Parsed ML analysis data:");
            Print("   ML Available: ", ml_available ? "Yes" : "No");
            Print("   Analysis Method: ", analysis_method);
        } else {
            Print("⚠️ ML analysis section not found in JSON response");
        }

        // Determine if prediction is valid
        // A valid prediction should have reasonable values (probability and confidence can be 0 for close recommendations)
        if(prediction.probability >= 0 && prediction.probability <= 1 &&
           prediction.confidence >= 0 && prediction.confidence <= 1 &&
           prediction.model_key != "" && prediction.model_type != "") {

            prediction.is_valid = true;
            prediction.error_message = "";

            // Log the analysis method used
            if(ml_available) {
                Print("✅ Active trade recommendation: ML-enhanced analysis (", analysis_method, ")");
            } else {
                Print("✅ Active trade recommendation: Trade health analysis only (", analysis_method, ")");
                Print("   This is normal when no suitable ML model is available");
            }
        } else {
            prediction.error_message = "Invalid prediction data - probability: " + DoubleToString(prediction.probability, 3) +
                                    ", confidence: " + DoubleToString(prediction.confidence, 3) +
                                    ", model_key: " + prediction.model_key +
                                    ", model_type: " + prediction.model_type;
        }

        return prediction;
    }

        //+------------------------------------------------------------------+
    //| Get open positions from unified trade tracking system           |
    //+------------------------------------------------------------------+
    int GetOpenPositionsFromUnifiedSystem(UnifiedTradeData& openPositions[], int maxCapacity) {
        int openCount = 0;

        for(int i = 0; i < unified_trade_count && openCount < maxCapacity; i++) {
            if(unified_trades[i].is_open && unified_trades[i].ticket > 0) {
                openPositions[openCount] = unified_trades[i];
                openCount++;
            }
        }

        return openCount;
    }

    //+------------------------------------------------------------------+
    //| Get open positions filtered by timeframe                        |
    //+------------------------------------------------------------------+
    int GetOpenPositionsByTimeframe(UnifiedTradeData& openPositions[], int maxCapacity, string targetTimeframe) {
        int openCount = 0;

        for(int i = 0; i < unified_trade_count && openCount < maxCapacity; i++) {
            if(unified_trades[i].is_open && unified_trades[i].ticket > 0 &&
               unified_trades[i].timeframe == targetTimeframe) {
                openPositions[openCount] = unified_trades[i];
                openCount++;
            }
        }

        return openCount;
    }

    //+------------------------------------------------------------------+
    //| Enable monitoring for trades on a specific timeframe            |
    //+------------------------------------------------------------------+
    void EnableMonitoringForTimeframe(string targetTimeframe) {
        for(int i = 0; i < unified_trade_count; i++) {
            if(unified_trades[i].timeframe == targetTimeframe) {
                unified_trades[i].monitoring_enabled = true;
                unified_trades[i].last_monitoring_check = 0; // Reset check timer
            }
        }
        Print("✅ Enabled monitoring for timeframe: ", targetTimeframe);
    }

    //+------------------------------------------------------------------+
    //| Check if monitoring is needed for a specific timeframe          |
    //+------------------------------------------------------------------+
    bool ShouldMonitorTimeframe(string targetTimeframe, int checkIntervalMinutes) {
        datetime currentTime = TimeCurrent();

        for(int i = 0; i < unified_trade_count; i++) {
            if(unified_trades[i].timeframe == targetTimeframe &&
               unified_trades[i].monitoring_enabled &&
               unified_trades[i].is_open) {

                // Check if enough time has passed since last monitoring
                if(currentTime - unified_trades[i].last_monitoring_check >= checkIntervalMinutes * 60) {
                    return true;
                }
            }
        }
        return false;
    }

    //+------------------------------------------------------------------+
    //| Update monitoring timestamp for a specific position             |
    //+------------------------------------------------------------------+
    void UpdatePositionMonitoringTimestamp(ulong ticket, datetime timestamp) {
        for(int i = 0; i < unified_trade_count; i++) {
            if(unified_trades[i].ticket == ticket) {
                unified_trades[i].last_monitoring_check = timestamp;
                break;
            }
        }
    }

        //+------------------------------------------------------------------+
    //| Check for candle close and monitor active trades               |
    //+------------------------------------------------------------------+
    void CheckCandleCloseAndMonitorTrades(string& lastCandleCloseTime, string currentTimeframe,
                                         int activeTradeCheckMinutes, bool enableTrading,
                                         double accountBalance, int maxTrackedPositions,
                                         string symbol, int digits) {
        // Get current candle time
        datetime currentCandleTime = iTime(symbol, StringToTimeframe(currentTimeframe), 0);

        // Check if we have a new candle (candle close detected)
        if(currentCandleTime != StringToInteger(lastCandleCloseTime)) {
            Print("🕯️ New candle detected at ", TimeToString(currentCandleTime), " - enabling active trade monitoring for ", currentTimeframe);
            lastCandleCloseTime = IntegerToString(currentCandleTime);

            // Enable monitoring for this specific timeframe
            EnableMonitoringForTimeframe(currentTimeframe);
        }

        // Check if we should monitor trades for this timeframe
        if(ShouldMonitorTimeframe(currentTimeframe, activeTradeCheckMinutes)) {
            MonitorActiveTrades(currentTimeframe, enableTrading, accountBalance, maxTrackedPositions, symbol, digits);
        }
    }

        //+------------------------------------------------------------------+
    //| Convert timeframe string to ENUM_TIMEFRAMES                     |
    //| This is the inverse of GetCurrentTimeframeString()              |
    //+------------------------------------------------------------------+
    ENUM_TIMEFRAMES StringToTimeframe(string timeframe) {
        if(timeframe == "M1") return PERIOD_M1;
        if(timeframe == "M5") return PERIOD_M5;
        if(timeframe == "M15") return PERIOD_M15;
        if(timeframe == "M30") return PERIOD_M30;
        if(timeframe == "H1") return PERIOD_H1;
        if(timeframe == "H4") return PERIOD_H4;
        if(timeframe == "D1") return PERIOD_D1;
        if(timeframe == "W1") return PERIOD_W1;
        if(timeframe == "MN1") return PERIOD_MN1;

        // Default to H1 if unknown (same as GetCurrentTimeframeString default)
        Print("⚠️ Unknown timeframe: ", timeframe, " - defaulting to H1");
        return PERIOD_H1;
    }

    //+------------------------------------------------------------------+
    //| Monitor active trades for health and recommendations            |
    //+------------------------------------------------------------------+
    void MonitorActiveTrades(string timeframe, bool enableTrading, double accountBalance,
                             int maxTrackedPositions, string symbol, int digits) {
        Print("🔍 Monitoring active trades for health and recommendations on ", timeframe, "...");

        // Get current market features for the request
        MLFeatures features;
        CollectMarketFeatures(features);

        if(accountBalance <= 0) {
            Print("❌ Invalid account balance, skipping active trade monitoring");
            return;
        }

        // Get open positions from the unified trade tracking system for this specific timeframe
        UnifiedTradeData openPositions[100]; // Temporary array for open positions
        int openCount = GetOpenPositionsByTimeframe(openPositions, 100, timeframe);

        if(openCount == 0) {
            Print("ℹ️ No open positions found in unified tracking system for timeframe ", timeframe);
            return;
        }

        Print("🔍 Found ", openCount, " open position(s) in unified tracking system for timeframe ", timeframe);

        int totalPositions = 0;
        int positionsToClose = 0;
        datetime currentTime = TimeCurrent();

        // Analyze each open position
        for(int i = 0; i < openCount; i++) {
            UnifiedTradeData& position = openPositions[i];

            if(position.ticket > 0) {
                totalPositions++;

                // Get current market price for this position
                double currentPrice = (position.direction == "BUY") ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

                // Calculate profit/loss in pips
                double profitLossPips = 0;
                if(position.direction == "BUY") {
                    profitLossPips = (currentPrice - position.entry_price) / SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
                } else {
                    profitLossPips = (position.entry_price - currentPrice) / SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
                }

                // Calculate trade duration in minutes
                int durationMinutes = (int)((currentTime - position.opened_time) / 60);

                // Get current profit/loss from MT5 (if position is still open)
                double profitLoss = 0;
                if(PositionSelectByTicket(position.ticket)) {
                    profitLoss = PositionGetDouble(POSITION_PROFIT);
                }

                Print("📊 Analyzing Position ", position.ticket, " (", symbol, " ", position.direction, "):");
                Print("   Entry Price: ", DoubleToString(position.entry_price, digits));
                Print("   Current Price: ", DoubleToString(currentPrice, digits));
                Print("   Duration: ", durationMinutes, " minutes");
                Print("   Profit/Loss: $", DoubleToString(profitLoss, 2), " (", DoubleToString(profitLossPips, 1), " pips)");
                Print("   Profit %: ", DoubleToString((profitLoss / accountBalance) * 100, 3), "%");

                // Get active trade recommendation from ML service
                MLPrediction recommendation = GetActiveTradeRecommendation(
                    features,
                    position.direction,
                    position.entry_price,
                    currentPrice,
                    durationMinutes,
                    profitLossPips,
                    accountBalance,
                    profitLoss
                );

                if(recommendation.is_valid) {
                    Print("   ML Recommendation: ", recommendation.should_trade ? "CONTINUE" : "CLOSE");
                    Print("   ML Confidence: ", DoubleToString(recommendation.confidence, 3));
                    Print("   ML Probability: ", DoubleToString(recommendation.probability, 3));
                    Print("   Model Key: ", recommendation.model_key);
                    Print("   Model Type: ", recommendation.model_type);

                    // Check if this is a fallback analysis (no ML model available)
                    if(recommendation.model_type == "trade_health" || recommendation.model_key == "active_trade_analysis") {
                        Print("   ℹ️ Using trade health analysis (no suitable ML model found)");
                        Print("   ℹ️ This is normal and expected for some market conditions");
                    }

                    // Act on recommendation if confidence is high enough
                    if(recommendation.confidence >= 0.7) {
                        if(!recommendation.should_trade && recommendation.confidence >= 0.8) {
                            // High confidence recommendation to close
                            Print("🚨 High confidence recommendation to CLOSE position ", position.ticket);
                            positionsToClose++;

                            if(enableTrading) {
                                // Close the position
                                MqlTradeRequest closeRequest = {};
                                closeRequest.action = TRADE_ACTION_DEAL;
                                closeRequest.position = position.ticket;
                                closeRequest.symbol = symbol;
                                closeRequest.volume = position.lot_size;
                                closeRequest.type = (position.direction == "BUY") ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                                closeRequest.price = currentPrice;
                                closeRequest.deviation = 5;
                                closeRequest.comment = "ML_ActiveTrade_Close";

                                MqlTradeResult closeResult = {};
                                if(OrderSend(closeRequest, closeResult)) {
                                    if(closeResult.retcode == TRADE_RETCODE_DONE) {
                                        Print("✅ Position ", position.ticket, " closed based on ML recommendation");
                                    } else {
                                        Print("❌ Failed to close position ", position.ticket, ": ", closeResult.retcode);
                                    }
                                } else {
                                    Print("❌ OrderSend failed for position ", position.ticket);
                                }
                            } else {
                                Print("ℹ️ Trading disabled - would close position ", position.ticket, " based on ML recommendation");
                            }
                        } else {
                            Print("✅ Position ", position.ticket, " should continue based on ML recommendation");
                        }
                    } else {
                        Print("ℹ️ ML confidence too low (", DoubleToString(recommendation.confidence, 3), ") - no action taken");
                    }
                } else {
                    Print("❌ Failed to get ML recommendation: ", recommendation.error_message);

                    // Check if this is a "No suitable model found" scenario
                    if(StringFind(recommendation.error_message, "No suitable model found") != -1) {
                        Print("   ℹ️ No suitable ML model found - this is normal for some market conditions");
                        Print("   ℹ️ The system will continue to monitor using basic trade health metrics");
                        Print("   ℹ️ Position will be re-evaluated on next monitoring cycle");
                    }
                }
                Print(""); // Empty line for readability
            }
        }

        if(totalPositions == 0) {
            Print("ℹ️ No open positions found for timeframe ", timeframe);
        } else {
            Print("✅ Monitored ", totalPositions, " active position(s) on timeframe ", timeframe);
            if(positionsToClose > 0) {
                Print("🚨 Recommended closing ", positionsToClose, " position(s) based on ML analysis");
            }
        }

        // Update monitoring timestamps for all monitored positions
        for(int i = 0; i < openCount; i++) {
            if(openPositions[i].ticket > 0) {
                UpdatePositionMonitoringTimestamp(openPositions[i].ticket, currentTime);
            }
        }

        Print("✅ Updated monitoring timestamps for ", openCount, " position(s)");
    }

    // Global instance
MLHttpInterface g_ml_interface;
