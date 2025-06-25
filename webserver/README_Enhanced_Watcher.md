# Enhanced File Watcher for MT5 Strategy Tester

This directory contains an enhanced file watching system that automatically processes MT5 strategy test results and can restart the web server when files change.

## Quick Start

### Option 1: Use the Development Startup Script (Recommended)
```bash
./start_dev.sh
```

This script provides multiple startup options:
- **Standard mode**: Start server only
- **Enhanced mode**: Start server with file watching (recommended)
- **Server-only mode**: Start server, watch only server files
- **MT5-only mode**: Start server, watch only MT5 files

### Option 2: Manual Startup

#### Start with Simple Enhanced Watcher (Recommended)
```bash
# Watch both MT5 and server files
python3 simple_enhanced_watcher.py --both

# Watch only server files
python3 simple_enhanced_watcher.py --server-only

# Watch only MT5 files
python3 simple_enhanced_watcher.py --mt5-only
```

#### Start with Original Enhanced Watcher
```bash
# Watch both MT5 and server files
python3 enhanced_file_watcher.py --both

# Watch only server files
python3 enhanced_file_watcher.py --server-only

# Watch only MT5 files
python3 enhanced_file_watcher.py --mt5-only
```

## File Watchers

### 1. Simple Enhanced Watcher (`simple_enhanced_watcher.py`) - **RECOMMENDED**

This is a simplified, more reliable version that focuses on preventing restart loops:

**Features:**
- ✅ **No restart loops** - Improved restart protection
- ✅ **Startup grace period** - 15-second grace period after startup
- ✅ **Longer cooldowns** - 10-second cooldown between restarts
- ✅ **Better error handling** - Robust server management
- ✅ **Simplified logic** - Easier to debug and maintain

**Configuration:**
- **Watched Files**: `app.py`
- **Watched Extensions**: `.html`
- **Watched Directories**: `templates`
- **Ignored Files**: All watcher scripts, cache files, database files, etc.

### 2. Original Enhanced Watcher (`enhanced_file_watcher.py`)

The original enhanced watcher with more features but potential restart loop issues:

**Features:**
- ✅ MT5 file processing
- ✅ Server auto-restart
- ✅ Multiple watch modes
- ⚠️ **Potential restart loops** - Use with caution

### 3. Basic File Watcher (`file_watcher.py`)

Simple MT5 file watcher only:

**Features:**
- ✅ MT5 file processing only
- ❌ No server restart capability

## Configuration

### MT5 Path
The watchers look for MT5 JSON files in:
```
/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files
```

### Server URL
The watchers send data to:
```
http://127.0.0.1:5000/api/test
```

## Troubleshooting

### Restart Loop Issues

If you experience continuous server restarts:

1. **Use the Simple Enhanced Watcher** - It has better restart protection
2. **Check the logs** - Look for what files are triggering restarts
3. **Use server-only mode** - `python3 simple_enhanced_watcher.py --server-only`
4. **Manual restart** - Stop the watcher and restart manually

### Server Not Starting

1. **Check dependencies** - Ensure Flask and other packages are installed
2. **Check port conflicts** - Ensure port 5000 is available
3. **Check file permissions** - Ensure scripts are executable

### MT5 Files Not Processing

1. **Check MT5 path** - Verify the path exists and is correct
2. **Check file permissions** - Ensure the watcher can read MT5 files
3. **Check server status** - Ensure the web server is running

## Testing

Run the test script to verify the watcher works correctly:
```bash
python3 test_simple_watcher.py
```

## Development

### Adding New Watched Files

To add new files to watch in the simple enhanced watcher:

1. Edit `simple_enhanced_watcher.py`
2. Add to `WATCHED_FILES` list:
   ```python
   WATCHED_FILES = ['app.py', 'your_new_file.py']
   ```
3. Or add to `WATCHED_EXTENSIONS`:
   ```python
   WATCHED_EXTENSIONS = ['.html', '.css', '.js']
   ```

### Adding New Ignored Files

To ignore new files to prevent restart loops:

1. Edit `simple_enhanced_watcher.py`
2. Add to `IGNORED_FILES` list:
   ```python
   IGNORED_FILES = [
       'enhanced_file_watcher.py',
       'your_ignored_file.py'
   ]
   ```

## File Structure

```
webserver/
├── app.py                          # Main Flask application
├── start_dev.sh                    # Development startup script
├── simple_enhanced_watcher.py      # Simple enhanced watcher (RECOMMENDED)
├── enhanced_file_watcher.py        # Original enhanced watcher
├── file_watcher.py                 # Basic MT5 file watcher
├── test_simple_watcher.py          # Test script
├── templates/                      # HTML templates
│   ├── index.html
│   └── test_details.html
└── README_Enhanced_Watcher.md      # This file
```

## Best Practices

1. **Use the Simple Enhanced Watcher** for development
2. **Use server-only mode** if you only need server restarts
3. **Monitor the logs** to understand what's happening
4. **Test changes** with the test script before using in production
5. **Keep the grace period** to avoid immediate restarts after startup
