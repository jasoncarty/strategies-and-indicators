//+------------------------------------------------------------------+
//|                                              WebServerAPI.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Web Server Configuration                                           |
//+------------------------------------------------------------------+
#define WEB_SERVER_URL "http://192.168.68.50:5000"
#define WEB_SERVER_TIMEOUT 5000

//+------------------------------------------------------------------+
//| Structure for Strategy Test Results                               |
//+------------------------------------------------------------------+
struct StrategyTestResult
{
    string strategy_name;
    string strategy_version;
    string symbol;
    string timeframe;
    datetime start_date;
    datetime end_date;
    double initial_deposit;
    double final_balance;
    double profit;
    double profit_factor;
    double max_drawdown;
    int total_trades;
    int winning_trades;
    int losing_trades;
    double win_rate;
    double sharpe_ratio;

    // --- New Fields ---
    double gross_profit;
    double gross_loss;
    double recovery_factor;
    double expected_payoff;
    double z_score;
    int long_trades;
    int short_trades;
    int long_trades_won;
    int short_trades_won;
    double largest_profit;
    double largest_loss;
    double avg_profit;
    double avg_loss;
    int max_consecutive_wins;
    int max_consecutive_losses;
    int avg_consecutive_wins;
    int avg_consecutive_losses;
    // --- End New Fields ---

    string parameters;
};

//+------------------------------------------------------------------+
//| Structure for Trade Data                                          |
//+------------------------------------------------------------------+
struct TradeData
{
    int ticket;
    string symbol;
    string type;
    double volume;
    double open_price;
    double close_price;
    datetime open_time;
    datetime close_time;
    double profit;
    double swap;
    double commission;
    double net_profit;
    string trading_conditions_json; // Holds the JSON string for trading conditions
};

//+------------------------------------------------------------------+
//| Convert datetime to ISO format for the API                       |
//+------------------------------------------------------------------+
string Api_DateTimeToISO(datetime dt)
{
    MqlDateTime mdt;
    TimeToStruct(dt, mdt);

    return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",
        mdt.year, mdt.mon, mdt.day, mdt.hour, mdt.min, mdt.sec);
}

//+------------------------------------------------------------------+
//| Convert MQL5 datetime to ISO string for the API                  |
//+------------------------------------------------------------------+
string Api_DateTimeToString(datetime time)
{
    return Api_DateTimeToISO(time);
}

//+------------------------------------------------------------------+
//| Helper macros for parameter capture                              |
//+------------------------------------------------------------------+
#define ADD_PARAM_BOOL(name) \
    if(param_count > 0) parameters += ","; \
    parameters += "\"" + #name + "\":" + (name ? "true" : "false"); \
    param_count++

#define ADD_PARAM_INT(name) \
    if(param_count > 0) parameters += ","; \
    parameters += "\"" + #name + "\":" + IntegerToString(name); \
    param_count++

#define ADD_PARAM_DOUBLE(name, digits) \
    if(param_count > 0) parameters += ","; \
    parameters += "\"" + #name + "\":" + DoubleToString(name, digits); \
    param_count++

#define ADD_PARAM_STRING(name) \
    if(param_count > 0) parameters += ","; \
    parameters += "\"" + #name + "\":\"" + name + "\""; \
    param_count++

#define ADD_PARAM_TIMEFRAME(name) \
    if(param_count > 0) parameters += ","; \
    parameters += "\"" + #name + "\":\"" + EnumToString(name) + "\""; \
    param_count++

