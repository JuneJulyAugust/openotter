#!/bin/bash
# Stops all actuators and centers the steering.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
compile_and_upload ../sketches/combined_stop/
echo "Combined actuators stopped and centered."
