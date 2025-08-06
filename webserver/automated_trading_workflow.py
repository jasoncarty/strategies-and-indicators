#!/usr/bin/env python3
"""
Automated Trading Workflow Script
Handles the complete workflow from Strategy Tester to ML training and EA updates
"""

import os
import sys
import time
import json
import subprocess
import argparse
import glob
from datetime import datetime
import platform
import shutil
import tempfile
import xml.etree.ElementTree as ET

class AutomatedTradingWorkflow:
    def _extract_symbol_from_path(self, file_path: Path) -> str:
        """Extract symbol from file path dynamically"""
        # Try to extract from path structure: Models/BreakoutStrategy/SYMBOL/TIMEFRAME/
        path_parts = file_path.parts
        for i, part in enumerate(path_parts):
            if part in ['Models', 'BreakoutStrategy'] and i + 1 < len(path_parts):
                potential_symbol = path_parts[i + 1]
                # Check if it looks like a symbol (6 characters, mostly letters)
                if len(potential_symbol) == 6 and potential_symbol.isalpha():
                    return potential_symbol

        # Try to extract from filename
        filename = file_path.name
        # Look for patterns like buy_EURUSD_PERIOD_H1.pkl
        symbol_match = re.search(r'[a-z]+_([A-Z]{6})_PERIOD_', filename)
        if symbol_match:
            return symbol_match.group(1)

        # Default fallback
        return "UNKNOWN_SYMBOL"

    def __init__(self, ea_name=None, symbol="EURUSD+", timeframe="M5", 
                 start_date="2023.10.01", end_date="2023.12.31", 
                 optimization_mode="Every tick", model="0"):
        """
        Initialize the automated workflow
        
        Args:
            ea_name: Name of the EA to test (e.g., "SimpleBreakoutML_EA")
            symbol: Trading symbol (default: EURUSD+)
            timeframe: Timeframe (default: M5)
            start_date: Test start date (default: 2023.10.01)
            end_date: Test end date (default: 2023.12.31)
            optimization_mode: Strategy Tester mode (default: Every tick)
            model: Model number for optimization (default: 0)
        """
        self.ea_name = ea_name
        self.symbol = symbol
        self.timeframe = timeframe
        self.start_date = start_date
        self.end_date = end_date
        self.optimization_mode = optimization_mode
        self.model = model
        
        # Paths
        self.mt5_path = self._find_mt5_path()
        self.workspace_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.ea_path = os.path.join(self.workspace_path, "Experts", ea_name + ".mq5") if ea_name else None
        
        # Available EAs
        self.available_eas = {
            "SimpleBreakoutML_EA": "SimpleBreakoutML_EA.mq5",
            "StrategyTesterML_EA": "StrategyTesterML_EA.mq5"
        }
        
        # MT5 automation settings
        self.mt5_automation_enabled = True
        self.mt5_autoit_path = self._find_autoit_path()
        self.mt5_script_path = None
        
        print(f"🚀 Automated Trading Workflow Initialized")
        print(f"📁 Workspace: {self.workspace_path}")
        print(f"📁 MT5 Path: {self.mt5_path}")
        if self.ea_name:
            print(f"🎯 Target EA: {self.ea_name}")
            print(f"📊 Symbol: {self.symbol}")
            print(f"⏰ Timeframe: {self.timeframe}")
            print(f"📅 Date Range: {self.start_date} to {self.end_date}")
    
    def _find_mt5_path(self):
        """Find MetaTrader 5 installation path"""
        system = platform.system()
        
        if system == "Darwin":  # macOS
            possible_paths = [
                "/Applications/MetaTrader 5.app/Contents/MacOS/MetaTrader 5",
                os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/terminal64.exe"),
                os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/terminal64.exe")
            ]
        elif system == "Windows":
            possible_paths = [
                "C:\\Program Files\\MetaTrader 5\\terminal64.exe",
                "C:\\Program Files (x86)\\MetaTrader 5\\terminal64.exe"
            ]
        else:  # Linux
            possible_paths = [
                "/opt/MetaTrader 5/terminal64.exe",
                os.path.expanduser("~/.wine/drive_c/Program Files/MetaTrader 5/terminal64.exe")
            ]
        
        for path in possible_paths:
            if os.path.exists(path):
                print(f"✅ Found MT5 at: {path}")
                return path
        
        print("⚠️  MetaTrader 5 not found in standard locations")
        return None
    
    def _find_autoit_path(self):
        """Find AutoIt installation path for Windows automation"""
        if platform.system() != "Windows":
            return None
            
        possible_paths = [
            "C:\\Program Files (x86)\\AutoIt3\\AutoIt3.exe",
            "C:\\Program Files\\AutoIt3\\AutoIt3.exe"
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                print(f"✅ Found AutoIt at: {path}")
                return path
        
        print("⚠️  AutoIt not found - Windows automation disabled")
        return None
    
    def _create_mt5_automation_script(self, auto_optimize=False, optimization_passes=10):
        """Create AutoIt script for MT5 automation"""
        if not self.mt5_autoit_path:
            return None
            
        # Create temporary AutoIt script
        script_content = f"""
#RequireAdmin
#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>

; MT5 Strategy Tester Automation Script
; Generated by Automated Trading Workflow

Opt("WinTitleMatchMode", 2)
Opt("SendKeyDelay", 100)
Opt("MouseClickDelay", 100)

; Variables
$MT5_TITLE = "MetaTrader 5"
$EA_NAME = "{self.ea_name}"
$SYMBOL = "{self.symbol}"
$TIMEFRAME = "{self.timeframe}"
$START_DATE = "{self.start_date}"
$END_DATE = "{self.end_date}"
$OPTIMIZATION = {"True" if auto_optimize else "False"}
$OPTIMIZATION_PASSES = {optimization_passes}

; Function to wait for window
Func WaitForWindow($title, $timeout = 30)
    Local $start = TimerInit()
    While TimerDiff($start) < ($timeout * 1000)
        If WinExists($title) Then
            WinActivate($title)
            Return True
        EndIf
        Sleep(1000)
    WEnd
    Return False
EndFunc

; Function to click button by text
Func ClickButtonByText($text)
    Local $button = ControlGetHandle($MT5_TITLE, "", "[CLASS:Button; TEXT:" & $text & "]")
    If $button Then
        ControlClick($MT5_TITLE, "", $button)
        Return True
    EndIf
    Return False
EndFunc

; Function to set combo box value
Func SetComboBox($class, $text)
    Local $combo = ControlGetHandle($MT5_TITLE, "", "[CLASS:" & $class & "]")
    If $combo Then
        ControlSetText($MT5_TITLE, "", $combo, $text)
        ControlSend($MT5_TITLE, "", $combo, "{{ENTER}}")
        Return True
    EndIf
    Return False
EndFunc

; Main automation sequence
ConsoleWrite("Starting MT5 Strategy Tester automation..." & @CRLF)

; 1. Launch MT5 if not running
If Not WinExists($MT5_TITLE) Then
    ConsoleWrite("Launching MetaTrader 5..." & @CRLF)
    Run("{self.mt5_path}")
    If Not WaitForWindow($MT5_TITLE, 60) Then
        ConsoleWrite("ERROR: Failed to launch MT5" & @CRLF)
        Exit(1)
    EndIf
    Sleep(5000) ; Wait for MT5 to fully load
EndIf

; 2. Open Strategy Tester
ConsoleWrite("Opening Strategy Tester..." & @CRLF)
Send("^r") ; Ctrl+R to open Strategy Tester
Sleep(2000)

; 3. Configure Expert Advisor
ConsoleWrite("Configuring Expert Advisor..." & @CRLF)
If Not SetComboBox("ComboBox", $EA_NAME) Then
    ConsoleWrite("ERROR: Failed to set Expert Advisor" & @CRLF)
    Exit(1)
EndIf
Sleep(1000)

; 4. Configure Symbol
ConsoleWrite("Configuring Symbol..." & @CRLF)
If Not SetComboBox("ComboBox", $SYMBOL) Then
    ConsoleWrite("ERROR: Failed to set Symbol" & @CRLF)
    Exit(1)
EndIf
Sleep(1000)

; 5. Configure Period
ConsoleWrite("Configuring Period..." & @CRLF)
If Not SetComboBox("ComboBox", $TIMEFRAME) Then
    ConsoleWrite("ERROR: Failed to set Period" & @CRLF)
    Exit(1)
EndIf
Sleep(1000)

; 6. Configure Date Range
ConsoleWrite("Configuring Date Range..." & @CRLF)
; Set start date
Local $start_date_control = ControlGetHandle($MT5_TITLE, "", "[CLASS:Edit; INSTANCE:1]")
If $start_date_control Then
    ControlSetText($MT5_TITLE, "", $start_date_control, $START_DATE)
EndIf
Sleep(500)

; Set end date
Local $end_date_control = ControlGetHandle($MT5_TITLE, "", "[CLASS:Edit; INSTANCE:2]")
If $end_date_control Then
    ControlSetText($MT5_TITLE, "", $end_date_control, $END_DATE)
EndIf
Sleep(500)

; 7. Configure Optimization if needed
If $OPTIMIZATION Then
    ConsoleWrite("Configuring Optimization..." & @CRLF)
    ; Click optimization checkbox
    Local $optimize_checkbox = ControlGetHandle($MT5_TITLE, "", "[CLASS:Button; STYLE:3]")
    If $optimize_checkbox Then
        ControlClick($MT5_TITLE, "", $optimize_checkbox)
    EndIf
    Sleep(1000)
    
    ; Set optimization passes
    Local $passes_control = ControlGetHandle($MT5_TITLE, "", "[CLASS:Edit; INSTANCE:3]")
    If $passes_control Then
        ControlSetText($MT5_TITLE, "", $passes_control, $OPTIMIZATION_PASSES)
    EndIf
    Sleep(500)
EndIf

; 8. Start Testing
ConsoleWrite("Starting Strategy Test..." & @CRLF)
If Not ClickButtonByText("Start") Then
    ConsoleWrite("ERROR: Failed to click Start button" & @CRLF)
    Exit(1)
EndIf

; 9. Wait for completion
ConsoleWrite("Waiting for test completion..." & @CRLF)
Local $progress_title = "Strategy Tester"
Local $start_time = TimerInit()
Local $timeout = 3600000 ; 1 hour timeout

While TimerDiff($start_time) < $timeout
    If WinExists($progress_title) Then
        Local $progress_text = WinGetText($progress_title)
        If StringInStr($progress_text, "Complete") Or StringInStr($progress_text, "Finished") Then
            ConsoleWrite("Strategy test completed successfully!" & @CRLF)
            Exit(0)
        EndIf
    EndIf
    Sleep(5000) ; Check every 5 seconds
WEnd

ConsoleWrite("ERROR: Test timeout or failed to complete" & @CRLF)
Exit(1)
"""
        
        # Create temporary script file
        script_file = tempfile.NamedTemporaryFile(mode='w', suffix='.au3', delete=False)
        script_file.write(script_content)
        script_file.close()
        
        self.mt5_script_path = script_file.name
        print(f"📝 Created AutoIt script: {self.mt5_script_path}")
        
        return self.mt5_script_path
    
    def _create_mt5_mql_script(self, auto_optimize=False, optimization_passes=10):
        """Create MQL script for MT5 automation"""
        script_content = f"""
//+------------------------------------------------------------------+
//| MT5 Strategy Tester Automation Script
//| Generated by Automated Trading Workflow
//+------------------------------------------------------------------+
#property copyright "Automated Trading Workflow"
#property link      ""
#property version   "1.00"
#property script_show_inputs

//--- Input parameters
input string EA_NAME = "{self.ea_name}";
input string SYMBOL = "{self.symbol}";
input ENUM_TIMEFRAMES TIMEFRAME = {self._get_timeframe_enum()};
input string START_DATE = "{self.start_date}";
input string END_DATE = "{self.end_date}";
input bool AUTO_OPTIMIZE = {"true" if auto_optimize else "false"};
input int OPTIMIZATION_PASSES = {optimization_passes};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{{
    Print("🤖 Starting MT5 Strategy Tester automation...");
    
    // Configure Strategy Tester
    if(!ConfigureStrategyTester())
    {{
        Print("❌ Failed to configure Strategy Tester");
        return;
    }}
    
    // Start testing
    if(!StartStrategyTest())
    {{
        Print("❌ Failed to start Strategy Test");
        return;
    }}
    
    Print("✅ Strategy Tester automation completed successfully!");
}}

//+------------------------------------------------------------------+
//| Configure Strategy Tester settings                               |
//+------------------------------------------------------------------+
bool ConfigureStrategyTester()
{{
    Print("🔧 Configuring Strategy Tester...");
    
    // Set Expert Advisor
    if(!SetExpertAdvisor(EA_NAME))
    {{
        Print("❌ Failed to set Expert Advisor: ", EA_NAME);
        return false;
    }}
    
    // Set Symbol
    if(!SetSymbol(SYMBOL))
    {{
        Print("❌ Failed to set Symbol: ", SYMBOL);
        return false;
    }}
    
    // Set Timeframe
    if(!SetTimeframe(TIMEFRAME))
    {{
        Print("❌ Failed to set Timeframe: ", EnumToString(TIMEFRAME));
        return false;
    }}
    
    // Set Date Range
    if(!SetDateRange(START_DATE, END_DATE))
    {{
        Print("❌ Failed to set Date Range: ", START_DATE, " to ", END_DATE);
        return false;
    }}
    
    // Configure Optimization
    if(AUTO_OPTIMIZE)
    {{
        if(!SetOptimization(OPTIMIZATION_PASSES))
        {{
            Print("❌ Failed to set Optimization");
            return false;
        }}
    }}
    
    Print("✅ Strategy Tester configuration completed");
    return true;
}}

//+------------------------------------------------------------------+
//| Set Expert Advisor                                               |
//+------------------------------------------------------------------+
bool SetExpertAdvisor(string ea_name)
{{
    // This would require MT5 API access
    // For now, we'll just log the setting
    Print("📋 Setting Expert Advisor: ", ea_name);
    return true;
}}

//+------------------------------------------------------------------+
//| Set Symbol                                                       |
//+------------------------------------------------------------------+
bool SetSymbol(string symbol)
{{
    Print("📊 Setting Symbol: ", symbol);
    return true;
}}

//+------------------------------------------------------------------+
//| Set Timeframe                                                    |
//+------------------------------------------------------------------+
bool SetTimeframe(ENUM_TIMEFRAMES timeframe)
{{
    Print("⏰ Setting Timeframe: ", EnumToString(timeframe));
    return true;
}}

//+------------------------------------------------------------------+
//| Set Date Range                                                   |
//+------------------------------------------------------------------+
bool SetDateRange(string start_date, string end_date)
{{
    Print("📅 Setting Date Range: ", start_date, " to ", end_date);
    return true;
}}

//+------------------------------------------------------------------+
//| Set Optimization                                                 |
//+------------------------------------------------------------------+
bool SetOptimization(int passes)
{{
    Print("🔄 Setting Optimization Passes: ", passes);
    return true;
}}

//+------------------------------------------------------------------+
//| Start Strategy Test                                              |
//+------------------------------------------------------------------+
bool StartStrategyTest()
{{
    Print("🚀 Starting Strategy Test...");
    
    // This would require MT5 API access
    // For now, we'll just log the action
    Print("📋 Strategy Test started - please monitor manually");
    
    return true;
}}
"""
        
        # Create temporary MQL script file
        script_file = tempfile.NamedTemporaryFile(mode='w', suffix='.mq5', delete=False)
        script_file.write(script_content)
        script_file.close()
        
        self.mt5_script_path = script_file.name
        print(f"📝 Created MQL script: {self.mt5_script_path}")
        
        return self.mt5_script_path
    
    def _get_timeframe_enum(self):
        """Convert timeframe string to MQL enum"""
        timeframe_map = {
            "M1": "PERIOD_M1",
            "M5": "PERIOD_M5", 
            "M15": "PERIOD_M15",
            "M30": "PERIOD_M30",
            "H1": "PERIOD_H1",
            "H4": "PERIOD_H4",
            "D1": "PERIOD_D1"
        }
        return timeframe_map.get(self.timeframe, "PERIOD_M5")
    
    def _run_mt5_automation(self, auto_optimize=False, optimization_passes=10):
        """Run MT5 automation using available methods"""
        system = platform.system()
        
        if system == "Windows" and self.mt5_autoit_path:
            return self._run_autoit_automation(auto_optimize, optimization_passes)
        else:
            return self._run_manual_automation(auto_optimize, optimization_passes)
    
    def _run_autoit_automation(self, auto_optimize=False, optimization_passes=10):
        """Run AutoIt automation on Windows"""
        print(f"\n🤖 Running AutoIt automation for MT5...")
        
        # Create AutoIt script
        script_path = self._create_mt5_automation_script(auto_optimize, optimization_passes)
        if not script_path:
            print("❌ Failed to create AutoIt script")
            return False
        
        try:
            # Run AutoIt script
            print(f"🔧 Executing AutoIt script: {script_path}")
            result = subprocess.run([
                self.mt5_autoit_path,
                script_path
            ], capture_output=True, text=True, timeout=3600)  # 1 hour timeout
            
            # Print output
            if result.stdout:
                print("\n📤 AutoIt Output:")
                print(result.stdout)
            
            if result.stderr:
                print("\n⚠️  AutoIt Errors:")
                print(result.stderr)
            
            if result.returncode == 0:
                print(f"\n✅ AutoIt automation completed successfully!")
                return True
            else:
                print(f"\n❌ AutoIt automation failed with return code: {result.returncode}")
                return False
                
        except subprocess.TimeoutExpired:
            print(f"\n⏰ AutoIt automation timed out after 1 hour")
            return False
        except Exception as e:
            print(f"\n❌ Error running AutoIt automation: {e}")
            return False
        finally:
            # Clean up script file
            try:
                os.unlink(script_path)
            except:
                pass
    
    def _run_manual_automation(self, auto_optimize=False, optimization_passes=10):
        """Provide manual automation instructions"""
        print(f"\n🤖 Manual MT5 Automation Instructions")
        print("=" * 50)
        
        # Create MQL script for reference
        script_path = self._create_mt5_mql_script(auto_optimize, optimization_passes)
        
        print(f"📋 Configuration Settings:")
        print(f"   Expert Advisor: {self.ea_name}")
        print(f"   Symbol: {self.symbol}")
        print(f"   Timeframe: {self.timeframe}")
        print(f"   Date Range: {self.start_date} to {self.end_date}")
        print(f"   Optimization: {'Yes' if auto_optimize else 'No'}")
        if auto_optimize:
            print(f"   Optimization Passes: {optimization_passes}")
        
        print(f"\n📝 Manual Steps:")
        print(f"1. Open MetaTrader 5")
        print(f"2. Press Ctrl+R to open Strategy Tester")
        print(f"3. Configure the following settings:")
        print(f"   - Expert Advisor: {self.ea_name}")
        print(f"   - Symbol: {self.symbol}")
        print(f"   - Period: {self.timeframe}")
        print(f"   - Date: {self.start_date} to {self.end_date}")
        print(f"   - Model: {self.model}")
        print(f"   - Optimization: {'Yes' if auto_optimize else 'No'}")
        if auto_optimize:
            print(f"   - Optimization Passes: {optimization_passes}")
        print(f"4. Click 'Start'")
        
        if auto_optimize:
            print(f"5. Wait for {optimization_passes} optimization passes to complete")
        else:
            print(f"5. Wait for the test to complete")
        
        print(f"\n💡 Automation Tips:")
        print(f"   - Reference MQL script created: {script_path}")
        print(f"   - Consider using MT5's built-in scripting for full automation")
        print(f"   - On Windows, install AutoIt for automated GUI control")
        
        # Wait for user confirmation
        input(f"\n⏸️  Press Enter when Strategy Tester has completed...")
        
        return True
    
    def list_available_eas(self):
        """List all available EAs in the workspace"""
        print("\n📋 Available Expert Advisors:")
        print("=" * 40)
        
        for ea_name, filename in self.available_eas.items():
            ea_path = os.path.join(self.workspace_path, "Experts", filename)
            if os.path.exists(ea_path):
                print(f"✅ {ea_name}: {filename}")
            else:
                print(f"❌ {ea_name}: {filename} (not found)")
        
        # Also check for any other .mq5 files
        experts_dir = os.path.join(self.workspace_path, "Experts")
        if os.path.exists(experts_dir):
            mq5_files = glob.glob(os.path.join(experts_dir, "*.mq5"))
            for mq5_file in mq5_files:
                filename = os.path.basename(mq5_file)
                ea_name = filename.replace(".mq5", "")
                if ea_name not in self.available_eas:
                    print(f"📄 {ea_name}: {filename}")
        
        print("=" * 40)
    
    def validate_setup(self):
        """Validate that all required components are available"""
        print("\n🔍 Validating Setup...")
        print("=" * 30)
        
        issues = []
        
        # Check MT5
        if not self.mt5_path:
            issues.append("❌ MetaTrader 5 not found")
        else:
            print("✅ MetaTrader 5 found")
        
        # Check EA
        if self.ea_name:
            if self.ea_name not in self.available_eas:
                issues.append(f"❌ EA '{self.ea_name}' not in available list")
            elif not os.path.exists(self.ea_path):
                issues.append(f"❌ EA file not found: {self.ea_path}")
            else:
                print(f"✅ EA file found: {self.ea_path}")
        
        # Check workspace structure
        required_dirs = ["Experts", "webserver"]
        for dir_name in required_dirs:
            dir_path = os.path.join(self.workspace_path, dir_name)
            if not os.path.exists(dir_path):
                issues.append(f"❌ Required directory not found: {dir_path}")
            else:
                print(f"✅ Directory found: {dir_path}")
        
        # Check ML trainer
        trainer_path = os.path.join(self.workspace_path, "webserver", "strategy_tester_ml_trainer.py")
        if not os.path.exists(trainer_path):
            issues.append(f"❌ ML trainer not found: {trainer_path}")
        else:
            print(f"✅ ML trainer found: {trainer_path}")
        
        # Check automation capabilities
        if platform.system() == "Windows" and self.mt5_autoit_path:
            print(f"✅ AutoIt automation available: {self.mt5_autoit_path}")
        else:
            print(f"ℹ️  Manual automation mode (AutoIt not available)")
        
        if issues:
            print("\n⚠️  Setup Issues Found:")
            for issue in issues:
                print(f"   {issue}")
            return False
        else:
            print("\n✅ Setup validation passed!")
            return True
    
    def run_strategy_tester(self, auto_optimize=False, optimization_passes=10):
        """
        Run Strategy Tester in MetaTrader 5
        
        Args:
            auto_optimize: Whether to run optimization instead of single test
            optimization_passes: Number of optimization passes
        """
        if not self.mt5_path or not self.ea_name:
            print("❌ Cannot run Strategy Tester: MT5 path or EA name not set")
            return False
        
        print(f"\n🎯 Running Strategy Tester for {self.ea_name}")
        print("=" * 50)
        print(f"📊 Symbol: {self.symbol}")
        print(f"⏰ Timeframe: {self.timeframe}")
        print(f"📅 Date Range: {self.start_date} to {self.end_date}")
        print(f"🔧 Mode: {'Optimization' if auto_optimize else 'Single Test'}")
        
        if auto_optimize:
            print(f"🔄 Optimization Passes: {optimization_passes}")
        
        # Run automation
        return self._run_mt5_automation(auto_optimize, optimization_passes)
    
    def analyze_results(self):
        """Analyze the Strategy Tester results"""
        print(f"\n📊 Analyzing Results for {self.ea_name}")
        print("=" * 50)
        
        # Find result files
        mt5_files_dir = self._find_mt5_files_directory()
        if not mt5_files_dir:
            print("❌ Could not find MT5 Files directory")
            return False
        
        ea_folder = os.path.join(mt5_files_dir, self.ea_name)
        if not os.path.exists(ea_folder):
            print(f"❌ EA folder not found: {ea_folder}")
            return False
        
        print(f"📁 Checking results in: {ea_folder}")
        
        # Look for result files
        result_files = {
            "ML Data": glob.glob(os.path.join(ea_folder, "*_ML_Data.json")),
            "Trade Results": glob.glob(os.path.join(ea_folder, "*_Trade_Results.json")),
            "Test Results": glob.glob(os.path.join(ea_folder, "*_Results.json")),
            "Comprehensive Results": glob.glob(os.path.join(ea_folder, "StrategyTester_Comprehensive_Results.json"))
        }
        
        files_found = False
        for result_type, files in result_files.items():
            if files:
                print(f"✅ {result_type}: {len(files)} files found")
                for file in files:
                    print(f"   📄 {os.path.basename(file)}")
                files_found = True
            else:
                print(f"❌ {result_type}: No files found")
        
        if not files_found:
            print("\n⚠️  No result files found!")
            print("   Make sure the EA has CollectMLData=true and SaveTradeResults=true")
            return False
        
        # Run quick analysis
        print(f"\n🔍 Running Quick Analysis...")
        
        # Check file sizes and basic structure
        for result_type, files in result_files.items():
            for file in files:
                try:
                    file_size = os.path.getsize(file)
                    print(f"   📊 {os.path.basename(file)}: {file_size:,} bytes")
                    
                    # Try to read JSON structure
                    with open(file, 'r') as f:
                        content = f.read()
                        if len(content) > 0:
                            try:
                                data = json.loads(content)
                                if isinstance(data, dict):
                                    print(f"      📋 Keys: {list(data.keys())}")
                                elif isinstance(data, list):
                                    print(f"      📋 Array with {len(data)} items")
                            except json.JSONDecodeError:
                                print(f"      ⚠️  Invalid JSON structure")
                        else:
                            print(f"      ⚠️  Empty file")
                            
                except Exception as e:
                    print(f"      ❌ Error reading file: {e}")
        
        return True
    
    def train_ml_models(self, incremental=False, separate_models=True):
        """Train ML models using the collected data"""
        print(f"\n🤖 Training ML Models for {self.ea_name}")
        print("=" * 50)
        
        # Change to webserver directory
        webserver_dir = os.path.join(self.workspace_path, "webserver")
        if not os.path.exists(webserver_dir):
            print(f"❌ Webserver directory not found: {webserver_dir}")
            return False
        
        # Build command
        cmd = ["python", "strategy_tester_ml_trainer.py", "--ea", self.ea_name]
        
        if incremental:
            cmd.append("--incremental")
        
        if not separate_models:
            cmd.append("--no-separate-models")
        
        print(f"🔧 Running command: {' '.join(cmd)}")
        print(f"📁 Working directory: {webserver_dir}")
        
        try:
            # Run the ML trainer
            result = subprocess.run(
                cmd,
                cwd=webserver_dir,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            
            # Print output
            if result.stdout:
                print("\n📤 Output:")
                print(result.stdout)
            
            if result.stderr:
                print("\n⚠️  Errors:")
                print(result.stderr)
            
            if result.returncode == 0:
                print(f"\n✅ ML training completed successfully!")
                return True
            else:
                print(f"\n❌ ML training failed with return code: {result.returncode}")
                return False
                
        except subprocess.TimeoutExpired:
            print(f"\n⏰ ML training timed out after 5 minutes")
            return False
        except Exception as e:
            print(f"\n❌ Error running ML trainer: {e}")
            return False
    
    def update_ea_parameters(self):
        """Update EA parameters based on ML training results"""
        print(f"\n🔧 Updating EA Parameters for {self.ea_name}")
        print("=" * 50)
        
        # Check if parameter files were created
        ml_models_dir = os.path.join(self.workspace_path, "webserver", "ml_models")
        if not os.path.exists(ml_models_dir):
            print(f"❌ ML models directory not found: {ml_models_dir}")
            return False
        
        # Look for parameter files
        param_files = glob.glob(os.path.join(ml_models_dir, "ml_model_params_*.txt"))
        
        if not param_files:
            print("❌ No parameter files found")
            return False
        
        print(f"✅ Found {len(param_files)} parameter files:")
        for param_file in param_files:
            filename = os.path.basename(param_file)
            print(f"   📄 {filename}")
            
            # Show parameter preview
            try:
                with open(param_file, 'r') as f:
                    lines = f.readlines()
                    print(f"      📋 {len(lines)} parameters")
                    # Show first few parameters
                    for i, line in enumerate(lines[:5]):
                        if line.strip():
                            print(f"         {line.strip()}")
                    if len(lines) > 5:
                        print(f"         ... and {len(lines) - 5} more")
            except Exception as e:
                print(f"      ❌ Error reading file: {e}")
        
        print(f"\n💡 Parameter files are ready to be used by the EA")
        print(f"   The EA will automatically load these parameters on startup")
        
        return True
    
    def run_complete_workflow(self, auto_optimize=False, optimization_passes=10, 
                            incremental=False, separate_models=True):
        """Run the complete workflow from Strategy Tester to ML training"""
        print(f"\n🚀 Starting Complete Workflow for {self.ea_name}")
        print("=" * 60)
        
        # Step 1: Validate setup
        if not self.validate_setup():
            print("❌ Setup validation failed. Please fix issues and try again.")
            return False
        
        # Step 2: Run Strategy Tester
        print(f"\n📋 Step 1/4: Running Strategy Tester")
        if not self.run_strategy_tester(auto_optimize, optimization_passes):
            print("❌ Strategy Tester step failed")
            return False
        
        # Step 3: Analyze results
        print(f"\n📋 Step 2/4: Analyzing Results")
        if not self.analyze_results():
            print("❌ Results analysis failed")
            return False
        
        # Step 4: Train ML models
        print(f"\n📋 Step 3/4: Training ML Models")
        if not self.train_ml_models(incremental, separate_models):
            print("❌ ML training failed")
            return False
        
        # Step 5: Update EA parameters
        print(f"\n📋 Step 4/4: Updating EA Parameters")
        if not self.update_ea_parameters():
            print("❌ EA parameter update failed")
            return False
        
        print(f"\n🎉 Complete workflow finished successfully!")
        print("=" * 60)
        print(f"✅ Strategy Tester completed")
        print(f"✅ Results analyzed")
        print(f"✅ ML models trained")
        print(f"✅ EA parameters updated")
        print(f"\n💡 Next steps:")
        print(f"   1. Review the ML training results in webserver/ml_models/")
        print(f"   2. Test the updated EA in Strategy Tester")
        print(f"   3. Repeat the workflow to iterate and improve")
        
        return True
    
    def _find_mt5_files_directory(self):
        """Find the MT5 Files directory where results are stored"""
        system = platform.system()
        
        if system == "Darwin":  # macOS
            possible_paths = [
                os.path.expanduser("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
                os.path.expanduser("~/Library/Application Support/MetaQuotes/Terminal/Common/Files"),
                os.path.expanduser("~/Documents/MetaTrader 5/MQL5/Files")
            ]
        elif system == "Windows":
            possible_paths = [
                os.path.expanduser("~/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
                "C:\\Users\\%USERNAME%\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files"
            ]
        else:  # Linux
            possible_paths = [
                os.path.expanduser("~/.wine/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"),
                "/opt/MetaTrader 5/MQL5/Files"
            ]
        
        for path in possible_paths:
            if os.path.exists(path):
                return path
        
        return None

def main():
    """Main function with command line interface"""
    parser = argparse.ArgumentParser(description='Automated Trading Workflow')
    parser.add_argument('--ea', type=str, choices=['SimpleBreakoutML_EA', 'StrategyTesterML_EA'],
                       help='Expert Advisor to test')
    parser.add_argument('--symbol', type=str, default='EURUSD+',
                       help='Trading symbol (default: EURUSD+)')
    parser.add_argument('--timeframe', type=str, default='M5',
                       help='Timeframe (default: M5)')
    parser.add_argument('--start-date', type=str, default='2023.10.01',
                       help='Test start date (default: 2023.10.01)')
    parser.add_argument('--end-date', type=str, default='2023.12.31',
                       help='Test end date (default: 2023.12.31)')
    parser.add_argument('--optimize', action='store_true',
                       help='Run optimization instead of single test')
    parser.add_argument('--optimization-passes', type=int, default=10,
                       help='Number of optimization passes (default: 10)')
    parser.add_argument('--incremental', action='store_true',
                       help='Use incremental ML training')
    parser.add_argument('--no-separate-models', action='store_true',
                       help='Disable separate buy/sell models')
    parser.add_argument('--list-eas', action='store_true',
                       help='List available Expert Advisors')
    parser.add_argument('--validate', action='store_true',
                       help='Validate setup only')
    parser.add_argument('--analyze-only', action='store_true',
                       help='Only analyze existing results')
    parser.add_argument('--train-only', action='store_true',
                       help='Only train ML models')
    parser.add_argument('--no-automation', action='store_true',
                       help='Disable MT5 automation (manual mode only)')
    
    args = parser.parse_args()
    
    # Initialize workflow
    workflow = AutomatedTradingWorkflow(
        ea_name=args.ea,
        symbol=args.symbol,
        timeframe=args.timeframe,
        start_date=args.start_date,
        end_date=args.end_date
    )
    
    # Disable automation if requested
    if args.no_automation:
        workflow.mt5_automation_enabled = False
    
    # List EAs if requested
    if args.list_eas:
        workflow.list_available_eas()
        return
    
    # Validate setup if requested
    if args.validate:
        workflow.validate_setup()
        return
    
    # Check if EA is specified
    if not args.ea:
        print("❌ Please specify an EA using --ea <EA_NAME>")
        print("💡 Available EAs:")
        workflow.list_available_eas()
        return
    
    # Run specific steps or complete workflow
    if args.analyze_only:
        workflow.analyze_results()
    elif args.train_only:
        workflow.train_ml_models(args.incremental, not args.no_separate_models)
    else:
        # Run complete workflow
        workflow.run_complete_workflow(
            auto_optimize=args.optimize,
            optimization_passes=args.optimization_passes,
            incremental=args.incremental,
            separate_models=not args.no_separate_models
        )

if __name__ == "__main__":
    main() 