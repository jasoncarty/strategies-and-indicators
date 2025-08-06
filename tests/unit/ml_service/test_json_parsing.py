#!/usr/bin/env python3
"""
Unit tests for JSON parsing logic used by the EA
"""

import unittest
import json


class TestJSONParsing(unittest.TestCase):
    """Test JSON parsing logic that the EA uses"""

    def test_ml_response_extraction(self):
        """Test that the JSON extraction logic works correctly with actual ML service response format"""

        # Sample ML service response (from the logs)
        sample_response = {
            "metadata": {
                "features_used": 28,
                "loaded_at": "2025-08-03T19:28:08.075326",
                "model_file": "ml_models/buy_model_XAUUSD+_PERIOD_H1.pkl"
            },
            "prediction": {
                "confidence": 0.4921692290812102,
                "direction": "buy",
                "model_key": "buy_XAUUSD+_PERIOD_H1",
                "model_type": "buy",
                "probability": 0.2539153854593949,
                "strategy": "ML_Testing_EA",
                "symbol": "XAUUSD+",
                "timeframe": "H1",
                "timestamp": "2025-08-04T14:53:27.387955"
            },
            "status": "success"
        }

        # Convert to JSON string (as the EA would receive it)
        json_response = json.dumps(sample_response)

        # Simulate the EA's extraction logic
        pred_start = json_response.find('"prediction": {')
        self.assertGreaterEqual(pred_start, 0, "Should find prediction object in response")

        pred_content_start = pred_start + 14  # Skip "prediction": {
        brace_count = 0  # Start at 0, will be incremented when we find the opening brace
        pred_content_end = pred_content_start

        # Find the end of the prediction object by looking for the closing brace
        # that matches the opening brace of the prediction object
        for i in range(pred_content_start, len(json_response)):
            char = json_response[i]
            if char == "{":
                brace_count += 1
            elif char == "}":
                brace_count -= 1
                if brace_count == 0:
                    pred_content_end = i
                    break

        # Extract the prediction object content (include the closing brace)
        prediction_json = json_response[pred_content_start:pred_content_end + 1]

        # Verify the extracted JSON is valid
        try:
            parsed_prediction = json.loads(prediction_json)

            # Check that all essential fields are present
            essential_fields = ['direction', 'probability', 'confidence', 'model_type', 'model_key']
            for field in essential_fields:
                self.assertIn(field, parsed_prediction, f"Essential field '{field}' should be present")

            # Check specific values
            self.assertEqual(parsed_prediction['direction'], 'buy')
            self.assertEqual(parsed_prediction['model_type'], 'buy')
            self.assertEqual(parsed_prediction['model_key'], 'buy_XAUUSD+_PERIOD_H1')
            self.assertAlmostEqual(parsed_prediction['probability'], 0.2539153854593949)
            self.assertAlmostEqual(parsed_prediction['confidence'], 0.4921692290812102)

        except json.JSONDecodeError as e:
            self.fail(f"Extracted JSON should be valid: {e}")

    def test_error_response_handling(self):
        """Test handling of error responses from ML service"""

        # Sample error response
        error_response = {
            "status": "error",
            "message": "Invalid features provided"
        }

        json_response = json.dumps(error_response)

        # Should not find prediction object in error response
        pred_start = json_response.find('"prediction": {')
        self.assertEqual(pred_start, -1, "Should not find prediction object in error response")

    def test_different_symbols_and_timeframes(self):
        """Test JSON extraction with different symbols and timeframes"""

        test_cases = [
            {
                "symbol": "ETHUSD",
                "timeframe": "M5",
                "direction": "sell",
                "model_key": "sell_ETHUSD_PERIOD_M5"
            },
            {
                "symbol": "BTCUSD",
                "timeframe": "H1",
                "direction": "buy",
                "model_key": "buy_BTCUSD_PERIOD_H1"
            },
            {
                "symbol": "XAUUSD+",
                "timeframe": "M15",
                "direction": "sell",
                "model_key": "sell_XAUUSD+_PERIOD_M15"
            }
        ]

        for test_case in test_cases:
            with self.subTest(symbol=test_case["symbol"], timeframe=test_case["timeframe"]):
                sample_response = {
                    "metadata": {
                        "features_used": 28,
                        "loaded_at": "2025-08-03T19:28:08.075326",
                        "model_file": f"ml_models/{test_case['direction']}_model_{test_case['symbol']}_PERIOD_{test_case['timeframe']}.pkl"
                    },
                    "prediction": {
                        "confidence": 0.5,
                        "direction": test_case["direction"],
                        "model_key": test_case["model_key"],
                        "model_type": test_case["direction"],
                        "probability": 0.6,
                        "strategy": "ML_Testing_EA",
                        "symbol": test_case["symbol"],
                        "timeframe": test_case["timeframe"],
                        "timestamp": "2025-08-04T14:53:27.387955"
                    },
                    "status": "success"
                }

                json_response = json.dumps(sample_response)

                # Simulate extraction
                pred_start = json_response.find('"prediction": {')
                self.assertGreaterEqual(pred_start, 0, f"Should find prediction object for {test_case['symbol']}")

                pred_content_start = pred_start + 14
                brace_count = 0
                pred_content_end = pred_content_start

                for i in range(pred_content_start, len(json_response)):
                    char = json_response[i]
                    if char == "{":
                        brace_count += 1
                    elif char == "}":
                        brace_count -= 1
                        if brace_count == 0:
                            pred_content_end = i
                            break

                prediction_json = json_response[pred_content_start:pred_content_end + 1]

                # Verify extraction worked
                parsed_prediction = json.loads(prediction_json)
                self.assertEqual(parsed_prediction['direction'], test_case["direction"])
                self.assertEqual(parsed_prediction['model_key'], test_case["model_key"])
                self.assertEqual(parsed_prediction['symbol'], test_case["symbol"])
                self.assertEqual(parsed_prediction['timeframe'], test_case["timeframe"])

    def test_malformed_json_handling(self):
        """Test handling of malformed JSON responses"""

        # Test with missing prediction object
        malformed_response = {
            "metadata": {"features_used": 28},
            "status": "success"
        }

        json_response = json.dumps(malformed_response)
        pred_start = json_response.find('"prediction": {')
        self.assertEqual(pred_start, -1, "Should not find prediction object in malformed response")

        # Test with incomplete prediction object (manually create malformed JSON)
        incomplete_json = '{"prediction": {"direction": "buy", "status": "success"}'

        # This should raise a JSONDecodeError when trying to parse
        with self.assertRaises(json.JSONDecodeError):
            json.loads(incomplete_json)


if __name__ == '__main__':
    unittest.main()
