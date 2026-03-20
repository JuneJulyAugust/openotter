#!/bin/bash
# Compiles and flashes the steering servo demo sketch.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
compile_and_upload ../sketches/servo_demo/
echo "The servo should begin sweeping."
