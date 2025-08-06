#ifndef __EA_HTTP_ANALYTICS_MQH__
#define __EA_HTTP_ANALYTICS_MQH__

// HTTP Analytics Integration for MT5 EA
// Sends analytics data via HTTP requests to a web server

//--- Input parameters for analytics
input group "HTTP Analytics Settings"
input bool EnableHttpAnalytics = true;           // Enable HTTP analytics
input string AnalyticsServerUrl = "http://127.0.0.1:5001";  // Analytics server URL
input int HttpTimeout = 5000;                    // HTTP timeout (ms)
input bool EnableBatchMode = true;               // Send data in batches
input int BatchSize = 10;                        // Number of records per batch
input int BatchTimeout = 30000;                  // Batch timeout (ms)

//--- Global variables
string g_analytics_trade_id = "";
bool g_analytics_enabled = false;
datetime g_last_batch_send = 0;
int g_batch_count = 0;

//--- Analytics data structures
struct TradeAnalyticsData {
    string trade_id;
    string symbol;
    string timeframe;
    string direction;
    double entry_price;
    double exit_price;
    double stop_loss;
    double take_profit;
    double lot_size;
    double profit_loss;
    double profit_loss_pips;
    datetime entry_time;
    datetime exit_time;
    int duration_seconds;
    string status;
    string strategy_name;
    string strategy_version;
    string account_id;
};

struct MLAnalyticsData {
    string trade_id;
    string model_name;
    string model_type;
    double prediction_probability;
    double confidence_score;
    string features_json;
    datetime timestamp;
    string symbol;
    string timeframe;
    string strategy_name;
    string strategy_version;
};

struct MarketConditionsData {
    string trade_id;
    string symbol;
    string timeframe;
    double rsi;
    double stoch_main;
    double stoch_signal;
    double macd_main;
    double macd_signal;
    double bb_upper;
    double bb_lower;
    double cci;
    double momentum;
    double volume_ratio;
    double price_change;
    double volatility;
    double spread;
    int session_hour;
    int day_of_week;
    int month;
    double williams_r;
    double force_index;
};

//--- Batch data structure
struct BatchRecord {
    string type;
    string data_json;
};

//--- Global batch array
BatchRecord g_batch_records[];
int g_batch_size = 0;

//+------------------------------------------------------------------+
//| Initialize HTTP analytics system                                  |
//+------------------------------------------------------------------+
void InitializeHttpAnalytics(string strategy_name, string strategy_version) {
    if(!EnableHttpAnalytics) return;

    g_analytics_enabled = true;
    g_analytics_trade_id = "";
    g_last_batch_send = 0;
    g_batch_count = 0;
    g_batch_size = 0;

    // Test connection to analytics server
    if(!TestAnalyticsConnection()) {
        Print("❌ Failed to connect to analytics server: ", AnalyticsServerUrl);
        g_analytics_enabled = false;
        return;
    }

    Print("✅ HTTP Analytics initialized - Server: ", AnalyticsServerUrl);
}

//+------------------------------------------------------------------+
//| Test connection to analytics server                              |
//+------------------------------------------------------------------+
bool TestAnalyticsConnection() {
    string url = AnalyticsServerUrl + "/health";
    string headers = "Content-Type: application/json\r\n";
    uchar post[], result[];
    string result_headers;

    int res = WebRequest("GET", url, headers, 0, post, result, result_headers);

    if(res == 200) {
        string result_str = CharArrayToString(result);
        return StringFind(result_str, "healthy") >= 0;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Generate unique trade ID                                          |
//+------------------------------------------------------------------+
string GenerateTradeID() {
    // Use MT5 position ticket as trade ID for consistency
    // This will be set when a position is opened
    return "0"; // Placeholder - will be replaced with actual MT5 ticket
}

//+------------------------------------------------------------------+
//| Set trade ID from MT5 position ticket                            |
//+------------------------------------------------------------------+
void SetTradeIDFromTicket(ulong position_ticket) {
    g_analytics_trade_id = IntegerToString(position_ticket);
    Print("✅ Analytics trade ID set to MT5 position ticket: ", g_analytics_trade_id);
}

//+------------------------------------------------------------------+
//| Record trade entry via HTTP                                       |
//+------------------------------------------------------------------+
void RecordTradeEntry(string direction, double entry_price, double stop_loss,
                      double take_profit, double lot_size, string strategy_name,
                      string strategy_version) {
    if(!g_analytics_enabled) return;

    // Only record if we have a valid trade ID (not "0")
    if(g_analytics_trade_id == "" || g_analytics_trade_id == "0") {
        Print("⚠️ No valid trade ID available - skipping analytics recording");
        return;
    }

    TradeAnalyticsData data;
    data.trade_id = g_analytics_trade_id;
    data.symbol = _Symbol;
    data.timeframe = GetCurrentTimeframeString();
    data.direction = direction;
    data.entry_price = entry_price;
    data.exit_price = 0.0;
    data.stop_loss = stop_loss;
    data.take_profit = take_profit;
    data.lot_size = lot_size;
    data.profit_loss = 0.0;
    data.profit_loss_pips = 0.0;
    data.entry_time = TimeCurrent();
    data.exit_time = 0;
    data.duration_seconds = 0;
    data.status = "OPEN";
    data.strategy_name = strategy_name;
    data.strategy_version = strategy_version;
    data.account_id = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));

    // Always send trade data directly, not in batches
    SendTradeData(data);
}

