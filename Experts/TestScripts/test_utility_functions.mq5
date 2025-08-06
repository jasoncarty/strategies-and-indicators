//+------------------------------------------------------------------+
//|                                    test_utility_functions.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

// Include the files we want to test
#include "../ML/MachineLearningUtils.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("🧪 Starting Utility Function Tests...");

    // Test 1: Feature calculation functions
    TestFeatureCalculations();

    // Test 2: JSON serialization functions
    TestJsonSerialization();

    // Test 3: Time and date functions
    TestTimeFunctions();

    // Test 4: String manipulation functions
    TestStringFunctions();

    Print("✅ Utility Function Tests Complete!");
}

//+------------------------------------------------------------------+
//| Test feature calculation functions                               |
//+------------------------------------------------------------------+
void TestFeatureCalculations()
{
    Print("📋 Test 1: Feature Calculations");

    // Test RSI calculation
    double rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE, 0);
    if(rsi >= 0 && rsi <= 100) {
        Print("✅ RSI calculation: ", DoubleToString(rsi, 2));
    } else {
        Print("❌ RSI calculation failed: ", DoubleToString(rsi, 2));
    }

    // Test Stochastic calculation
    double stoch_main, stoch_signal;
    if(iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH, 0, stoch_main, stoch_signal)) {
        Print("✅ Stochastic calculation: Main=", DoubleToString(stoch_main, 2), ", Signal=", DoubleToString(stoch_signal, 2));
    } else {
        Print("❌ Stochastic calculation failed");
    }

    // Test MACD calculation
    double macd_main, macd_signal, macd_hist;
    if(iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, 0, macd_main, macd_signal, macd_hist)) {
        Print("✅ MACD calculation: Main=", DoubleToString(macd_main, 5), ", Signal=", DoubleToString(macd_signal, 5));
    } else {
        Print("❌ MACD calculation failed");
    }
}

//+------------------------------------------------------------------+
//| Test JSON serialization functions                                |
//+------------------------------------------------------------------+
void TestJsonSerialization()
{
    Print("📋 Test 2: JSON Serialization");

    // Test MLFeatures struct serialization
    MLFeatures features;
    features.rsi = 50.5;
    features.stoch_main = 75.2;
    features.stoch_signal = 70.1;
    features.macd_main = 0.00123;
    features.macd_signal = 0.00098;
    features.bb_upper = 1.2345;
    features.bb_lower = 1.2100;
    features.williams_r = -25.5;
    features.cci = 125.8;
    features.momentum = 1.0012;
    features.volume_ratio = 1.15;
    features.price_change = 0.0023;
    features.volatility = 0.0156;
    features.force_index = 1250000;
    features.spread = 0.0001;
    features.session_hour = 14;
    features.is_news_time = false;
    features.day_of_week = 3;
    features.month = 8;

    string json_result = MLFeaturesStructToJson(features);
    Print("✅ MLFeatures JSON: ", json_result);

    // Test MarketConditionsData struct serialization
    MarketConditionsData market_data;
    market_data.trade_id = 123456789;
    market_data.symbol = _Symbol;
    market_data.timeframe = EnumToString(Period());
    market_data.rsi = 55.5;
    market_data.stoch_main = 65.2;
    market_data.stoch_signal = 60.1;
    market_data.macd_main = 0.00234;
    market_data.macd_signal = 0.00187;
    market_data.bb_upper = 1.2456;
    market_data.bb_lower = 1.2156;
    market_data.williams_r = -30.5;
    market_data.cci = 115.8;
    market_data.momentum = 1.0023;
    market_data.volume_ratio = 1.25;
    market_data.price_change = 0.0034;
    market_data.volatility = 0.0189;
    market_data.force_index = 1350000;
    market_data.spread = 0.0002;
    market_data.session_hour = 15;
    market_data.is_news_time = false;
    market_data.day_of_week = 3;
    market_data.month = 8;

    string market_json = MarketConditionsStructToJson(market_data);
    Print("✅ MarketConditions JSON: ", market_json);
}

//+------------------------------------------------------------------+
//| Test time and date functions                                     |
//+------------------------------------------------------------------+
void TestTimeFunctions()
{
    Print("📋 Test 3: Time Functions");

    // Test current time
    datetime current_time = TimeCurrent();
    Print("✅ Current time: ", TimeToString(current_time));

    // Test day of week
    int day_of_week = TimeDayOfWeek(current_time);
    Print("✅ Day of week: ", day_of_week, " (0=Sunday, 6=Saturday)");

    // Test month
    int month = TimeMonth(current_time);
    Print("✅ Month: ", month);

    // Test session hour
    int hour = TimeHour(current_time);
    Print("✅ Hour: ", hour);
}

//+------------------------------------------------------------------+
//| Test string manipulation functions                               |
//+------------------------------------------------------------------+
void TestStringFunctions()
{
    Print("📋 Test 4: String Functions");

    // Test string concatenation
    string symbol = _Symbol;
    string timeframe = EnumToString(Period());
    string combined = symbol + "_" + timeframe;
    Print("✅ String concatenation: ", combined);

    // Test string length
    int length = StringLen(combined);
    Print("✅ String length: ", length);

    // Test string find
    int pos = StringFind(combined, "_");
    if(pos >= 0) {
        Print("✅ String find '_' at position: ", pos);
    } else {
        Print("❌ String find failed");
    }

    // Test string substring
    string first_part = StringSubstr(combined, 0, pos);
    string second_part = StringSubstr(combined, pos + 1);
    Print("✅ String substring: '", first_part, "' and '", second_part, "'");
}
