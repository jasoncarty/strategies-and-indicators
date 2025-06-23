import time
import json
import os
import requests
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# --- Configuration ---
# The path to the MQL5 'Files' directory you provided
WATCH_PATH = '/Users/jasoncarty/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files'
SERVER_URL = "http://127.0.0.1:5000/api/test" # Use 127.0.0.1 for local server
# --- End Configuration ---


class JSONFileHandler(FileSystemEventHandler):
    """
    Handles events for new .json files in the watched directory.
    """
    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.json'):
            print(f"✅ New result file detected: {os.path.basename(event.src_path)}")
            # Wait a bit to ensure the file is fully written by MT5
            time.sleep(1)
            self.process_file(event.src_path)

    def process_file(self, file_path):
        """
        Reads a JSON file, sends its content to the web server, and deletes it.
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)

            print(f"   - Read {len(data.get('trades', []))} trades from file.")

            response = requests.post(SERVER_URL, json=data)

            if response.status_code == 201:
                test_id = response.json().get('test_id', 'N/A')
                print(f"   - ✔️ Successfully sent to server. New Test ID: {test_id}")
            else:
                print(f"   - ❌ ERROR sending to server. Status: {response.status_code}")
                print(f"   - Server Response: {response.text}")

        except json.JSONDecodeError:
            print(f"   - ❌ ERROR: Could not decode JSON from file: {os.path.basename(file_path)}")
        except requests.exceptions.RequestException as e:
            print(f"   - ❌ ERROR: Could not connect to the web server: {e}")
        except Exception as e:
            print(f"   - ❌ An unexpected error occurred: {e}")
        finally:
            # Delete the file after processing to avoid duplicates
            try:
                os.remove(file_path)
                print(f"   - 🗑️ Deleted processed file: {os.path.basename(file_path)}")
            except OSError as e:
                print(f"   - ❌ ERROR deleting file: {e}")


def main():
    """
    Starts the file watcher.
    """
    print("--- MT5 Strategy Result File Watcher ---")
    if not os.path.exists(WATCH_PATH):
        print(f"❌ ERROR: The path '{WATCH_PATH}' does not exist.")
        print("   - Please verify the path from 'Open Data Folder' in MT5.")
        return

    print(f"👀 Watching for new .json files in: {WATCH_PATH}")
    print(f"🚀 Sending results to: {SERVER_URL}")
    print("Press Ctrl+C to stop.")

    event_handler = JSONFileHandler()
    observer = Observer()
    observer.schedule(event_handler, WATCH_PATH, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        print("\n🛑 Watcher stopped by user.")

    observer.join()

if __name__ == "__main__":
    main()