//+------------------------------------------------------------------+
//| Record trade exit via HTTP                                        |
//+------------------------------------------------------------------+
void RecordTradeExit(double exit_price, double profit_loss, double profit_loss_pips) {
    if(!g_analytics_enabled || g_analytics_trade_id == "") return;

    // Create exit data
    string exit_data = "{\"trade_id\":" + g_analytics_trade_id + ",";
    exit_data += "\"exit_price\":" + DoubleToString(exit_price, _Digits) + ",";
    exit_data += "\"profit_loss\":" + DoubleToString(profit_loss, 2) + ",";
    exit_data += "\"profit_loss_pips\":" + DoubleToString(profit_loss_pips, 2) + ",";
    exit_data += "\"exit_time\":" + IntegerToString(TimeCurrent()) + ",";
    exit_data += "\"status\":\"CLOSED\"}";

    // Always send trade exit data directly, not in batches
    SendHttpRequest("/analytics/trade_exit", exit_data);

    g_analytics_trade_id = "";
}

//+------------------------------------------------------------------+
//| Record ML prediction via HTTP (trade-specific)                    |
//+------------------------------------------------------------------+
void RecordMLPrediction(string model_name, string model_type, double prediction_probability,
                        double confidence_score, string features_json = "") {
    if(!g_analytics_enabled) return;

    // Only record if we have a valid trade ID (not "0")
    if(g_analytics_trade_id == "" || g_analytics_trade_id == "0") {
        Print("⚠️ No valid trade ID available - skipping ML prediction recording");
        return;
    }

    MLAnalyticsData data;
    data.trade_id = g_analytics_trade_id;
    data.model_name = model_name;
    data.model_type = model_type;
    data.prediction_probability = prediction_probability;
    data.confidence_score = confidence_score;
    data.features_json = features_json;
    data.timestamp = TimeCurrent();
    data.symbol = _Symbol;
    data.timeframe = GetCurrentTimeframeString();
    data.strategy_name = "BreakoutStrategy_ML";
    data.strategy_version = "1.00";

    if(EnableBatchMode) {
        AddMLToBatch(data);
    } else {
        SendMLData(data);
    }
}

//+------------------------------------------------------------------+
//| Record general ML prediction via HTTP (no trade required)         |
//+------------------------------------------------------------------+
void RecordGeneralMLPrediction(string model_name, string model_type, double prediction_probability,
                               double confidence_score, string features_json = "") {
    if(!g_analytics_enabled) return;

    MLAnalyticsData data;
    data.trade_id = "0"; // General prediction, not tied to a specific trade
    data.model_name = model_name;
    data.model_type = model_type;
    data.prediction_probability = prediction_probability;
    data.confidence_score = confidence_score;
    data.features_json = features_json;
    data.timestamp = TimeCurrent();
    data.symbol = _Symbol;
    data.timeframe = GetCurrentTimeframeString();
    data.strategy_name = "BreakoutStrategy_ML";
    data.strategy_version = "1.00";

    if(EnableBatchMode) {
        AddMLToBatch(data);
    } else {
        SendMLData(data);
    }
}