//+------------------------------------------------------------------+
//| Dynamically capture all input parameters as JSON                 |
//+------------------------------------------------------------------+
string CaptureAllInputParameters()
{
    string parameters = "{";
    int param_count = 0;

    // Add your parameters here using the macros above
    // This is much cleaner than the previous hardcoded approach

    // Risk Management Parameters
    ADD_PARAM_DOUBLE(RiskPercent, 2);
    ADD_PARAM_DOUBLE(RRRatio, 2);
    ADD_PARAM_DOUBLE(MinLotSize, 2);
    ADD_PARAM_DOUBLE(MaxLotSize, 2);
    ADD_PARAM_INT(MaxPositions);

    // Stop Loss Parameters
    ADD_PARAM_BOOL(UseATRStopLoss);
    ADD_PARAM_DOUBLE(ATRMultiplier, 2);
    ADD_PARAM_INT(ATRPeriod);
    ADD_PARAM_BOOL(UseTrailingStop);
    ADD_PARAM_DOUBLE(TrailStartPercent, 2);
    ADD_PARAM_DOUBLE(TrailDistancePercent, 2);

    // Imbalance Settings
    ADD_PARAM_INT(ImbalanceConfirmationBars);
    ADD_PARAM_DOUBLE(MinImbalanceRatio, 2);
    ADD_PARAM_INT(MinImbalanceVolume);
    ADD_PARAM_BOOL(RequireStackedImbalance);
    ADD_PARAM_BOOL(RequireVolumeConfirmation);

    // Trading Settings
    ADD_PARAM_BOOL(RequireConfirmation);
    ADD_PARAM_INT(MagicNumber);

    // ICT Macro and Custom Interval Trading Restrictions
    ADD_PARAM_BOOL(RestrictToICTMacros);
    ADD_PARAM_STRING(CustomRestrictTimes);
    ADD_PARAM_INT(ServerToESTOffset);

    // News Filter Settings
    ADD_PARAM_INT(NewsBlockMinutesBefore);
    ADD_PARAM_INT(NewsBlockMinutesAfter);
    ADD_PARAM_BOOL(BlockHighImpactOnly);

    // Kill Zone Settings
    ADD_PARAM_BOOL(UseKillZones);
    ADD_PARAM_BOOL(UseLondonKillZone);
    ADD_PARAM_INT(LondonKillZoneStart);
    ADD_PARAM_INT(LondonKillZoneEnd);
    ADD_PARAM_BOOL(UseNewYorkKillZone);
    ADD_PARAM_INT(NewYorkKillZoneStart);
    ADD_PARAM_INT(NewYorkKillZoneEnd);
    ADD_PARAM_BOOL(UseAsianKillZone);
    ADD_PARAM_INT(AsianKillZoneStart);
    ADD_PARAM_INT(AsianKillZoneEnd);
    ADD_PARAM_BOOL(UseLondonOpenKillZone);
    ADD_PARAM_INT(LondonOpenKillZoneStart);
    ADD_PARAM_INT(LondonOpenKillZoneEnd);
    ADD_PARAM_BOOL(UseNewYorkOpenKillZone);
    ADD_PARAM_INT(NewYorkOpenKillZoneStart);
    ADD_PARAM_INT(NewYorkOpenKillZoneEnd);

    // Market Structure Settings
    ADD_PARAM_BOOL(UseMarketStructureFilter);
    ADD_PARAM_TIMEFRAME(StructureTimeframe);
    ADD_PARAM_INT(StructureLookback);
    ADD_PARAM_BOOL(RequireLiquiditySweep);
    ADD_PARAM_INT(LiquiditySweepLookback);
    ADD_PARAM_DOUBLE(MinSweepDistance, 2);

    // OTE Filter Settings
    ADD_PARAM_BOOL(UseOTEFilter);
    ADD_PARAM_BOOL(UseFibonacciLevels);
    ADD_PARAM_DOUBLE(FibLevel1, 3);
    ADD_PARAM_DOUBLE(FibLevel2, 3);
    ADD_PARAM_DOUBLE(FibLevel3, 3);
    ADD_PARAM_DOUBLE(FibLevel4, 3);

    // Order Block Settings
    ADD_PARAM_BOOL(UseOrderBlocks);
    ADD_PARAM_INT(OrderBlockLookback);
    ADD_PARAM_DOUBLE(OrderBlockMinSize, 2);

    // Standard Deviation Settings
    ADD_PARAM_BOOL(UseStandardDeviation);
    ADD_PARAM_INT(StdDevPeriod);
    ADD_PARAM_DOUBLE(StdDevMultiplier, 2);

    // Lower Timeframe Analysis
    ADD_PARAM_BOOL(UseLowerTimeframeTriggers);
    ADD_PARAM_TIMEFRAME(LowerTimeframe);
    ADD_PARAM_INT(LTFStructureLookback);
    ADD_PARAM_BOOL(RequireLTFConfirmation);
    ADD_PARAM_BOOL(RequireOTERetest);
    ADD_PARAM_DOUBLE(OTERetestTolerance, 2);
    ADD_PARAM_INT(MinLTFConditions);
    ADD_PARAM_BOOL(RequireStructureBreak);
    ADD_PARAM_BOOL(AllowLTFOnlyTrades);
    ADD_PARAM_BOOL(RequireMarketStructureForLTF);

    parameters += "}";
    return parameters;
}

