#!/bin/bash
# Stops the servo at neutral (90 degrees).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
compile_and_upload ../sketches/servo_stop/
echo "Servo centered at 90 degrees."