//+------------------------------------------------------------------+
//| Record market conditions via HTTP (trade-specific)                |
//+------------------------------------------------------------------+
void RecordMarketConditions(MLFeatures &features) {
    if(!g_analytics_enabled) return;

    // Only record if we have a valid trade ID (not "0")
    if(g_analytics_trade_id == "" || g_analytics_trade_id == "0") {
        Print("⚠️ No valid trade ID available - skipping market conditions recording");
        return;
    }

    MarketConditionsData data;
    data.trade_id = g_analytics_trade_id;
    data.symbol = _Symbol; // Set current symbol
    data.timeframe = EnumToString(_Period); // Set current timeframe
    data.rsi = features.rsi;
    data.stoch_main = features.stoch_main;
    data.stoch_signal = features.stoch_signal;
    data.macd_main = features.macd_main;
    data.macd_signal = features.macd_signal;
    data.bb_upper = features.bb_upper;
    data.bb_lower = features.bb_lower;
    data.cci = features.cci;
    data.momentum = features.momentum;
    data.volume_ratio = features.volume_ratio;
    data.price_change = features.price_change;
    data.volatility = features.volatility;
    data.spread = features.spread;
    data.session_hour = features.session_hour;
    data.day_of_week = features.day_of_week;
    data.month = features.month;
    data.williams_r = features.williams_r;
    data.force_index = features.force_index;

    if(EnableBatchMode) {
        AddMarketConditionsToBatch(data);
    } else {
        SendMarketConditionsData(data);
    }
}

//+------------------------------------------------------------------+
//| Record general market conditions via HTTP (no trade required)     |
//+------------------------------------------------------------------+
void RecordGeneralMarketConditions(MLFeatures &features) {
    if(!g_analytics_enabled) return;

    MarketConditionsData data;
    data.trade_id = "0"; // General market conditions, not tied to a specific trade
    data.symbol = _Symbol; // Set current symbol
    data.timeframe = EnumToString(_Period); // Set current timeframe
    data.rsi = features.rsi;
    data.stoch_main = features.stoch_main;
    data.stoch_signal = features.stoch_signal;
    data.macd_main = features.macd_main;
    data.macd_signal = features.macd_signal;
    data.bb_upper = features.bb_upper;
    data.bb_lower = features.bb_lower;
    data.cci = features.cci;
    data.momentum = features.momentum;
    data.volume_ratio = features.volume_ratio;
    data.price_change = features.price_change;
    data.volatility = features.volatility;
    data.spread = features.spread;
    data.session_hour = features.session_hour;
    data.day_of_week = features.day_of_week;
    data.month = features.month;
    data.williams_r = features.williams_r;
    data.force_index = features.force_index;

    if(EnableBatchMode) {
        AddMarketConditionsToBatch(data);
    } else {
        SendMarketConditionsData(data);
    }
}

//+------------------------------------------------------------------+
//| Add trade record to batch                                         |
//+------------------------------------------------------------------+
void AddTradeToBatch(TradeAnalyticsData &data) {
    if(g_batch_size >= BatchSize) {
        SendBatch();
    }

    // Resize array if needed
    if(g_batch_size >= ArraySize(g_batch_records)) {
        ArrayResize(g_batch_records, g_batch_size + 10);
    }

    g_batch_records[g_batch_size].type = "trade";
    g_batch_records[g_batch_size].data_json = TradeStructToJson(data);
    g_batch_size++;

    // Check if we should send batch due to timeout
    if(TimeCurrent() - g_last_batch_send > BatchTimeout) {
        SendBatch();
    }
}

//+------------------------------------------------------------------+
//| Add ML record to batch                                            |
//+------------------------------------------------------------------+
void AddMLToBatch(MLAnalyticsData &data) {
    if(g_batch_size >= BatchSize) {
        SendBatch();
    }

    // Resize array if needed
    if(g_batch_size >= ArraySize(g_batch_records)) {
        ArrayResize(g_batch_records, g_batch_size + 10);
    }

    g_batch_records[g_batch_size].type = "ml_prediction";
    g_batch_records[g_batch_size].data_json = MLStructToJson(data);
    g_batch_size++;

    // Check if we should send batch due to timeout
    if(TimeCurrent() - g_last_batch_send > BatchTimeout) {
        SendBatch();
    }
}

//+------------------------------------------------------------------+
//| Add market conditions record to batch                             |
//+------------------------------------------------------------------+
void AddMarketConditionsToBatch(MarketConditionsData &data) {
    if(g_batch_size >= BatchSize) {
        SendBatch();
    }

    // Resize array if needed
    if(g_batch_size >= ArraySize(g_batch_records)) {
        ArrayResize(g_batch_records, g_batch_size + 10);
    }

    g_batch_records[g_batch_size].type = "market_conditions";
    g_batch_records[g_batch_size].data_json = MarketConditionsStructToJson(data);
    g_batch_size++;

    // Check if we should send batch due to timeout
    if(TimeCurrent() - g_last_batch_send > BatchTimeout) {
        SendBatch();
    }
}

