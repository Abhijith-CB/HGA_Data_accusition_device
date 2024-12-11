import sys
import pandas as pd
from datetime import datetime
from websocket import WebSocketApp
import threading
import select


def generate_filename(custom_name):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"{custom_name}_{timestamp}" if custom_name else f"sensor_data_{timestamp}"


def on_message(ws, message):
    if not logging_active:
        return
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        data_lines = message.strip().splitlines()
        mpu_data = "\n".join([line for line in data_lines if line.startswith("MPU6050")])
        flex_data = "\n".join([line for line in data_lines if line.startswith("Bend Sensor")])

        if mpu_data and flex_data:
            print(f"[{timestamp}] Data Logged:\n{message}\n")
            columns = ["Timestamp", "MPU6050 Data", "Flex Sensor Data"]
            new_entry = pd.DataFrame([[timestamp, mpu_data, flex_data]], columns=columns)

            if csv_enabled:
                new_entry.to_csv(csv_filename, mode='a', header=not pd.io.common.file_exists(csv_filename), index=False)

            if excel_enabled:
                if pd.io.common.file_exists(excel_filename):
                    excel_data = pd.read_excel(excel_filename, engine='openpyxl')
                    updated_data = pd.concat([excel_data, new_entry], ignore_index=True)
                else:
                    updated_data = new_entry
                updated_data.to_excel(excel_filename, index=False, engine='openpyxl')
        else:
            print("Invalid Data Received, Skipping Log.")
    except Exception as e:
        print(f"Unexpected Error: {e}")


def on_error(ws, error):
    print(f"WebSocket Error: {error}")


def on_close(ws, close_status_code, close_msg):
    print("WebSocket Closed.")


def on_open(ws):
    print("WebSocket Connected.")


def start_logging():
    global logging_active, csv_filename, excel_filename, ws

    ip = input("Enter WebSocket IP (default ws://10.10.10.10/ws): ") or "ws://192.168.4.1/ws"
    custom_name = input("Enter Custom Filename (optional): ").strip()
    csv_filename = f"{generate_filename(custom_name)}.csv"
    excel_filename = f"{generate_filename(custom_name)}.xlsx"

    logging_active = True
    ws = WebSocketApp(
        ip, 
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close
    )
    threading.Thread(target=ws.run_forever, daemon=True).start()
    print("Logging started. Press 'q' to stop logging.")


def stop_logging():
    global logging_active, ws
    if logging_active:
        logging_active = False
        if ws:
            ws.close()
        print("Logging stopped.")
    else:
        print("Logging is not currently active.")


if __name__ == '__main__':
    csv_enabled = True
    excel_enabled = True
    logging_active = False
    ws = None

    start_logging()

    try:
        print("Press 'q' to stop logging.")
        while True:
            if select.select([sys.stdin], [], [], 0)[0]:
                if sys.stdin.read(1).lower() == 'q':
                    stop_logging()
                    sys.exit("Exiting...")
    except KeyboardInterrupt:
        stop_logging()
        sys.exit("Exiting...")
