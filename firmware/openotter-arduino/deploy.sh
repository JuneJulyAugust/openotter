#!/usr/bin/env bash
set -euo pipefail

# Deployment script for openotter-arduino (Pi-side)
# Usage: ./deploy.sh [pi-hostname-or-ip]

PI_HOST="${1:-pi}"
REMOTE_DIR="~/openotter-arduino"

# Get the absolute path to the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Syncing Arduino source and tools to $PI_HOST:$REMOTE_DIR..."

rsync -avz --delete \
    --exclude '.git/' \
    --exclude 'tools/bin/' \
    --exclude 'tools/arduino_data/' \
    "$SCRIPT_DIR/" "$PI_HOST:$REMOTE_DIR/"

echo "==> Initializing and Running on $PI_HOST..."
ssh "$PI_HOST" "
    cd $REMOTE_DIR && \
    # 1. Setup local arduino-cli
    chmod +x tools/setup_env_pi.sh && \
    bash tools/setup_env_pi.sh && \
    
    # 2. Source environment
    export PATH=\"\$HOME/openotter-arduino/tools/bin:\$PATH\" && \
    export ARDUINO_CONFIG_FILE=\"\$HOME/openotter-arduino/tools/arduino-cli.yaml\" && \
    export ARDUINO_DIRECTORIES_DATA=\"\$HOME/openotter-arduino/tools/arduino_data\" && \
    export ARDUINO_DIRECTORIES_USER=\"\$HOME/openotter-arduino/tools/arduino_data/user\" && \
    export ARDUINO_DIRECTORIES_DOWNLOADS=\"\$HOME/openotter-arduino/tools/arduino_data/staging\" && \
    
    # 3. Find the port
    PORT=\$(ls /dev/ttyUSB* 2>/dev/null | head -1) && \
    if [ -z \"\$PORT\" ]; then
        echo 'Error: No /dev/ttyUSB* device found on Pi.' >&2
        exit 1
    fi && \
    echo \"Using port: \$PORT\" && \
    
    # 4. KILL any process using the port (like the MCP)
    echo 'Ensuring serial port is free...' && \
    sudo fuser -k \"\$PORT\" || true && \
    
    # 5. Compile and Upload
    echo 'Compiling...' && \
    arduino-cli compile --fqbn arduino:avr:mega . && \
    echo 'Uploading...' && \
    arduino-cli upload -p \"\$PORT\" --fqbn arduino:avr:mega .
"

echo "==> Done."