//+------------------------------------------------------------------+
//| Create JSON string from strategy test result                     |
//+------------------------------------------------------------------+
string CreateTestResultJSON(const StrategyTestResult &result, const TradeData &trades[])
{
    string json = "{";
    json += "\"strategy_name\":\"" + result.strategy_name + "\",";
    json += "\"strategy_version\":\"" + result.strategy_version + "\",";
    json += "\"symbol\":\"" + result.symbol + "\",";
    json += "\"timeframe\":\"" + result.timeframe + "\",";
    json += "\"start_date\":\"" + Api_DateTimeToString(result.start_date) + "\",";
    json += "\"end_date\":\"" + Api_DateTimeToString(result.end_date) + "\",";
    json += "\"initial_deposit\":" + DoubleToString(result.initial_deposit, 2) + ",";
    json += "\"final_balance\":" + DoubleToString(result.final_balance, 2) + ",";
    json += "\"profit\":" + DoubleToString(result.profit, 2) + ",";
    json += "\"profit_factor\":" + DoubleToString(result.profit_factor, 2) + ",";
    json += "\"max_drawdown\":" + DoubleToString(result.max_drawdown, 2) + ",";
    json += "\"total_trades\":" + IntegerToString(result.total_trades) + ",";
    json += "\"winning_trades\":" + IntegerToString(result.winning_trades) + ",";
    json += "\"losing_trades\":" + IntegerToString(result.losing_trades) + ",";
    json += "\"win_rate\":" + DoubleToString(result.win_rate, 2) + ",";
    json += "\"sharpe_ratio\":" + DoubleToString(result.sharpe_ratio, 2) + ",";

    // --- New Fields ---
    json += "\"gross_profit\":" + DoubleToString(result.gross_profit, 2) + ",";
    json += "\"gross_loss\":" + DoubleToString(result.gross_loss, 2) + ",";
    json += "\"recovery_factor\":" + DoubleToString(result.recovery_factor, 2) + ",";
    json += "\"expected_payoff\":" + DoubleToString(result.expected_payoff, 2) + ",";
    json += "\"z_score\":" + DoubleToString(result.z_score, 2) + ",";
    json += "\"long_trades\":" + IntegerToString(result.long_trades) + ",";
    json += "\"short_trades\":" + IntegerToString(result.short_trades) + ",";
    json += "\"long_trades_won\":" + IntegerToString(result.long_trades_won) + ",";
    json += "\"short_trades_won\":" + IntegerToString(result.short_trades_won) + ",";
    json += "\"largest_profit\":" + DoubleToString(result.largest_profit, 2) + ",";
    json += "\"largest_loss\":" + DoubleToString(result.largest_loss, 2) + ",";
    json += "\"avg_profit\":" + DoubleToString(result.avg_profit, 2) + ",";
    json += "\"avg_loss\":" + DoubleToString(result.avg_loss, 2) + ",";
    json += "\"max_consecutive_wins\":" + IntegerToString(result.max_consecutive_wins) + ",";
    json += "\"max_consecutive_losses\":" + IntegerToString(result.max_consecutive_losses) + ",";
    json += "\"avg_consecutive_wins\":" + IntegerToString(result.avg_consecutive_wins) + ",";
    json += "\"avg_consecutive_losses\":" + IntegerToString(result.avg_consecutive_losses) + ",";
    // --- End New Fields ---

    json += "\"parameters\":" + result.parameters + ",";

    // Add trades array
    json += "\"trades\":[";
    for(int i = 0; i < ArraySize(trades); i++)
    {
        if(i > 0) json += ",";
        json += "{";
        json += "\"ticket\":" + IntegerToString(trades[i].ticket) + ",";
        json += "\"symbol\":\"" + trades[i].symbol + "\",";
        json += "\"type\":\"" + trades[i].type + "\",";
        json += "\"volume\":" + DoubleToString(trades[i].volume, 2) + ",";
        json += "\"open_price\":" + DoubleToString(trades[i].open_price, 5) + ",";
        json += "\"close_price\":" + DoubleToString(trades[i].close_price, 5) + ",";
        json += "\"open_time\":\"" + Api_DateTimeToString(trades[i].open_time) + "\",";
        json += "\"close_time\":\"" + Api_DateTimeToString(trades[i].close_time) + "\",";
        json += "\"profit\":" + DoubleToString(trades[i].profit, 2) + ",";
        json += "\"swap\":" + DoubleToString(trades[i].swap, 2) + ",";
        json += "\"commission\":" + DoubleToString(trades[i].commission, 2) + ",";
        json += "\"net_profit\":" + DoubleToString(trades[i].net_profit, 2);
        // Add the trading_conditions object, if it's not empty
        if(trades[i].trading_conditions_json != "" && trades[i].trading_conditions_json != "{}")
        {
            json += ",\"trading_conditions\":" + trades[i].trading_conditions_json;
        }
        json += "}";
    }
    json += "]";
    json += "}";

    return json;
}