//+------------------------------------------------------------------+
//| Send batch of records                                             |
//+------------------------------------------------------------------+
void SendBatch() {
    if(g_batch_size == 0) return;

    string batch_json = "{\"records\":[";

    for(int i = 0; i < g_batch_size; i++) {
        if(i > 0) batch_json += ",";
        batch_json += "{\"type\":\"" + g_batch_records[i].type + "\",";
        batch_json += "\"data\":" + g_batch_records[i].data_json + "}";
    }

    batch_json += "]}";

    SendHttpRequest("/analytics/batch", batch_json);

    g_batch_size = 0;
    g_last_batch_send = TimeCurrent();
    g_batch_count++;
}

//+------------------------------------------------------------------+
//| Send HTTP request                                                 |
//+------------------------------------------------------------------+
void SendHttpRequest(string endpoint, string data) {
    Print("📤 Sending analytics HTTP request to: ", endpoint);
    Print("   URL: ", AnalyticsServerUrl + endpoint);
    Print("   Data length: ", StringLen(data), " characters");
    Print("   Data preview: ", StringSubstr(data, 0, 200), "...");

    string url = AnalyticsServerUrl + endpoint;
    string headers = "Content-Type: application/json\r\n";
    uchar post[], result[];
    string result_headers;

    // Convert data to UTF-8 uchar array (fix for WebRequest buffer issue)
    StringToCharArray(data, post, 0, WHOLE_ARRAY, CP_UTF8);
    // Remove the null terminator that StringToCharArray adds
    ArrayRemove(post, ArraySize(post)-1);
    Print("   Binary data length: ", ArraySize(post), " bytes");

    int res = WebRequest("POST", url, headers, 0, post, result, result_headers);
    Print("📥 HTTP Response Code: ", res);

    if(res == 200 || res == 201) {
        string response = CharArrayToString(result);
        Print("✅ Analytics request successful");
        Print("   Response: ", response);
    } else {
        string response = CharArrayToString(result);
        Print("❌ HTTP request failed: ", res, " - ", endpoint);
        Print("   Response: ", response);
    }
}

//+------------------------------------------------------------------+
//| Send trade data                                                   |
//+------------------------------------------------------------------+
void SendTradeData(TradeAnalyticsData &data) {
    string json = TradeStructToJson(data);
    SendHttpRequest("/analytics/trade", json);
}

//+------------------------------------------------------------------+
//| Send ML data                                                      |
//+------------------------------------------------------------------+
void SendMLData(MLAnalyticsData &data) {
    string json = MLStructToJson(data);
    SendHttpRequest("/analytics/ml_prediction", json);
}

//+------------------------------------------------------------------+
//| Send market conditions data                                       |
//+------------------------------------------------------------------+
void SendMarketConditionsData(MarketConditionsData &data) {
    string json = MarketConditionsStructToJson(data);
    SendHttpRequest("/analytics/market_conditions", json);
}

