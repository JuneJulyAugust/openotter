# raspberry-pi-mcp

Raspberry Pi WiFi bridge firmware for `openotter`.

This firmware is the legacy Raspberry Pi WiFi bridge between the iPhone app and the Arduino actuation path. It provides a real-time TUI dashboard for monitoring communication health and manual control inputs.

## Features

- **Event-driven Networking:** High-performance UDP communication using `Asio`.
- **Dashboard UI:** Terminal UI built with `FTXUI` featuring bi-directional car-style meters.
- **Health Monitoring:** 1.5-second watchdog timeout for connection status tracking.
- **Identity Display:** Real-time display of local (Pi) and remote (iPhone) network identities.
- **Serial Bridge:** Automatic USB serial forwarding to the Arduino actuation path with reconnect, boot sync, and ACK logging.

## Requirements

### Hardware

- Raspberry Pi 4B.
- Connected Arduino actuation path via Serial.

### Software

- C++17 compiler (`g++`).
- `CMake` (3.16+).
- `libasio-dev` (networking library).
- `FTXUI` (cloned as a git submodule or in the project root).

## Installation

1. Install dependencies on the Pi:

   ```bash
   sudo apt update && sudo apt install -y cmake libasio-dev
   ```

2. Clone `FTXUI` in the project root:

   ```bash
   git clone https://github.com/ArthurSonzogni/FTXUI.git
   ```

## Development & Deployment

Use the provided `deploy.sh` script to sync and build on your Raspberry Pi:

```bash
cd firmware/raspberry-pi-mcp
chmod +x deploy.sh
./deploy.sh pi  # Replace 'pi' with your Pi's IP or SSH alias
```

## Running

Run the built executable on the Pi:

```bash
~/raspberry-pi-mcp/build/raspberry-pi-mcp
```

## Architecture

```text
iPhone (Brain) <---- UDP (1.0 Hz HB) ----> Pi (WiFi Bridge) <---- USB Serial + ACKs ----> Arduino actuation path
```

- **Port:** 8888 (UDP).
- **Timeout:** 1.5s Watchdog.
- The Pi keeps the Arduino link open, retries on USB errors, and shows the latest ACK line in the dashboard.