//+------------------------------------------------------------------+
//| Save strategy test results to a JSON file                        |
//+------------------------------------------------------------------+
bool SaveTestResultsToFile(const StrategyTestResult &result, const TradeData &trades[])
{
    // Create a file-safe datetime string from the CURRENT time to ensure uniqueness
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt); // Use TimeCurrent() for a unique timestamp
    string dt_string = StringFormat("%04d-%02d-%02d_%02d-%02d-%02d",
                                    dt.year, dt.mon, dt.day,
                                    dt.hour, dt.min, dt.sec);

    // Create a unique filename using the safe string
    string filename = result.strategy_name + "-" + dt_string + ".json";

    // Create the JSON payload
    string json_data = CreateTestResultJSON(result, trades);

    // Use FILE_COMMON to save to the shared data folder, which is stable on macOS/Wine
    int file_handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);

    if(file_handle == INVALID_HANDLE)
    {
        Print("Error opening file '", filename, "'. Error code: ", GetLastError());
        return false;
    }

    FileWriteString(file_handle, json_data);
    FileClose(file_handle);

    Print("Successfully saved test results to file: ", filename);
    // Let's print the exact path so we know where to watch
    Print("File should be located in the 'Common/Files' directory at: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH));
    return true;
}

//+------------------------------------------------------------------+
//| [DEPRECATED FOR MACOS] Send strategy test results to web server  |
//+------------------------------------------------------------------+
bool SendTestResultsToServer(const StrategyTestResult &result, const TradeData &trades[])
{
    string url = WEB_SERVER_URL + "/api/test";
    string headers = "Content-Type: application/json";
    string post_data = CreateTestResultJSON(result, trades);

    uchar post[], result_data[];
    string result_headers;
    int res;

    StringToCharArray(post_data, post, 0, -1, CP_UTF8);

    res = WebRequest("POST", url, headers, WEB_SERVER_TIMEOUT, post, result_data, result_headers);

    if(res == 201)
    {
        string response = CharArrayToString(result_data);
        Print("Test results sent successfully to web server");
        Print("Response: ", response);
        return true;
    }
    else
    {
        Print("Failed to send test results to web server. Error code: ", res);
        if(res == -1)
            Print("Make sure to add '", WEB_SERVER_URL, "' to the 'Allow WebRequest' list in MT5 settings");
        return false;
    }
}

