#!/usr/bin/env python3
"""
Automated ML Training Pipeline for Multi-Symbol Trading
=======================================================

This script automates the entire process from strategy testing to ML model deployment:
1. Monitors for new strategy test data
2. Trains ML models with 24 universal features (strategy-agnostic)
3. Deploys models to correct MT5 directories
4. Manages parameter files and feature files

Usage:
    python automate_ml_training.py --symbols EURUSD,GBPUSD,XAUUSD,BTCUSD
    python automate_ml_training.py --monitor  # Continuous monitoring mode
"""

import os
import sys
import json
import time
import glob
import shutil
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
import logging

# Configuration constants for file paths and directories
class AutomationConfig:
    """Configuration constants for ML automation paths and directories"""

    # MT5 Common Files structure
    MT5_COMMON_FILES = None  # Will be set dynamically
    EA_DATA_DIR = "SimpleBreakoutML_EA"  # Directory where EA saves data
    MODELS_DIR = "Models/BreakoutStrategy"  # Directory for ML models
    PARAMS_DIR = "BreakoutStrategy"  # Directory for parameter files

    # File patterns
    DATA_FILE_PATTERN = "SimpleBreakoutML_EA_*.json"  # Pattern for data files
    MODEL_FILE_PATTERN = "*.pkl"  # Pattern for model files
    PARAM_FILE_PATTERN = "*.txt"  # Pattern for parameter files
    FEATURE_FILE_PATTERN = "*_feature_names*.pkl"  # Pattern for feature files

    # Cache and logging
    CACHE_FILE = "processed_files_cache.json"  # Cache file for processed files
    LOG_FILE = "ml_automation.log"  # Log file

    # Webserver paths
    WEBSERVER_DIR = "webserver"  # Relative to script location
    ML_MODELS_SOURCE = "ml_models"  # Source directory for trained models

    @classmethod
    def set_mt5_common_files(cls, mt5_path: Path):
        """Set the MT5 Common Files path and update all related paths"""
        cls.MT5_COMMON_FILES = mt5_path
        logger.info(f"🔧 Set MT5 Common Files path: {mt5_path}")

    @classmethod
    def get_ea_data_path(cls) -> Path:
        """Get the EA data directory path"""
        return cls.MT5_COMMON_FILES / cls.EA_DATA_DIR

    @classmethod
    def get_models_path(cls) -> Path:
        """Get the models directory path"""
        return cls.MT5_COMMON_FILES / cls.MODELS_DIR

    @classmethod
    def get_params_path(cls) -> Path:
        """Get the parameters directory path"""
        return cls.MT5_COMMON_FILES / cls.PARAMS_DIR

    @classmethod
    def get_webserver_path(cls) -> Path:
        """Get the webserver directory path"""
        return Path(__file__).parent / cls.WEBSERVER_DIR

    @classmethod
    def get_ml_models_source_path(cls) -> Path:
        """Get the ML models source directory path"""
        return cls.get_webserver_path() / cls.ML_MODELS_SOURCE

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(AutomationConfig.LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class MLTrainingAutomation:
    def __init__(self):
        """Initialize the automation system"""
        # Find and set MT5 Common Files path
        self.mt5_common_files = self._find_mt5_common_files()
        AutomationConfig.set_mt5_common_files(self.mt5_common_files)

        # Load configuration
        self.config = self._load_config()

        # Get symbols and timeframes from config
        self.symbols_to_test = self._get_symbols_from_config()
        self.timeframes = self._get_timeframes_from_config()

        # Test run configuration
        self.test_config = self.config.get("strategy_testing", {
            "start_date": "2023.01.01",
            "end_date": "2024.12.31",
            "optimization": "genetic",
            "initial_deposit": 10000,
            "currency": "USD"
        })

        logger.info(f"🚀 ML Training Automation initialized")
        logger.info(f"📁 MT5 Common Files: {self.mt5_common_files}")
        logger.info(f"📁 EA Data Directory: {AutomationConfig.get_ea_data_path()}")
        logger.info(f"📁 Models Directory: {AutomationConfig.get_models_path()}")
        logger.info(f"📁 Parameters Directory: {AutomationConfig.get_params_path()}")
        logger.info(f"📁 Webserver Directory: {AutomationConfig.get_webserver_path()}")

        # Handle dynamic symbol discovery
        if not self.symbols_to_test:
            self.symbols_to_test = self._discover_symbols_from_data()
            if not self.symbols_to_test:
                logger.warning("⚠️ No symbols found in config or data - using defaults")
                self.symbols_to_test = ["EURUSD+", "XAUUSD+", "BTCUSD+"]

        # Handle dynamic timeframe discovery
        if not self.timeframes:
            logger.info("🔄 Auto-discovering timeframes from data...")
            self.timeframes = ["M5", "M15", "M30", "H1", "H4"]  # Default fallback

        logger.info(f"🎯 Symbols to test: {len(self.symbols_to_test)}")
        logger.info(f"⏰ Timeframes: {self.timeframes}")

    def _find_mt5_common_files(self) -> Path:
        """Find MT5 Common Files directory"""
        possible_paths = [
            Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
            Path.home() / "Library/Application Support/MetaQuotes/Terminal/Common/Files",
            Path.home() / "Documents/MetaTrader 5/MQL5/Files",
            Path.home() / "AppData/Roaming/MetaQuotes/Terminal/Common/Files",
            Path("/Applications/MetaTrader 5.app/Contents/Resources/MQL5/Files")
        ]

        for path in possible_paths:
            if path.exists():
                logger.info(f"✅ Found MT5 directory: {path}")
                return path

        raise FileNotFoundError("MT5 Common Files directory not found")

    def _load_config(self) -> Dict:
        """Load configuration from JSON file"""
        config_file = Path("ml_automation_config.json")
        if not config_file.exists():
            logger.warning(f"Configuration file not found: {config_file}")
            return {}

        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
            logger.info(f"✅ Loaded configuration from {config_file}")
            return config
        except Exception as e:
            logger.error(f"❌ Error loading configuration: {e}")
            return {}

    def _get_symbols_from_config(self) -> List[str]:
        """Get symbols from configuration with dynamic options"""
        symbols = []

        # Check if dynamic mode is enabled
        automation_config = self.config.get("automation", {})
        if automation_config.get("dynamic_mode", False):
            logger.info("🔄 Dynamic mode enabled - will auto-discover symbols from data")
            return []  # Empty list means auto-discover

        # Get symbols from predefined categories
        symbol_config = self.config.get("symbols", {})
        symbol_selection = self.config.get("symbol_selection", {})

        # Use specified categories or all categories
        categories_to_use = symbol_selection.get("categories_to_use", ["forex_majors", "commodities", "crypto"])

        for category in categories_to_use:
            if category in symbol_config:
                symbols.extend(symbol_config[category])

        # Add custom symbols
        symbols.extend(symbol_config.get("custom", []))

        # Apply filters
        exclude_symbols = symbol_selection.get("exclude_symbols", [])
        include_symbols = symbol_selection.get("include_symbols", [])

        # Remove excluded symbols
        symbols = [s for s in symbols if s not in exclude_symbols]

        # Add included symbols
        symbols.extend(include_symbols)

        # Remove duplicates and limit per category
        max_per_category = symbol_selection.get("max_symbols_per_category", 10)
        symbols = list(dict.fromkeys(symbols))[:max_per_category]

        return symbols

    def _get_timeframes_from_config(self) -> List[str]:
        """Get timeframes from configuration with dynamic options"""
        timeframes = []

        # Check if dynamic mode is enabled
        automation_config = self.config.get("automation", {})
        if automation_config.get("auto_discover_timeframes", False):
            logger.info("🔄 Auto-discover timeframes enabled - will detect from data")
            return []  # Empty list means auto-discover

        # Get timeframes from config
        timeframes = self.config.get("timeframes", ["M5", "M15", "M30", "H1", "H4"])
        timeframe_selection = self.config.get("timeframe_selection", {})

        # Use specified timeframes or all timeframes
        timeframes_to_use = timeframe_selection.get("timeframes_to_use", timeframes)

        # Apply filters
        exclude_timeframes = timeframe_selection.get("exclude_timeframes", [])
        include_timeframes = timeframe_selection.get("include_timeframes", [])

        # Remove excluded timeframes
        timeframes = [tf for tf in timeframes_to_use if tf not in exclude_timeframes]

        # Add included timeframes
        timeframes.extend(include_timeframes)

        # Remove duplicates
        timeframes = list(dict.fromkeys(timeframes))

        return timeframes

    def _discover_symbols_from_data(self) -> List[str]:
        """Discover symbols from existing data files"""
        logger.info("🔍 Discovering symbols from existing data files...")

        discovered_symbols = set()
        ea_data_path = AutomationConfig.get_ea_data_path()
        data_pattern = ea_data_path / AutomationConfig.DATA_FILE_PATTERN

        logger.info(f"🔍 Looking for data files in: {ea_data_path}")

        if not ea_data_path.exists():
            logger.warning(f"⚠️ EA data directory does not exist: {ea_data_path}")
            return []

        # Look for data files in the EA data directory and its subdirectories
        for data_file in ea_data_path.rglob(AutomationConfig.DATA_FILE_PATTERN):
            try:
                logger.debug(f"🔍 Reading data file: {data_file}")
                with open(data_file, 'r') as f:
                    data = json.load(f)
                    if isinstance(data, list) and len(data) > 0:
                        for trade in data:
                            if 'symbol' in trade:
                                discovered_symbols.add(trade['symbol'])
                                logger.debug(f"   Found symbol: {trade['symbol']}")
            except Exception as e:
                logger.warning(f"⚠️ Error reading {data_file}: {e}")

        symbols = list(discovered_symbols)
        logger.info(f"✅ Discovered {len(symbols)} symbols from data: {symbols}")
        return symbols

    def create_strategy_tester_batch(self, symbols: List[str], timeframes: List[str]) -> str:
        """Create a batch file for automated strategy testing"""
        batch_content = []
        batch_content.append("@echo off")
        batch_content.append("echo Starting automated strategy testing...")
        batch_content.append("")

        for symbol in symbols:
            for timeframe in timeframes:
                # Create test run ID
                test_run_id = f"{symbol}_{timeframe}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

                # MT5 Strategy Tester command
                cmd = (
                    f'start /wait "" "C:\\Program Files\\MetaTrader 5\\terminal64.exe" '
                    f'/tester:SimpleBreakoutML_EA.ex5,{symbol},{timeframe},'
                    f'{self.test_config["start_date"]},{self.test_config["end_date"]},'
                    f'{self.test_config["optimization"]},{self.test_config["initial_deposit"]},'
                    f'{self.test_config["currency"]} '
                    f'/export:SimpleBreakoutML_EA\\{test_run_id}'
                )
                batch_content.append(cmd)
                batch_content.append(f"echo Completed test for {symbol} {timeframe}")
                batch_content.append("")

        batch_content.append("echo All tests completed!")
        batch_content.append("pause")

        # Save batch file
        batch_file = Path("run_strategy_tests.bat")
        with open(batch_file, 'w') as f:
            f.write('\n'.join(batch_content))

        logger.info(f"📝 Created batch file: {batch_file}")
        return str(batch_file)

    def monitor_for_new_data(self) -> List[Path]:
        """Monitor for new strategy test data files and return test directories"""
        logger.info("🔍 Monitoring for new strategy test data...")

        # Look for new data in SimpleBreakoutML_EA directory using config constants
        ea_data_path = AutomationConfig.get_ea_data_path()
        data_pattern = ea_data_path / AutomationConfig.DATA_FILE_PATTERN

        logger.info(f"🔍 Looking for data files in: {ea_data_path}")
        logger.info(f"🔍 Using pattern: {data_pattern}")

        existing_files = set()

        # Load existing file list
        cache_file = Path(AutomationConfig.CACHE_FILE)
        if cache_file.exists():
            with open(cache_file, 'r') as f:
                existing_files = set(json.load(f))

        # Find current files - look in subdirectories too
        current_files = set()
        if ea_data_path.exists():
            # Look for data files in the EA data directory and its subdirectories
            for data_file in ea_data_path.rglob(AutomationConfig.DATA_FILE_PATTERN):
                current_files.add(str(data_file))
                logger.debug(f"Found data file: {data_file}")
        else:
            logger.warning(f"⚠️ EA data directory does not exist: {ea_data_path}")

        new_files = current_files - existing_files

        if new_files:
            logger.info(f"🆕 Found {len(new_files)} new data files")
            for file in new_files:
                logger.info(f"   📄 {Path(file).name}")
        else:
            logger.info("📭 No new data files found")

        # Update cache
        with open(cache_file, 'w') as f:
            json.dump(list(current_files), f)

        # Group new files by their parent directory (test directory)
        test_directories = set()
        for file_path in new_files:
            test_dir = Path(file_path).parent
            test_directories.add(test_dir)
            logger.debug(f"📁 Grouped file {Path(file_path).name} into test directory: {test_dir.name}")

        logger.info(f"📁 Found {len(test_directories)} test directories with new data")
        for test_dir in test_directories:
            logger.info(f"   📁 {test_dir.name}")

        return list(test_directories)

    def aggregate_test_data(self, test_directories: List[Path]) -> List[Path]:
        """Aggregate data from test directories using aggregate_test_runs.py"""
        logger.info(f"🔄 Aggregating data from {len(test_directories)} test directories...")

        aggregated_files = []

        for test_dir in test_directories:
            try:
                logger.info(f"📁 Processing test directory: {test_dir.name}")

                # Check if both required files exist
                ml_data_file = test_dir / "SimpleBreakoutML_EA_ML_Data.json"
                results_file = test_dir / "SimpleBreakoutML_EA_Results.json"

                if not ml_data_file.exists():
                    logger.warning(f"⚠️ ML data file not found: {ml_data_file}")
                    continue

                if not results_file.exists():
                    logger.warning(f"⚠️ Results file not found: {results_file}")
                    continue

                # Run aggregate_test_runs.py for this specific directory
                aggregated_file = self._run_aggregation_for_directory(test_dir)
                if aggregated_file:
                    aggregated_files.append(aggregated_file)
                    logger.info(f"✅ Aggregated data saved: {aggregated_file.name}")

            except Exception as e:
                logger.error(f"❌ Error aggregating data from {test_dir}: {e}")

        logger.info(f"✅ Completed aggregation for {len(aggregated_files)} directories")
        return aggregated_files

    def _run_aggregation_for_directory(self, test_dir: Path) -> Optional[Path]:
        """Run aggregation for a specific test directory"""
        try:
            # Create a temporary script to aggregate just this directory
            temp_script = self._create_temp_aggregation_script(test_dir)

                        # Run the aggregation script
            cmd = [sys.executable, str(temp_script)]
            logger.info(f"🚀 Running aggregation: {' '.join(cmd)}")

            result = subprocess.run(cmd, capture_output=True, text=True, cwd=Path.cwd())

            if result.returncode == 0:
                logger.info("✅ Aggregation completed successfully")
                if result.stdout:
                    logger.info(f"📋 Output: {result.stdout}")

                # Return the aggregated file path
                aggregated_file = test_dir / "aggregated_ml_data.json"
                if aggregated_file.exists():
                    return aggregated_file
                else:
                    logger.warning(f"⚠️ Aggregated file not found: {aggregated_file}")
                    return None
            else:
                logger.error("❌ Aggregation failed")
                if result.stderr:
                    logger.error(f"📋 Error: {result.stderr}")
                return None

        except Exception as e:
            logger.error(f"❌ Error running aggregation: {e}")
            return None
        finally:
            # Clean up temporary script
            if 'temp_script' in locals():
                try:
                    temp_script.unlink()
                except:
                    pass

    def _create_temp_aggregation_script(self, test_dir: Path) -> Path:
        """Create a temporary aggregation script for a specific directory"""
        script_content = f'''#!/usr/bin/env python3
import json
import os
from pathlib import Path

def aggregate_single_directory(test_dir):
    """Aggregate data from a single test directory"""
    test_dir = Path("{test_dir}")

    # Check for required files
    ml_data_file = test_dir / "SimpleBreakoutML_EA_ML_Data.json"
    results_file = test_dir / "SimpleBreakoutML_EA_Results.json"

    if not ml_data_file.exists() or not results_file.exists():
        print(f"❌ Required files not found in {{test_dir}}")
        return False

    try:
        # Load ML data
        with open(ml_data_file, 'r') as f:
            ml_data = json.load(f)

        # Load results data
        with open(results_file, 'r') as f:
            results_data = json.load(f)

        # Merge the data
        merged_data = {{
            "trades": ml_data.get("trades", []),
            "comprehensive_results": results_data.get("comprehensive_results", []),
            "aggregation_info": {{
                "source_directory": str(test_dir),
                "aggregated_at": "{datetime.now().isoformat()}",
                "ml_data_trades": len(ml_data.get("trades", [])),
                "results_count": len(results_data.get("comprehensive_results", []))
            }}
        }}

        # Save merged data in the same directory
        output_file = test_dir / "aggregated_ml_data.json"
        with open(output_file, 'w') as f:
            json.dump(merged_data, f, indent=2)

        print(f"✅ Aggregated data saved to {{output_file}}")
        return True

    except Exception as e:
        print(f"❌ Error aggregating data: {{e}}")
        return False

if __name__ == "__main__":
    aggregate_single_directory(Path("{test_dir}"))
'''

        # Create temporary script file
        temp_script = Path("temp_aggregation.py")
        with open(temp_script, 'w') as f:
            f.write(script_content)

        return temp_script

    def train_ml_models(self, data_files: List[Path]) -> bool:
        """Train ML models using the improved trainer"""
        if not data_files:
            logger.info("📭 No new data files to process")
            return True

        logger.info(f"🤖 Training ML models for {len(data_files)} data files")

        try:
            # Change to webserver directory using config constants
            webserver_path = AutomationConfig.get_webserver_path()
            logger.info(f"📁 Changing to webserver directory: {webserver_path}")
            os.chdir(webserver_path)

            # Run the improved ML trainer with aggregated data files
            cmd = [sys.executable, "improved_ml_trainer.py", "--data-pattern", "aggregated_ml_data.json"]
            logger.info(f"🚀 Running command: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                logger.info("✅ ML training completed successfully")
                if result.stdout:
                    logger.info(f"📋 Training output: {result.stdout}")
                return True
            else:
                logger.error("❌ ML training failed")
                if result.stderr:
                    logger.error(f"📋 Error output: {result.stderr}")
                return False

        except Exception as e:
            logger.error(f"❌ Error during ML training: {e}")
            return False
        finally:
            # Return to original directory
            original_dir = Path(__file__).parent
            logger.info(f"📁 Returning to original directory: {original_dir}")
            os.chdir(original_dir)

    def deploy_models_to_mt5(self) -> bool:
        """Deploy trained models to MT5 directories"""
        logger.info("📦 Deploying models to MT5 directories...")

        try:
            # Source directories using config constants
            models_source = AutomationConfig.get_ml_models_source_path()
            params_source = AutomationConfig.get_ml_models_source_path()

            # Target directories using config constants
            models_target = AutomationConfig.get_models_path()
            params_target = AutomationConfig.get_params_path()

            logger.info(f"📁 Source models directory: {models_source}")
            logger.info(f"📁 Target models directory: {models_target}")
            logger.info(f"📁 Target parameters directory: {params_target}")

            # Create target directories
            models_target.mkdir(parents=True, exist_ok=True)
            params_target.mkdir(parents=True, exist_ok=True)

            # Deploy models for each symbol and timeframe
            for symbol in self.symbols_to_test:
                symbol_clean = symbol.replace('+', '')  # Remove + suffix

                for timeframe in self.timeframes:
                    # Create symbol/timeframe directory
                    symbol_dir = models_target / symbol_clean / timeframe
                    symbol_dir.mkdir(parents=True, exist_ok=True)

                    logger.info(f"📁 Creating directory: {symbol_dir}")

                    # Copy model files
                    model_patterns = [
                        f"*{symbol_clean}*{timeframe}*.pkl",
                        f"*{symbol_clean}*_improved.pkl",
                        f"*{symbol_clean}*_feature_names*.pkl"
                    ]

                    for pattern in model_patterns:
                        for model_file in models_source.glob(pattern):
                            target_file = symbol_dir / model_file.name
                            shutil.copy2(model_file, target_file)
                            logger.info(f"   📋 Copied {model_file.name} to {symbol_dir}")

                    # Copy parameter files
                    param_patterns = [
                        f"*{symbol_clean}*{timeframe}*.txt",
                        f"*{symbol_clean}*_improved.txt"
                    ]

                    for pattern in param_patterns:
                        for param_file in params_source.glob(pattern):
                            target_file = params_target / param_file.name
                            shutil.copy2(param_file, target_file)
                            logger.info(f"   📋 Copied {param_file.name} to {params_target}")

            logger.info("✅ Model deployment completed")
            return True

        except Exception as e:
            logger.error(f"❌ Error during model deployment: {e}")
            return False

    def fix_missing_generic_models(self) -> bool:
        """Fix missing generic model files by copying symbol-specific models as generic models"""
        logger.info("🔧 Fixing missing generic model files...")

        try:
            models_dir = AutomationConfig.get_models_path()

            for symbol in self.symbols_to_test:
                symbol_clean = symbol.replace('+', '')
                symbol_dir = models_dir / symbol_clean

                if not symbol_dir.exists():
                    logger.info(f"⚠️  Skipping {symbol_clean} - directory doesn't exist")
                    continue

                logger.info(f"📁 Processing {symbol_clean}...")

                for timeframe in self.timeframes:
                    timeframe_dir = symbol_dir / timeframe
                    if not timeframe_dir.exists():
                        continue

                    # Check what models exist for this timeframe
                    existing_files = list(timeframe_dir.glob("*.pkl"))

                    # Find the best models to use as generic models
                    buy_model = None
                    sell_model = None
                    combined_model = None

                    for file in existing_files:
                        if f"buy_model_{symbol_clean}_PERIOD_" in file.name:
                            buy_model = file
                        elif f"sell_model_{symbol_clean}_PERIOD_" in file.name:
                            sell_model = file
                        elif f"combined_model_{symbol_clean}_PERIOD_" in file.name:
                            combined_model = file

                    # Copy models as generic models
                    if buy_model:
                        generic_buy = timeframe_dir / "buy_model.pkl"
                        if not generic_buy.exists():
                            shutil.copy2(buy_model, generic_buy)
                            logger.info(f"   ✅ Created {timeframe}/buy_model.pkl")

                        # Copy corresponding scaler and feature names
                        buy_scaler = buy_model.parent / buy_model.name.replace("model", "scaler")
                        if buy_scaler.exists():
                            generic_scaler = timeframe_dir / "buy_scaler.pkl"
                            if not generic_scaler.exists():
                                shutil.copy2(buy_scaler, generic_scaler)
                                logger.info(f"   ✅ Created {timeframe}/buy_scaler.pkl")

                        buy_features = buy_model.parent / buy_model.name.replace("model", "feature_names")
                        if buy_features.exists():
                            generic_features = timeframe_dir / "buy_feature_names.pkl"
                            if not generic_features.exists():
                                shutil.copy2(buy_features, generic_features)
                                logger.info(f"   ✅ Created {timeframe}/buy_feature_names.pkl")

                    if sell_model:
                        generic_sell = timeframe_dir / "sell_model.pkl"
                        if not generic_sell.exists():
                            shutil.copy2(sell_model, generic_sell)
                            logger.info(f"   ✅ Created {timeframe}/sell_model.pkl")

                        # Copy corresponding scaler and feature names
                        sell_scaler = sell_model.parent / sell_model.name.replace("model", "scaler")
                        if sell_scaler.exists():
                            generic_scaler = timeframe_dir / "sell_scaler.pkl"
                            if not generic_scaler.exists():
                                shutil.copy2(sell_scaler, generic_scaler)
                                logger.info(f"   ✅ Created {timeframe}/sell_scaler.pkl")

                        sell_features = sell_model.parent / sell_model.name.replace("model", "feature_names")
                        if sell_features.exists():
                            generic_features = timeframe_dir / "sell_feature_names.pkl"
                            if not generic_features.exists():
                                shutil.copy2(sell_features, generic_features)
                                logger.info(f"   ✅ Created {timeframe}/sell_feature_names.pkl")

                    if combined_model:
                        generic_combined = timeframe_dir / "combined_model.pkl"
                        if not generic_combined.exists():
                            shutil.copy2(combined_model, generic_combined)
                            logger.info(f"   ✅ Created {timeframe}/combined_model.pkl")

                        # Copy corresponding scaler and feature names
                        combined_scaler = combined_model.parent / combined_model.name.replace("model", "scaler")
                        if combined_scaler.exists():
                            generic_scaler = timeframe_dir / "combined_scaler.pkl"
                            if not generic_scaler.exists():
                                shutil.copy2(combined_scaler, generic_scaler)
                                logger.info(f"   ✅ Created {timeframe}/combined_scaler.pkl")

                        combined_features = combined_model.parent / combined_model.name.replace("model", "feature_names")
                        if combined_features.exists():
                            generic_features = timeframe_dir / "combined_feature_names.pkl"
                            if not generic_features.exists():
                                shutil.copy2(combined_features, generic_features)
                                logger.info(f"   ✅ Created {timeframe}/combined_feature_names.pkl")

            logger.info("✅ Generic model files fixed!")
            return True

        except Exception as e:
            logger.error(f"❌ Error fixing generic model files: {e}")
            return False

    def create_feature_files(self) -> bool:
        """Create feature files with 24 universal features for all symbols/timeframes"""
        logger.info("📝 Creating feature files with 24 universal features...")

        # The 24 universal features (strategy-agnostic)
        complete_features = [
            # Technical indicators (16 features)
            'rsi', 'stoch_main', 'stoch_signal', 'macd_main', 'macd_signal',
            'bb_upper', 'bb_lower', 'williams_r', 'cci', 'momentum', 'force_index',
            # Market conditions (4 features)
            'volume_ratio', 'price_change', 'volatility', 'spread',
            # Time-based features (4 features)
            'session_hour', 'is_news_time', 'day_of_week', 'month'
        ]

        try:
            try:
                import joblib
            except ImportError:
                logger.warning("⚠️ joblib not available, skipping feature file creation")
                return True

            # Create feature files for each symbol and timeframe
            for symbol in self.symbols_to_test:
                symbol_clean = symbol.replace('+', '')

                for timeframe in self.timeframes:
                    # Models directory using config constants
                    models_dir = AutomationConfig.get_models_path() / symbol_clean / timeframe
                    models_dir.mkdir(parents=True, exist_ok=True)

                    logger.info(f"📁 Creating feature files in: {models_dir}")

                    # Create feature names files
                    feature_files = [
                        f"buy_feature_names_{symbol_clean}_PERIOD_{timeframe}.pkl",
                        f"sell_feature_names_{symbol_clean}_PERIOD_{timeframe}.pkl",
                        f"combined_feature_names_{symbol_clean}_PERIOD_{timeframe}.pkl",
                        f"buy_feature_names_{symbol_clean}_improved.pkl",
                        f"sell_feature_names_{symbol_clean}_improved.pkl",
                        f"combined_feature_names_{symbol_clean}_improved.pkl"
                    ]

                    for feature_file in feature_files:
                        file_path = models_dir / feature_file
                        joblib.dump(complete_features, file_path)
                        logger.info(f"   📝 Created {feature_file}")

            logger.info("✅ Feature files created successfully")
            return True

        except Exception as e:
            logger.error(f"❌ Error creating feature files: {e}")
            return False

    def run_full_pipeline(self, symbols: Optional[List[str]] = None) -> bool:
        """Run the complete automation pipeline"""
        if symbols is None:
            symbols = self.symbols_to_test

        logger.info("🚀 Starting full ML training pipeline")
        logger.info(f"🎯 Processing {len(symbols)} symbols")

        try:
            # Step 1: Create strategy tester batch file
            batch_file = self.create_strategy_tester_batch(symbols, self.timeframes)
            logger.info(f"📝 Strategy tester batch file created: {batch_file}")

            # Step 2: Monitor for new data (returns test directories)
            new_test_directories = self.monitor_for_new_data()

            # Step 3: Aggregate data from test directories
            if new_test_directories:
                aggregated_files = self.aggregate_test_data(new_test_directories)
                if not aggregated_files:
                    logger.error("❌ Data aggregation failed")
                    return False

                # Step 4: Train ML models using aggregated data
                success = self.train_ml_models(aggregated_files)
                if not success:
                    logger.error("❌ ML training failed")
                    return False

            # Step 5: Deploy models to MT5
            success = self.deploy_models_to_mt5()
            if not success:
                logger.error("❌ Model deployment failed")
                return False

            # Step 6: Fix missing generic model files
            success = self.fix_missing_generic_models()
            if not success:
                logger.error("❌ Generic model file fixing failed")
                return False

            # Step 7: Create feature files
            success = self.create_feature_files()
            if not success:
                logger.error("❌ Feature file creation failed")
                return False

            logger.info("🎉 Full pipeline completed successfully!")
            return True

        except Exception as e:
            logger.error(f"❌ Pipeline failed: {e}")
            return False

    def monitor_continuous(self, check_interval: int = 300):
        """Continuous monitoring mode"""
        logger.info(f"🔄 Starting continuous monitoring (check every {check_interval}s)")

        try:
            while True:
                logger.info("🔍 Checking for new data...")

                # Monitor for new data (returns test directories)
                new_test_directories = self.monitor_for_new_data()

                if new_test_directories:
                    logger.info(f"🆕 Found {len(new_test_directories)} new test directories")

                    # Aggregate data from test directories
                    aggregated_files = self.aggregate_test_data(new_test_directories)
                    if aggregated_files:
                        # Run training and deployment
                        success = self.train_ml_models(aggregated_files)
                        if success:
                            self.deploy_models_to_mt5()
                            self.create_feature_files()
                            logger.info("✅ Processing completed")
                        else:
                            logger.error("❌ Processing failed")
                    else:
                        logger.error("❌ Data aggregation failed")
                else:
                    logger.info("📭 No new data found")

                logger.info(f"⏰ Waiting {check_interval} seconds...")
                time.sleep(check_interval)

        except KeyboardInterrupt:
            logger.info("🛑 Continuous monitoring stopped by user")
        except Exception as e:
            logger.error(f"❌ Monitoring error: {e}")

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Automated ML Training Pipeline")
    parser.add_argument("--symbols", type=str, help="Comma-separated list of symbols to test")
    parser.add_argument("--monitor", action="store_true", help="Run in continuous monitoring mode")
    parser.add_argument("--interval", type=int, default=300, help="Monitoring interval in seconds")
    parser.add_argument("--timeframes", type=str, default="M5,M15,M30,H1,H4", help="Comma-separated timeframes")

    args = parser.parse_args()

    # Initialize automation
    automation = MLTrainingAutomation()

    # Override symbols if specified
    if args.symbols:
        automation.symbols_to_test = [s.strip() for s in args.symbols.split(",")]

    # Override timeframes if specified
    if args.timeframes:
        automation.timeframes = [t.strip() for t in args.timeframes.split(",")]

    if args.monitor:
        # Continuous monitoring mode
        automation.monitor_continuous(args.interval)
    else:
        # Single run mode
        success = automation.run_full_pipeline()
        if success:
            logger.info("🎉 Automation completed successfully!")
            sys.exit(0)
        else:
            logger.error("❌ Automation failed!")
            sys.exit(1)

if __name__ == "__main__":
    main()
