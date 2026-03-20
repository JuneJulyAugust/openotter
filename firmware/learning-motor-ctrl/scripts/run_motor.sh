#!/bin/bash
# Compiles and flashes the brushless motor demo sketch.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
compile_and_upload ../sketches/motor_demo/
echo "The motor should arm and begin ramping."
