//+------------------------------------------------------------------+
//|                                           test_json_parsing.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property script_show_inputs

// Include the files we want to test
#include "../ML/MLHttpInterface.mqh"
#include "../ML/MachineLearningUtils.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("🧪 Starting JSON Parsing Tests...");

    // Test 1: Valid ML response
    TestValidMLResponse();

    // Test 2: Error response
    TestErrorResponse();

    // Test 3: Malformed response
    TestMalformedResponse();

    // Test 4: Different symbols
    TestDifferentSymbols();

    Print("✅ JSON Parsing Tests Complete!");
}

//+------------------------------------------------------------------+
//| Test valid ML service response                                   |
//+------------------------------------------------------------------+
void TestValidMLResponse()
{
    Print("📋 Test 1: Valid ML Response");

    string valid_response = "{\"metadata\":{\"features_used\":28,\"loaded_at\":\"2025-08-03T19:28:08.075326\",\"model_file\":\"ml_models/buy_model_XAUUSD+_PERIOD_H1.pkl\"},\"prediction\":{\"confidence\":0.4921692290812102,\"direction\":\"buy\",\"model_key\":\"buy_XAUUSD+_PERIOD_H1\",\"model_type\":\"buy\",\"probability\":0.2539153854593949,\"strategy\":\"ML_Testing_EA\",\"symbol\":\"XAUUSD+\",\"timeframe\":\"H1\",\"timestamp\":\"2025-08-04T14:53:27.387955\"},\"status\":\"success\"}";

    MLPrediction prediction = ParseJsonResponse(valid_response);

    if(prediction.is_valid) {
        Print("✅ Valid response parsed successfully");
        Print("   Direction: ", prediction.direction);
        Print("   Probability: ", DoubleToString(prediction.probability, 4));
        Print("   Confidence: ", DoubleToString(prediction.confidence, 4));
        Print("   Model Type: ", prediction.model_type);
        Print("   Model Key: ", prediction.model_key);
    } else {
        Print("❌ Failed to parse valid response: ", prediction.error_message);
    }
}

//+------------------------------------------------------------------+
//| Test error response from ML service                              |
//+------------------------------------------------------------------+
void TestErrorResponse()
{
    Print("📋 Test 2: Error Response");

    string error_response = "{\"status\":\"error\",\"message\":\"Invalid features provided\"}";

    MLPrediction prediction = ParseJsonResponse(error_response);

    if(!prediction.is_valid) {
        Print("✅ Error response handled correctly: ", prediction.error_message);
    } else {
        Print("❌ Error response should not be valid");
    }
}

//+------------------------------------------------------------------+
//| Test malformed response                                          |
//+------------------------------------------------------------------+
void TestMalformedResponse()
{
    Print("📋 Test 3: Malformed Response");

    string malformed_response = "{\"metadata\":{\"features_used\":28},\"status\":\"success\"}";

    MLPrediction prediction = ParseJsonResponse(malformed_response);

    if(!prediction.is_valid) {
        Print("✅ Malformed response handled correctly: ", prediction.error_message);
    } else {
        Print("❌ Malformed response should not be valid");
    }
}

//+------------------------------------------------------------------+
//| Test different symbols and timeframes                            |
//+------------------------------------------------------------------+
void TestDifferentSymbols()
{
    Print("📋 Test 4: Different Symbols");

    string test_cases[] = {
        "{\"prediction\":{\"confidence\":0.5,\"direction\":\"sell\",\"model_key\":\"sell_ETHUSD_PERIOD_M5\",\"model_type\":\"sell\",\"probability\":0.6,\"strategy\":\"ML_Testing_EA\",\"symbol\":\"ETHUSD\",\"timeframe\":\"M5\",\"timestamp\":\"2025-08-04T14:53:27.387955\"},\"status\":\"success\"}",
        "{\"prediction\":{\"confidence\":0.7,\"direction\":\"buy\",\"model_key\":\"buy_BTCUSD_PERIOD_H1\",\"model_type\":\"buy\",\"probability\":0.8,\"strategy\":\"ML_Testing_EA\",\"symbol\":\"BTCUSD\",\"timeframe\":\"H1\",\"timestamp\":\"2025-08-04T14:53:27.387955\"},\"status\":\"success\"}"
    };

    for(int i = 0; i < ArraySize(test_cases); i++) {
        MLPrediction prediction = ParseJsonResponse(test_cases[i]);

        if(prediction.is_valid) {
            Print("✅ Symbol test ", i+1, " passed - Direction: ", prediction.direction, ", Symbol: ", prediction.model_key);
        } else {
            Print("❌ Symbol test ", i+1, " failed: ", prediction.error_message);
        }
    }
}
