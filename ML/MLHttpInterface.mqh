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

    // Additional features can be added as needed
};

//+------------------------------------------------------------------+
//| HTTP-based Machine Learning Interface Class                       |
//+------------------------------------------------------------------+
class MLHttpInterface {
public:
    MLConfig config;  // Make config public for easy access
private:
    MLPrediction last_prediction;
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
                    prediction.error_message = "HTTP request failed with code: " + IntegerToString(res);
            }

            Print("❌ HTTP request failed: ", res, " - ", prediction.error_message);
        }

        return prediction;
    }

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

    // Adjust stop loss based on ML prediction
    double AdjustStopLoss(double base_stop_loss, MLPrediction &prediction, string direction) {
        if(!prediction.is_valid) {
            return base_stop_loss;
        }

        // Simple adjustment based on confidence
        double adjustment_factor = 1.0 + (prediction.confidence - 0.5) * 0.2; // ±10% adjustment

        if(direction == "buy") {
            return base_stop_loss * adjustment_factor;
        } else if(direction == "sell") {
            return base_stop_loss / adjustment_factor;
        }

        return base_stop_loss;
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
        json_request["ml_model_type"] = prediction.model_type;
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
    typedef void (*MLPredictionCallback)(string model_name, string direction, double probability, double confidence, string features_json);
    typedef void (*SetTradeIDCallback)(ulong position_ticket);
    typedef void (*TradeExitCallback)(double close_price, double profit, double profitLossPips);

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

        // Validate features
        ValidateFeatures(features);

        Print("✅ Features collected - RSI: ", DoubleToString(features.rsi, 2),
              ", MACD: ", DoubleToString(features.macd_main, 2),
              ", BB_Upper: ", DoubleToString(features.bb_upper, _Digits),
              ", Price Change: ", DoubleToString(features.price_change * 100, 3), "%");
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
           !MathIsValidNumber(features.spread)) {

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
        }
    }

    //+------------------------------------------------------------------+
    //| Unified analytics handler using individual callbacks             |
    //+------------------------------------------------------------------+
    void HandleTradeAnalytics(double entry_price, double lot_size, string direction, string strategy_name,
                             MLFeatures& lastMarketFeatures, string& lastTradeDirection, MLPrediction& lastMLPrediction,
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
        if(lastMarketFeatures.rsi != 0 && marketConditionsCallback != NULL) {
            marketConditionsCallback(lastMarketFeatures);
            Print("✅ Recorded market conditions analytics");
        }

        // Record ML prediction if we have stored data
        if(lastTradeDirection != "" && mlPredictionCallback != NULL) {
            // Record ML prediction with features JSON
            string model_name = (lastTradeDirection == "BUY") ? "buy_model_improved" : "sell_model_improved";
            string features_json = CreateFeatureJSON(lastMarketFeatures, lastTradeDirection);
            mlPredictionCallback(model_name, StringToLower(lastTradeDirection), lastMLPrediction.probability, lastMLPrediction.confidence, features_json);
            Print("✅ Recorded ML prediction analytics with features");

            // Clear stored data
            lastTradeDirection = "";
        }
    }

    //+------------------------------------------------------------------+
    //| Complete OnTradeTransaction handler - for simple EAs            |
    //+------------------------------------------------------------------+
    void HandleCompleteTradeTransaction(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result,
                            ulong& lastKnownPositionTicket,
                            datetime& lastPositionOpenTime,
                            string& lastTradeID,
                            bool& pendingTradeData,
                            bool enableHttpAnalytics,
                            string eaIdentifier,
                            string strategyName,
                            MLPrediction& pendingPrediction,
                            MLFeatures& pendingFeatures,
                            string& pendingDirection,
                            double pendingEntry,
                            double pendingStopLoss,
                            double pendingTakeProfit,
                            double pendingLotSize,
                            MLPrediction& lastMLPrediction,
                            MLFeatures& lastMarketFeatures,
                            string& lastTradeDirection,
                            SetTradeIDCallback setTradeIDCallback,
                            TradeEntryCallback tradeEntryCallback,
                            MarketConditionsCallback marketConditionsCallback,
                            MLPredictionCallback mlPredictionCallback,
                            TradeExitCallback tradeExitCallback) {

        Print("🔄 OnTradeTransaction() called - Transaction type: ", EnumToString(trans.type));
        Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);

        // Handle trade open transactions
        HandleTradeOpenTransaction(trans, lastKnownPositionTicket, lastPositionOpenTime,
                                 lastTradeID, pendingTradeData, enableHttpAnalytics, eaIdentifier,
                                 strategyName, pendingPrediction, pendingFeatures,
                                 pendingDirection, pendingEntry, pendingStopLoss, pendingTakeProfit, pendingLotSize);

        // Handle unified analytics after trade open
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0 && lastKnownPositionTicket == trans.position) {
            if(enableHttpAnalytics && HistoryDealSelect(trans.deal)) {
                double entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                double lot_size = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                string direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";

                // Use unified analytics handler
                HandleTradeAnalytics(entry_price, lot_size, direction, strategyName,
                                   lastMarketFeatures, lastTradeDirection, lastMLPrediction,
                                   setTradeIDCallback, tradeEntryCallback, marketConditionsCallback, mlPredictionCallback,
                                   lastKnownPositionTicket);
            }
        }

        // Handle trade close transactions
        HandleTradeCloseTransaction(trans, lastKnownPositionTicket, lastPositionOpenTime,
                                  lastTradeID, pendingTradeData, enableHttpAnalytics, eaIdentifier, tradeExitCallback);
    }

    //+------------------------------------------------------------------+
    //| Complete OnTradeTransaction handler - for BreakoutStrategy EA   |
    //+------------------------------------------------------------------+
    void HandleCompleteTradeTransactionWithPosition(const MqlTradeTransaction& trans,
                                        const MqlTradeRequest& request,
                                        const MqlTradeResult& result,
                                        ulong& lastKnownPositionTicket,
                                        datetime& lastPositionOpenTime,
                                        string& lastTradeID,
                                        bool& pendingTradeData,
                                        bool enableHttpAnalytics,
                                        string eaIdentifier,
                                        string strategyName,
                                        MLPrediction& pendingPrediction,
                                        MLFeatures& pendingFeatures,
                                        string& pendingDirection,
                                        double pendingEntry,
                                        double pendingStopLoss,
                                        double pendingTakeProfit,
                                        double pendingLotSize,
                                        MLPrediction& lastMLPrediction,
                                        MLFeatures& lastMarketFeatures,
                                        string& lastTradeDirection,
                                        bool& hasOpenPosition,
                                        SetTradeIDCallback setTradeIDCallback,
                                        TradeEntryCallback tradeEntryCallback,
                                        MarketConditionsCallback marketConditionsCallback,
                                        MLPredictionCallback mlPredictionCallback,
                                        TradeExitCallback tradeExitCallback) {

        Print("🔄 OnTradeTransaction() called - Transaction type: ", EnumToString(trans.type));
        Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);

        // Handle trade open transactions
        HandleTradeOpenTransaction(trans, lastKnownPositionTicket, lastPositionOpenTime,
                                 lastTradeID, pendingTradeData, enableHttpAnalytics, eaIdentifier,
                                 strategyName, pendingPrediction, pendingFeatures,
                                 pendingDirection, pendingEntry, pendingStopLoss, pendingTakeProfit, pendingLotSize);

        // Handle BreakoutStrategy-specific logic after trade open
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0 && lastKnownPositionTicket == trans.position) {
            hasOpenPosition = true;

            // Handle unified analytics after trade open
            if(enableHttpAnalytics && HistoryDealSelect(trans.deal)) {
                double entry_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                double lot_size = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
                string direction = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";

                // Use unified analytics handler
                HandleTradeAnalytics(entry_price, lot_size, direction, strategyName,
                                   lastMarketFeatures, lastTradeDirection, lastMLPrediction,
                                   setTradeIDCallback, tradeEntryCallback, marketConditionsCallback, mlPredictionCallback,
                                   lastKnownPositionTicket);
            }
        }

        // Store the original position ticket to check if trade was closed
        ulong originalPositionTicket = lastKnownPositionTicket;

        // Handle trade close transactions
        HandleTradeCloseTransaction(trans, lastKnownPositionTicket, lastPositionOpenTime,
                                  lastTradeID, pendingTradeData, enableHttpAnalytics, eaIdentifier, tradeExitCallback);

        // Handle BreakoutStrategy-specific logic after trade close
        if(originalPositionTicket != 0 && lastKnownPositionTicket == 0) {
            // Position was closed and reset by utility function
            hasOpenPosition = false;
            Print("🔄 Updated hasOpenPosition status after trade close");
        }
    }

    //+------------------------------------------------------------------+
    //| Handle trade open transactions - utility function for EAs        |
    //+------------------------------------------------------------------+
    void HandleTradeOpenTransaction(const MqlTradeTransaction& trans,
                                   ulong& lastKnownPositionTicket,
                                   datetime& lastPositionOpenTime,
                                   string& lastTradeID,
                                   bool& pendingTradeData,
                                   bool enableHttpAnalytics,
                                   string eaIdentifier,
                                   string strategyName,
                                   MLPrediction& pendingPrediction,
                                   MLFeatures& pendingFeatures,
                                   string& pendingDirection,
                                   double pendingEntry,
                                   double pendingStopLoss,
                                   double pendingTakeProfit,
                                   double pendingLotSize) {

        Print("🔄 HandleTradeOpenTransaction() called - Transaction type: ", EnumToString(trans.type));
        Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);

        // Check if this is a position opening transaction
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position != 0 && lastKnownPositionTicket == 0) {
            Print("🔍 Potential position opening transaction detected - Position: ", trans.position);

            // Verify this is our position by checking the deal
            if(HistoryDealSelect(trans.deal)) {
                string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
                string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
                ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

                Print("🔍 Deal symbol: ", deal_symbol, ", Comment: ", deal_comment);
                Print("🔍 EA identifier: ", eaIdentifier);
                Print("🔍 Deal entry type: ", EnumToString(deal_entry));

                if(deal_symbol == _Symbol && StringFind(deal_comment, eaIdentifier) >= 0 && deal_entry == DEAL_ENTRY_IN) {
                    Print("✅ Position opening confirmed for this EA - Ticket: ", trans.position);
                    lastKnownPositionTicket = trans.position;
                    lastPositionOpenTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

                    // Set the trade ID to the MT5 position ticket for consistency
                    if(lastTradeID == "" || lastTradeID == "0") {
                        lastTradeID = IntegerToString(trans.position);
                        Print("✅ Set trade ID to MT5 position ticket: ", lastTradeID);

                        // Note: SetTradeIDFromTicket is EA-specific and should be called by the EA

                        // Record trade entry analytics now that we have the actual position ticket
                        if(enableHttpAnalytics) {
                            Print("📊 HTTP Analytics enabled - EA should handle RecordTradeEntry");
                            // Note: RecordTradeEntry is EA-specific and should be handled by the EA
                        }

                        // Log trade data for ML retraining now that we have the actual MT5 ticket
                        if(pendingTradeData) {
                            Print("📊 Logging trade data for ML retraining with actual MT5 ticket: ", lastTradeID);
                            LogTradeForRetraining(lastTradeID, pendingDirection, pendingEntry, pendingStopLoss, pendingTakeProfit, pendingLotSize, pendingPrediction, pendingFeatures);
                            Print("✅ Trade data logged for ML retraining");

                            // Clear pending trade data
                            pendingTradeData = false;
                        }
                    }

                    Print("🔄 Updated position tracking - Ticket: ", lastKnownPositionTicket, ", Time: ", TimeToString(lastPositionOpenTime));
                    Print("🔄 Trade ID for this position: ", lastTradeID);
                } else {
                    Print("❌ Deal does not match this EA or is not an entry deal - skipping");
                    Print("   Symbol match: ", deal_symbol == _Symbol ? "true" : "false");
                    Print("   Comment match: ", StringFind(deal_comment, eaIdentifier) >= 0 ? "true" : "false");
                    Print("   Entry type: ", deal_entry == DEAL_ENTRY_IN ? "true" : "false");
                }
            } else {
                Print("❌ Could not select deal for position opening check: ", trans.deal);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Handle trade close transactions - utility function for EAs       |
    //+------------------------------------------------------------------+
    void HandleTradeCloseTransaction(const MqlTradeTransaction& trans,
                                   ulong& lastKnownPositionTicket,
                                   datetime& lastPositionOpenTime,
                                   string& lastTradeID,
                                   bool& pendingTradeData,
                                   bool enableHttpAnalytics,
                                   string eaIdentifier,
                                   TradeExitCallback tradeExitCallback) {
        Print("🔄 HandleTradeCloseTransaction() called - Transaction type: ", EnumToString(trans.type));
        Print("🔍 Position ticket: ", trans.position, ", Deal ticket: ", trans.deal);

        // Handle TRADE_TRANSACTION_DEAL_ADD for immediate trade close detection
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.position == lastKnownPositionTicket && lastKnownPositionTicket != 0) {
            Print("✅ Position close transaction detected for tracked position!");

            // Get the closing deal details
            if(HistoryDealSelect(trans.deal)) {
                ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

                // Only process if this is actually a closing deal
                if(deal_entry == DEAL_ENTRY_OUT) {
                    double close_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                    double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                    datetime close_time = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

                    Print("🔍 Deal details - Price: ", DoubleToString(close_price, _Digits), ", Profit: $", DoubleToString(profit, 2), ", Time: ", TimeToString(close_time));

                    // Process the trade close
                    ProcessTradeClose(close_price, profit, close_time, lastTradeID, lastKnownPositionTicket, lastPositionOpenTime, pendingTradeData, enableHttpAnalytics, tradeExitCallback);
                } else {
                    Print("❌ Deal is not a closing deal (entry type: ", EnumToString(deal_entry), ")");
                }
            } else {
                Print("❌ Could not select deal: ", trans.deal);
            }
        }

        // Handle TRADE_TRANSACTION_HISTORY_ADD for when position is moved to history after closing
        else if(trans.type == TRADE_TRANSACTION_HISTORY_ADD && trans.position == lastKnownPositionTicket && lastKnownPositionTicket != 0) {
            Print("✅ Position history add detected for tracked position: ", trans.position);

            // Position has been moved to history, which means it's closed
            // We need to get the closing deal information from history
            if(HistorySelectByPosition(trans.position)) {
                // Find the closing deal (DEAL_ENTRY_OUT)
                int total_deals = HistoryDealsTotal();
                bool found_closing_deal = false;

                for(int i = total_deals - 1; i >= 0; i--) {
                    ulong deal_ticket = HistoryDealGetTicket(i);
                    if(deal_ticket > 0) {
                        long deal_position = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                        ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                        string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
                        string deal_comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);

                        // Check if this is the closing deal for our position
                        if(deal_position == trans.position && deal_entry == DEAL_ENTRY_OUT &&
                           deal_symbol == _Symbol && StringFind(deal_comment, eaIdentifier) >= 0) {

                            Print("🔍 Found closing deal for position: ", trans.position);

                            double close_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                            datetime close_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);

                            Print("🔍 Deal details - Price: ", DoubleToString(close_price, _Digits), ", Profit: $", DoubleToString(profit, 2), ", Time: ", TimeToString(close_time));

                            // Process the trade close
                            ProcessTradeClose(close_price, profit, close_time, lastTradeID, lastKnownPositionTicket, lastPositionOpenTime, pendingTradeData, enableHttpAnalytics, tradeExitCallback);

                            found_closing_deal = true;
                            break;
                        }
                    }
                }

                if(!found_closing_deal) {
                    Print("⚠️ Could not find closing deal for position: ", trans.position);
                }
            } else {
                Print("❌ Could not select position history for: ", trans.position);
            }
        }
    }

