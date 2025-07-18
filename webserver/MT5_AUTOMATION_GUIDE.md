# MT5 Automation Guide

This guide explains the MetaTrader 5 automation capabilities in the trading workflow system.

## 🚀 Overview

The automation system now supports **automatic Strategy Tester execution** in MetaTrader 5, eliminating the need for manual configuration and execution.

## 🔧 Automation Methods

### 1. **AutoIt Automation (Windows)**
- **Fully automated** GUI control
- **Requires AutoIt installation**
- **Handles all MT5 interactions automatically**

### 2. **Manual Automation (All Platforms)**
- **Guided manual steps** with clear instructions
- **Reference scripts** for configuration
- **Cross-platform compatibility**

### 3. **MQL Scripting (Future)**
- **Native MT5 automation** using MQL scripts
- **API-based control** (requires MT5 API access)
- **Most reliable method** when available

## 🎯 Usage Options

### **Full Automation (Windows with AutoIt)**
```bash
# Automatically runs Strategy Tester with all settings
./quick_workflow.sh full SimpleBreakoutML_EA

# With custom settings
./quick_workflow.sh full SimpleBreakoutML_EA \
  --symbol EURUSD+ \
  --timeframe M5 \
  --start-date 2023.10.01 \
  --end-date 2023.12.31
```

### **Manual Mode (All Platforms)**
```bash
# Provides step-by-step instructions
./quick_workflow.sh manual SimpleBreakoutML_EA

# Or disable automation explicitly
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --no-automation
```

### **Quick Iteration (Skip Strategy Tester)**
```bash
# Only analyze and train (assumes ST already completed)
./quick_workflow.sh quick SimpleBreakoutML_EA --incremental
```

## 🔧 AutoIt Setup (Windows)

### **Installation**
1. Download AutoIt from: https://www.autoitscript.com/site/
2. Install to default location: `C:\Program Files (x86)\AutoIt3\`
3. Verify installation: `C:\Program Files (x86)\AutoIt3\AutoIt3.exe`

### **Verification**
```bash
# Check if AutoIt is detected
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --validate
```

Expected output:
```
✅ AutoIt automation available: C:\Program Files (x86)\AutoIt3\AutoIt3.exe
```

## 🤖 AutoIt Automation Features

### **What It Does Automatically:**
1. **Launches MT5** if not running
2. **Opens Strategy Tester** (Ctrl+R)
3. **Configures Expert Advisor** selection
4. **Sets Symbol** (e.g., EURUSD+)
5. **Sets Timeframe** (e.g., M5)
6. **Configures Date Range**
7. **Enables Optimization** (if requested)
8. **Sets Optimization Passes** (if optimization mode)
9. **Clicks Start** button
10. **Monitors Progress** until completion

### **Configuration Options:**
```bash
# Basic automation
./quick_workflow.sh full SimpleBreakoutML_EA

# With optimization
./quick_workflow.sh optimize SimpleBreakoutML_EA --optimization-passes 50

# Custom settings
./quick_workflow.sh full SimpleBreakoutML_EA \
  --symbol GBPUSD+ \
  --timeframe H1 \
  --start-date 2023.11.01 \
  --end-date 2023.12.31
```

## 📋 Manual Automation Instructions

### **When AutoIt is Not Available:**
The system provides detailed manual instructions:

```
🤖 Manual MT5 Automation Instructions
==================================================
📋 Configuration Settings:
   Expert Advisor: SimpleBreakoutML_EA
   Symbol: EURUSD+
   Timeframe: M5
   Date Range: 2023.10.01 to 2023.12.31
   Optimization: No

📝 Manual Steps:
1. Open MetaTrader 5
2. Press Ctrl+R to open Strategy Tester
3. Configure the following settings:
   - Expert Advisor: SimpleBreakoutML_EA
   - Symbol: EURUSD+
   - Period: M5
   - Date: 2023.10.01 to 2023.12.31
   - Model: 0
   - Optimization: No
4. Click 'Start'
5. Wait for the test to complete

💡 Automation Tips:
   - Reference MQL script created: /tmp/tmp_script.mq5
   - Consider using MT5's built-in scripting for full automation
   - On Windows, install AutoIt for automated GUI control