//+------------------------------------------------------------------+
//| [DEPRECATED FOR MACOS] Get strategy test results from web server |
//+------------------------------------------------------------------+
bool GetTestResultsFromServer()
{
    string url = WEB_SERVER_URL + "/api/tests";
    uchar result[];
    string result_headers;
    uchar data[];
    int res;

    res = WebRequest("GET", url, "", WEB_SERVER_TIMEOUT, data, result, result_headers);

    if(res == 200)
    {
        string response = CharArrayToString(result);
        Print("Retrieved test results from web server:");
        Print(response);
        return true;
    }
    else
    {
        Print("Failed to get test results from web server. Error code: ", res);
        return false;
    }
}

//+------------------------------------------------------------------+
//| [DEPRECATED FOR MACOS] Get statistics from web server            |
//+------------------------------------------------------------------+
bool GetStatsFromServer()
{
    string url = WEB_SERVER_URL + "/api/stats";
    uchar result[];
    string result_headers;
    uchar data[];
    int res;

    res = WebRequest("GET", url, "", WEB_SERVER_TIMEOUT, data, result, result_headers);

    if(res == 200)
    {
        string response = CharArrayToString(result);
        Print("Retrieved statistics from web server:");
        Print(response);
        return true;
    }
    else
    {
        Print("Failed to get statistics from web server. Error code: ", res);
        return false;
    }
}

//+------------------------------------------------------------------+
//| [DEPRECATED FOR MACOS] Example function to extract test results  |
//+------------------------------------------------------------------+
bool ExtractAndSendTestResults(string strategy_name, string parameters = "{}")
{
    // This function should be called after a strategy test is completed
    // You'll need to implement the logic to extract actual test results
    // from the strategy tester or your EA's variables

    StrategyTestResult result;
    result.strategy_name = strategy_name;
    result.symbol = _Symbol;
    result.timeframe = EnumToString(_Period);
    result.start_date = 0; // Set to actual test start date
    result.end_date = 0;   // Set to actual test end date
    result.initial_deposit = 10000; // Set to actual initial deposit
    result.final_balance = 0;       // Set to actual final balance
    result.profit = 0;              // Set to actual profit
    result.profit_factor = 0;       // Set to actual profit factor
    result.max_drawdown = 0;        // Set to actual max drawdown
    result.total_trades = 0;        // Set to actual total trades
    result.winning_trades = 0;      // Set to actual winning trades
    result.losing_trades = 0;       // Set to actual losing trades
    result.win_rate = 0;            // Set to actual win rate
    result.sharpe_ratio = 0;        // Set to actual Sharpe ratio
    result.gross_profit = 0;         // Set to actual gross profit
    result.gross_loss = 0;          // Set to actual gross loss
    result.recovery_factor = 0;     // Set to actual recovery factor
    result.expected_payoff = 0;     // Set to actual expected payoff
    result.z_score = 0;             // Set to actual z-score
    result.long_trades = 0;         // Set to actual long trades
    result.short_trades = 0;        // Set to actual short trades
    result.long_trades_won = 0;     // Set to actual long trades won
    result.short_trades_won = 0;    // Set to actual short trades won
    result.largest_profit = 0;       // Set to actual largest profit
    result.largest_loss = 0;         // Set to actual largest loss
    result.avg_profit = 0;           // Set to actual average profit
    result.avg_loss = 0;            // Set to actual average loss
    result.max_consecutive_wins = 0; // Set to actual max consecutive wins
    result.max_consecutive_losses = 0; // Set to actual max consecutive losses
    result.avg_consecutive_wins = 0; // Set to actual average consecutive wins
    result.avg_consecutive_losses = 0; // Set to actual average consecutive losses

    // Use dynamic parameter capture instead of hardcoded parameters
    result.parameters = CaptureAllInputParameters();

    TradeData trades[];
    ArrayResize(trades, 0); // Initialize empty array

    return SendTestResultsToServer(result, trades);
}
