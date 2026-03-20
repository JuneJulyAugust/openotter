#!/bin/bash
# Description: Sets up the environment variables needed for arduino-cli
# Usage: source setup_env.sh

# Calculate script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-bootstrap arduino-cli if it doesn't exist
if [ ! -f "$SCRIPT_DIR/bin/arduino-cli" ]; then
    echo "arduino-cli not found in bin/. Downloading and installing..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$SCRIPT_DIR/bin" sh
fi

export PATH=$PATH:$SCRIPT_DIR/bin
export ARDUINO_CONFIG_FILE=$SCRIPT_DIR/arduino-cli.yaml

# Auto-install AVR core and Servo library if missing
if [ ! -d "$SCRIPT_DIR/arduino_data/packages/arduino/hardware/avr" ]; then
    echo "Arduino AVR core not found. Initializing local toolchain environment..."
    arduino-cli core update-index
    arduino-cli core install arduino:avr
    arduino-cli lib install Servo
    echo "Toolchain initialized locally in arduino_data/."
fi

echo "arduino-cli has been added to your PATH and is ready to use."
arduino-cli version