private:
    //+------------------------------------------------------------------+
    //| Process trade close - common logic for both transaction types    |
    //+------------------------------------------------------------------+
    void ProcessTradeClose(double close_price, double profit, datetime close_time,
                          string& lastTradeID, ulong& lastKnownPositionTicket,
                          datetime& lastPositionOpenTime, bool& pendingTradeData,
                          bool enableHttpAnalytics, TradeExitCallback tradeExitCallback) {

        // Calculate profit/loss in pips
        double profitLossPips = 0.0;
        if(profit != 0) {
            double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            profitLossPips = profit / (pointValue * 10); // Convert to pips
        }

        Print("✅ Position closed detected - P&L: $", DoubleToString(profit, 2), " (", DoubleToString(profitLossPips, 1), " pips)");

        // Record trade exit analytics using callback
        if(enableHttpAnalytics && tradeExitCallback != NULL) {
            Print("📊 Recording trade exit analytics...");
            tradeExitCallback(close_price, profit, profitLossPips);
            Print("✅ Trade exit analytics recorded");
        } else {
            Print("⚠️ HTTP Analytics disabled or no trade exit callback provided");
        }

        // Always log trade close for ML retraining
        Print("📊 Logging trade close for ML retraining...");
        Print("🔍 Using stored trade ID: ", lastTradeID);
        LogTradeCloseForRetraining(lastTradeID, close_price, profit, profitLossPips, close_time);
        Print("✅ Trade close logged for ML retraining");

        // Reset position tracking
        lastKnownPositionTicket = 0;
        lastPositionOpenTime = 0;
        lastTradeID = ""; // Clear the trade ID
        pendingTradeData = false; // Clear pending trade data
        Print("🔄 Reset position tracking variables");
    }

private:
                // Prepare JSON request for API using JSON library
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

    // Get current timeframe as string
    string GetCurrentTimeframeString() {
        switch(_Period) {
            case PERIOD_M1:  return "M1";
            case PERIOD_M5:  return "M5";
            case PERIOD_M15: return "M15";
            case PERIOD_M30: return "M30";
            case PERIOD_H1:  return "H1";
            case PERIOD_H4:  return "H4";
            case PERIOD_D1:  return "D1";
            default:         return "H1";
        }
    }

};

// Global instance
MLHttpInterface g_ml_interface;