//+------------------------------------------------------------------+
//| Convert trade struct to JSON                                      |
//+------------------------------------------------------------------+
string TradeStructToJson(TradeAnalyticsData &data) {
    string json = "{";
    json += "\"trade_id\":" + data.trade_id + ",";
    json += "\"symbol\":\"" + data.symbol + "\",";
    json += "\"timeframe\":\"" + data.timeframe + "\",";
    json += "\"direction\":\"" + data.direction + "\",";
    json += "\"entry_price\":" + DoubleToString(data.entry_price, _Digits) + ",";
    json += "\"exit_price\":" + DoubleToString(data.exit_price, _Digits) + ",";
    json += "\"stop_loss\":" + DoubleToString(data.stop_loss, _Digits) + ",";
    json += "\"take_profit\":" + DoubleToString(data.take_profit, _Digits) + ",";
    json += "\"lot_size\":" + DoubleToString(data.lot_size, 2) + ",";
    json += "\"profit_loss\":" + DoubleToString(data.profit_loss, 2) + ",";
    json += "\"profit_loss_pips\":" + DoubleToString(data.profit_loss_pips, 2) + ",";
    json += "\"entry_time\":" + IntegerToString(data.entry_time) + ",";
    json += "\"exit_time\":" + IntegerToString(data.exit_time) + ",";
    json += "\"duration_seconds\":" + IntegerToString(data.duration_seconds) + ",";
    json += "\"status\":\"" + data.status + "\",";
    json += "\"strategy_name\":\"" + data.strategy_name + "\",";
    json += "\"strategy_version\":\"" + data.strategy_version + "\",";
    json += "\"account_id\":\"" + data.account_id + "\"";
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Convert ML struct to JSON                                         |
//+------------------------------------------------------------------+
string MLStructToJson(MLAnalyticsData &data) {
    string json = "{";
    json += "\"trade_id\":" + data.trade_id + ",";
    json += "\"model_name\":\"" + data.model_name + "\",";
    json += "\"model_type\":\"" + data.model_type + "\",";
    json += "\"prediction_probability\":" + DoubleToString(data.prediction_probability, 3) + ",";
    json += "\"confidence_score\":" + DoubleToString(data.confidence_score, 3) + ",";
    json += "\"features_json\":\"" + data.features_json + "\",";
    json += "\"timestamp\":" + IntegerToString(data.timestamp) + ",";
    json += "\"symbol\":\"" + data.symbol + "\",";
    json += "\"timeframe\":\"" + data.timeframe + "\",";
    json += "\"strategy_name\":\"" + data.strategy_name + "\",";
    json += "\"strategy_version\":\"" + data.strategy_version + "\"";
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Convert market conditions struct to JSON                          |
//+------------------------------------------------------------------+
string MarketConditionsStructToJson(MarketConditionsData &data) {
    string json = "{";
    json += "\"trade_id\":" + data.trade_id + ",";
    json += "\"symbol\":\"" + data.symbol + "\",";
    json += "\"timeframe\":\"" + data.timeframe + "\",";
    json += "\"rsi\":" + DoubleToString(data.rsi, 2) + ",";
    json += "\"stoch_main\":" + DoubleToString(data.stoch_main, 2) + ",";
    json += "\"stoch_signal\":" + DoubleToString(data.stoch_signal, 2) + ",";
    json += "\"macd_main\":" + DoubleToString(data.macd_main, 2) + ",";
    json += "\"macd_signal\":" + DoubleToString(data.macd_signal, 2) + ",";
    json += "\"bb_upper\":" + DoubleToString(data.bb_upper, _Digits) + ",";
    json += "\"bb_lower\":" + DoubleToString(data.bb_lower, _Digits) + ",";
    json += "\"cci\":" + DoubleToString(data.cci, 2) + ",";
    json += "\"momentum\":" + DoubleToString(data.momentum, 2) + ",";
    json += "\"volume_ratio\":" + DoubleToString(data.volume_ratio, 2) + ",";
    json += "\"price_change\":" + DoubleToString(data.price_change, 4) + ",";
    json += "\"volatility\":" + DoubleToString(data.volatility, 4) + ",";
    json += "\"spread\":" + DoubleToString(data.spread, _Digits) + ",";
    json += "\"session_hour\":" + IntegerToString(data.session_hour) + ",";
    json += "\"day_of_week\":" + IntegerToString(data.day_of_week) + ",";
    json += "\"month\":" + IntegerToString(data.month) + ",";
    json += "\"williams_r\":" + DoubleToString(data.williams_r, 2) + ",";
    json += "\"force_index\":" + DoubleToString(data.force_index, 2);
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Add exit data to batch                                            |
//+------------------------------------------------------------------+
void AddExitToBatch(string exit_data) {
    if(g_batch_size >= BatchSize) {
        SendBatch();
    }

    // Resize array if needed
    if(g_batch_size >= ArraySize(g_batch_records)) {
        ArrayResize(g_batch_records, g_batch_size + 10);
    }

    g_batch_records[g_batch_size].type = "trade_exit";
    g_batch_records[g_batch_size].data_json = exit_data;
    g_batch_size++;

    // Check if we should send batch due to timeout
    if(TimeCurrent() - g_last_batch_send > BatchTimeout) {
        SendBatch();
    }
}

//+------------------------------------------------------------------+
//| Get current timeframe as string                                   |
//+------------------------------------------------------------------+
string GetCurrentTimeframeString() {
    switch(_Period) {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "H1";
    }
}

#endif // __EA_HTTP_ANALYTICS_MQH__
