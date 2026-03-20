#!/bin/bash
# Compiles and flashes the combined motor + steering demo.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/common.sh"
compile_and_upload ../sketches/combined_demo/
echo "Combined demo running — motor + steering."
