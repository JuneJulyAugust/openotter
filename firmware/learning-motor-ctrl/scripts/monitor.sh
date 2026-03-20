#!/bin/bash
# Opens a serial monitor to read Arduino output. Press Ctrl+C to exit.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
port=$(detect_port)
echo "Monitoring $port at 115200 baud (Ctrl+C to exit)..."
arduino-cli monitor -p "$port" --config baudrate=115200