```

## 🔄 Workflow Comparison

### **Traditional Manual Process:**
1. Open MT5 manually
2. Navigate to Strategy Tester
3. Configure all settings manually
4. Start test and wait
5. Manually check for completion
6. Analyze results manually
7. Train ML models manually
8. Update EA parameters manually

**Time: ~15-30 minutes per iteration**

### **Automated Process:**
1. Run single command
2. System handles everything automatically
3. Results are analyzed automatically
4. ML models trained automatically
5. EA parameters updated automatically

**Time: ~5-10 minutes per iteration**

### **Quick Iteration Process:**
1. Run single command (assumes ST already completed)
2. System analyzes existing results
3. ML models trained automatically
4. EA parameters updated automatically

**Time: ~2-5 minutes per iteration**

## 🛠️ Technical Details

### **AutoIt Script Generation**
The system automatically generates AutoIt scripts with:
- **Dynamic configuration** based on your settings
- **Error handling** and timeout protection
- **Progress monitoring** and completion detection
- **Cross-platform compatibility** considerations

### **Script Location**
- **Temporary files** created automatically
- **Automatic cleanup** after execution
- **Debug output** for troubleshooting

### **Error Handling**
- **Timeout protection** (1 hour default)
- **Window detection** and validation
- **Fallback mechanisms** for failed operations
- **Detailed logging** for debugging

## 🎯 Platform Support

### **Windows (Full Automation)**
- ✅ AutoIt automation
- ✅ GUI control
- ✅ Full workflow automation
- ✅ Optimization support

### **macOS (Manual Mode)**
- ✅ Manual automation instructions
- ✅ Reference scripts
- ✅ Quick iteration support
- ⚠️ No GUI automation (AutoIt not available)

### **Linux (Manual Mode)**
- ✅ Manual automation instructions
- ✅ Reference scripts
- ✅ Quick iteration support
- ⚠️ No GUI automation (AutoIt not available)

## 💡 Best Practices

### **For Windows Users:**
1. **Install AutoIt** for full automation
2. **Test automation** with simple settings first
3. **Monitor first few runs** to ensure reliability
4. **Use quick iteration** for rapid development

### **For macOS/Linux Users:**
1. **Use manual mode** with clear instructions
2. **Create reference scripts** for common configurations
3. **Use quick iteration** for rapid ML training
4. **Consider Windows VM** for full automation

### **General Tips:**
1. **Start with short date ranges** for quick testing
2. **Use incremental training** for large datasets
3. **Monitor system resources** during optimization
4. **Backup successful configurations**

## 🔧 Troubleshooting

### **AutoIt Issues:**
```bash
# Check AutoIt installation
ls "C:\Program Files (x86)\AutoIt3\AutoIt3.exe"

# Verify in workflow
python automated_trading_workflow.py --ea SimpleBreakoutML_EA --validate
```

### **MT5 Issues:**
```bash
# Check MT5 installation
python automated_trading_workflow.py --validate

# Test manual mode
./quick_workflow.sh manual SimpleBreakoutML_EA
```

### **Common Problems:**
1. **MT5 not found** - Check installation path
2. **AutoIt not detected** - Verify installation
3. **Script timeout** - Increase timeout or check MT5 responsiveness
4. **Window not found** - Ensure MT5 is properly launched

## 🚀 Future Enhancements

### **Planned Features:**
- **MQL API integration** for native MT5 control
- **Web interface** for workflow management
- **Multi-EA batch processing**
- **Advanced analytics** and reporting
- **Cloud-based automation** for remote execution

### **Current Limitations:**
- **AutoIt only works on Windows**
- **GUI automation can be fragile**
- **Requires MT5 to be responsive**
- **Limited to Strategy Tester operations**

## 📞 Support

### **Getting Help:**
1. **Run validation** first: `./quick_workflow.sh validate`
2. **Check documentation** in this guide
3. **Use manual mode** if automation fails
4. **Review error messages** carefully

### **Reporting Issues:**
- **Include platform** (Windows/macOS/Linux)
- **Include AutoIt status** (if applicable)
- **Include error messages** and logs
- **Describe expected vs actual behavior**

---

**The automation system significantly reduces manual work and speeds up your development process!** 🚀

Start with `./quick_workflow.sh validate` to check your setup, then use `./quick_workflow.sh full SimpleBreakoutML_EA` for your first automated workflow. 