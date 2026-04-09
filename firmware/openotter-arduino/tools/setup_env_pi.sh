#!/bin/bash
# Description: Sets up the arduino-cli environment on the Raspberry Pi
# This is meant to be run ON the Pi.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install arduino-cli for Linux ARM (Pi) if missing
if [ ! -f "$SCRIPT_DIR/bin/arduino-cli" ]; then
    echo "==> Creating bin directory..."
    mkdir -p "$SCRIPT_DIR/bin"
    echo "==> Downloading arduino-cli for Raspberry Pi..."
    # The official install.sh script detects architecture (armhf for Pi 32-bit, aarch64 for 64-bit)
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$SCRIPT_DIR/bin" sh
fi

# 2. Set environment variables
export PATH="$SCRIPT_DIR/bin:$PATH"
export ARDUINO_CONFIG_FILE="$SCRIPT_DIR/arduino-cli.yaml"
export ARDUINO_DIRECTORIES_DATA="$SCRIPT_DIR/arduino_data"
export ARDUINO_DIRECTORIES_USER="$SCRIPT_DIR/arduino_data/user"
export ARDUINO_DIRECTORIES_DOWNLOADS="$SCRIPT_DIR/arduino_data/staging"

# 3. Initialize/Update cores and libraries
if [ ! -d "$ARDUINO_DIRECTORIES_DATA/packages/arduino/hardware/avr" ]; then
    echo "==> Initializing Arduino AVR core and Servo library..."
    mkdir -p "$ARDUINO_DIRECTORIES_DATA"
    "$SCRIPT_DIR/bin/arduino-cli" core update-index
    "$SCRIPT_DIR/bin/arduino-cli" core install arduino:avr
    "$SCRIPT_DIR/bin/arduino-cli" lib install Servo
fi

echo "==> arduino-cli environment ready on Pi."
"$SCRIPT_DIR/bin/arduino-cli" version
