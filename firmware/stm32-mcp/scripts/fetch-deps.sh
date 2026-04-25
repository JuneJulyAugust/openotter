#!/usr/bin/env bash
# fetch-deps.sh — Fetch vendor dependencies not tracked in git.
#
# Usage: ./scripts/fetch-deps.sh [--vl53l5cx-path /path/to/stsw-img023]
#
# Clones STM32CubeL4 and VL53L1 from GitHub (no login required).
# VL53L5CX requires a manual download from st.com — see --vl53l5cx-path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "--- $*"; }

# ── Parse args ────────────────────────────────────────────────────────────────
VL53L5CX_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vl53l5cx-path) VL53L5CX_PATH="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── 1. STM32CubeL4 (CMSIS + HAL + BLE) ───────────────────────────────────────
info "Cloning STM32CubeL4 (shallow) ..."
CUBE_DIR="$TMPDIR_BASE/STM32CubeL4"
git clone --depth 1 \
  https://github.com/STMicroelectronics/STM32CubeL4 \
  "$CUBE_DIR"

# CMSIS core headers
info "Installing CMSIS/Include ..."
rm -rf "$ROOT/Drivers/CMSIS/Include"
cp -r "$CUBE_DIR/Drivers/CMSIS/Include" "$ROOT/Drivers/CMSIS/"

# CMSIS Device (STM32L4xx only)
info "Installing CMSIS/Device/ST/STM32L4xx ..."
rm -rf "$ROOT/Drivers/CMSIS/Device"
mkdir -p "$ROOT/Drivers/CMSIS/Device/ST"
cp -r "$CUBE_DIR/Drivers/CMSIS/Device/ST/STM32L4xx" \
      "$ROOT/Drivers/CMSIS/Device/ST/"

# STM32L4xx HAL driver
info "Installing STM32L4xx_HAL_Driver ..."
rm -rf "$ROOT/Drivers/STM32L4xx_HAL_Driver"
cp -r "$CUBE_DIR/Drivers/STM32L4xx_HAL_Driver" "$ROOT/Drivers/"

# BLE middleware from P2P_LedButton example
info "Installing BLE middleware ..."
EXAMPLE="$CUBE_DIR/Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton"
MIDDLEWARE="$CUBE_DIR/Middlewares/ST/BlueNRG-MS"

mkdir -p "$ROOT/BLE/"{ble_core,ble_services,hw,tl,utilities,debug,_reference}

# BlueNRG-MS ACI + HCI layer
cp "$MIDDLEWARE"/hci/*.c         "$ROOT/BLE/ble_core/" 2>/dev/null || true
cp "$MIDDLEWARE"/hci/*.h         "$ROOT/BLE/ble_core/" 2>/dev/null || true
cp "$MIDDLEWARE"/includes/*.h    "$ROOT/BLE/ble_core/" 2>/dev/null || true

# Transport layer
cp "$EXAMPLE"/BLE_Application/TL/tl_ble_*.c  "$ROOT/BLE/tl/" 2>/dev/null || true
cp "$EXAMPLE"/BLE_Application/TL/tl_ble_*.h  "$ROOT/BLE/tl/" 2>/dev/null || true

# HW abstraction
cp "$EXAMPLE"/BLE_Application/hw_*.c  "$ROOT/BLE/hw/" 2>/dev/null || true
cp "$EXAMPLE"/BLE_Application/hw_*.h  "$ROOT/BLE/hw/" 2>/dev/null || true

# Utilities
find "$EXAMPLE"/BLE_Application -maxdepth 2 -name "osal.*" \
     -o -name "stm32_seq.*" | while read f; do
  cp "$f" "$ROOT/BLE/utilities/" 2>/dev/null || true
done

# Reference snapshot
cp "$EXAMPLE"/Core/Src/main.c         "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Src/stm32l4xx_it.c "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Inc/*.h            "$ROOT/BLE/_reference/" 2>/dev/null || true

# ── 2. VL53L1 API ─────────────────────────────────────────────────────────────
info "Cloning VL53L1 API (v6.6.19, shallow) ..."
VL53L1_DIR="$TMPDIR_BASE/VL53L1"
git clone --depth 1 \
  https://github.com/STMicroelectronics/VL53L1 \
  "$VL53L1_DIR"

rm -rf "$ROOT/Drivers/VL53L1CB"
mkdir -p "$ROOT/Drivers/VL53L1CB"
cp -r "$VL53L1_DIR/core"     "$ROOT/Drivers/VL53L1CB/"
cp -r "$VL53L1_DIR/platform" "$ROOT/Drivers/VL53L1CB/"

# ── 3. VL53L5CX ULD ───────────────────────────────────────────────────────────
if [[ -n "$VL53L5CX_PATH" ]]; then
  info "Installing VL53L5CX from $VL53L5CX_PATH ..."
  rm -rf "$ROOT/Drivers/VL53L5CX/modules" "$ROOT/Drivers/VL53L5CX/platform"
  mkdir -p "$ROOT/Drivers/VL53L5CX"/{modules,platform}

  # Try both common package layouts from STSW-IMG023
  ULD="$VL53L5CX_PATH"
  if [[ -d "$ULD/Middlewares/ST/VL53L5CX_ULD" ]]; then
    ULD="$ULD/Middlewares/ST/VL53L5CX_ULD"
  fi

  cp "$ULD"/modules/*.c  "$ROOT/Drivers/VL53L5CX/modules/" 2>/dev/null || true
  cp "$ULD"/modules/*.h  "$ROOT/Drivers/VL53L5CX/modules/" 2>/dev/null || true

  # Keep our project's platform wrapper, not the ST stub
  echo "NOTE: Preserving existing platform/platform.{c,h} (our STM32 HAL wrapper)."
  if [[ ! -f "$ROOT/Drivers/VL53L5CX/platform/platform.h" ]]; then
    cp "$ULD"/platform/*.c "$ROOT/Drivers/VL53L5CX/platform/" 2>/dev/null || true
    cp "$ULD"/platform/*.h "$ROOT/Drivers/VL53L5CX/platform/" 2>/dev/null || true
  fi
else
  echo ""
  echo "VL53L5CX: SKIPPED — download STSW-IMG023 from:"
  echo "  https://www.st.com/en/embedded-software/stsw-img023.html"
  echo "Then re-run: $0 --vl53l5cx-path /path/to/extracted/stsw-img023"
  echo ""
fi

# ── Done ──────────────────────────────────────────────────────────────────────
info "Verifying installation ..."
errors=0
check() {
  if [[ ! -e "$1" ]]; then
    echo "MISSING: $1" >&2; errors=$((errors+1))
  fi
}

check "$ROOT/Drivers/CMSIS/Include/core_cm4.h"
check "$ROOT/Drivers/CMSIS/Device/ST/STM32L4xx/Include/stm32l475xx.h"
check "$ROOT/Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal.c"
check "$ROOT/Drivers/VL53L1CB/core/inc/vl53l1_api.h"
[[ -n "$VL53L5CX_PATH" ]] && check "$ROOT/Drivers/VL53L5CX/modules/vl53l5cx_api.h"

if [[ $errors -eq 0 ]]; then
  echo ""
  echo "All dependencies installed. Build with:"
  echo "  cd build/Debug && cmake --build ."
else
  echo "$errors file(s) missing — check the fetch output above." >&2
  exit 1
fi
