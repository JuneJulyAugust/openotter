#!/usr/bin/env bash
# fetch-deps.sh — Fetch vendor dependencies not tracked in git.
#
# Usage: ./scripts/fetch-deps.sh [--vl53l8cx-path /path/to/stsw-img040]
#
# Fetches a pinned STM32CubeL4 snapshot from GitHub (no login required).
# VL53L8CX requires a manual download from st.com; see --vl53l8cx-path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
STM32CUBE_L4_REF="${STM32CUBE_L4_REF:-ca1ce808ce1e49916f9d3d795b8e4437fe65d715}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "--- $*"; }

# ── Parse args ────────────────────────────────────────────────────────────────
VL53L8CX_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vl53l8cx-path) VL53L8CX_PATH="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ -n "$VL53L8CX_PATH" && ! -d "$VL53L8CX_PATH" ]]; then
  die "VL53L8CX path does not exist: $VL53L8CX_PATH"
fi

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── 1. STM32CubeL4 (CMSIS + HAL + BLE) ───────────────────────────────────────
info "Fetching STM32CubeL4 $STM32CUBE_L4_REF ..."
CUBE_DIR="$TMPDIR_BASE/STM32CubeL4"
git init -q "$CUBE_DIR"
git -C "$CUBE_DIR" remote add origin https://github.com/STMicroelectronics/STM32CubeL4
git -C "$CUBE_DIR" fetch --depth 1 origin "$STM32CUBE_L4_REF"
git -C "$CUBE_DIR" checkout -q --detach FETCH_HEAD
git -C "$CUBE_DIR" submodule update --init --depth 1 \
  Drivers/CMSIS/Device/ST/STM32L4xx \
  Drivers/STM32L4xx_HAL_Driver

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

# BLE middleware from the B-L475E-IOT01A BLE examples.
info "Installing BLE middleware ..."
BLE_APPS="$CUBE_DIR/Projects/B-L475E-IOT01A/Applications/BLE"
EXAMPLE="$BLE_APPS/P2P_LedButton"
COMMON="$BLE_APPS/Common"
LEGACY_APP="$EXAMPLE/BLE_Application"

mkdir -p "$ROOT/BLE/"{ble_core,ble_services,hw,tl,utilities,debug,_reference}

if [[ -d "$COMMON" ]]; then
  # Current STM32CubeL4 layout: common reusable middleware lives outside each
  # example application. Copy only generated/vendor directories; Core/Inc owns
  # this project's active BLE configuration.
  rm -rf "$ROOT/BLE/ble_core" "$ROOT/BLE/ble_services" "$ROOT/BLE/hw" \
         "$ROOT/BLE/tl" "$ROOT/BLE/utilities" "$ROOT/BLE/debug"
  cp -r "$COMMON/ble_core" "$ROOT/BLE/"
  cp -r "$COMMON/ble_services" "$ROOT/BLE/"
  cp -r "$COMMON/hw" "$ROOT/BLE/"
  cp -r "$COMMON/tl" "$ROOT/BLE/"
  cp -r "$COMMON/utilities" "$ROOT/BLE/"
  cp -r "$COMMON/debug" "$ROOT/BLE/"
  cp "$COMMON"/ble_*_template.h "$ROOT/BLE/" 2>/dev/null || true
  cp "$COMMON"/common.h "$COMMON"/config_template.h "$ROOT/BLE/" 2>/dev/null || true
elif [[ -d "$LEGACY_APP" ]]; then
  # Older STM32CubeL4 layout: middleware was nested under P2P_LedButton.
  rm -rf "$ROOT/BLE/ble_core" "$ROOT/BLE/ble_services" "$ROOT/BLE/hw" \
         "$ROOT/BLE/tl" "$ROOT/BLE/utilities" "$ROOT/BLE/debug"
  mkdir -p "$ROOT/BLE/"{ble_core,ble_services,hw,tl,utilities,debug}
  cp "$LEGACY_APP"/TL/tl_ble_*.c "$ROOT/BLE/tl/" 2>/dev/null || true
  cp "$LEGACY_APP"/TL/tl_ble_*.h "$ROOT/BLE/tl/" 2>/dev/null || true
  cp "$LEGACY_APP"/HW/hw_*.c "$ROOT/BLE/hw/" 2>/dev/null || true
  cp "$LEGACY_APP"/HW/hw_*.h "$ROOT/BLE/hw/" 2>/dev/null || true
  cp "$LEGACY_APP"/SERVICES/*.{c,h} "$ROOT/BLE/ble_services/" 2>/dev/null || true
  cp "$LEGACY_APP"/Utilities/*.{c,h} "$ROOT/BLE/utilities/" 2>/dev/null || true
  cp "$LEGACY_APP"/Debug/*.h "$ROOT/BLE/debug/" 2>/dev/null || true
else
  die "Cannot find STM32CubeL4 BLE Common or legacy BLE_Application under $BLE_APPS"
fi

cat > "$ROOT/BLE/ble_core/hal_types.h" <<'EOF'
/**
 * @file  hal_types.h
 * @brief Compatibility shim for BlueNRG-MS core files.
 */
#ifndef __HAL_TYPES_H
#define __HAL_TYPES_H

#include <stdint.h>
#include "bluenrg_private_hal_types.h"

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef BOOL
typedef uint8_t BOOL;
#endif

#ifndef TRUE
#define TRUE  1
#endif

#ifndef FALSE
#define FALSE 0
#endif

#endif /* __HAL_TYPES_H */
EOF

cat > "$ROOT/BLE/ble_core/hal.h" <<'EOF'
/**
 * @file  hal.h
 * @brief Compatibility shim for BlueNRG-MS core files.
 */
#ifndef __HAL_H
#define __HAL_H

#include "hal_types.h"
#include "hci_tl_io.h"

#endif /* __HAL_H */
EOF

# Reference snapshot
rm -rf "$ROOT/BLE/_reference"
mkdir -p "$ROOT/BLE/_reference"
cp "$EXAMPLE"/Src/*.c "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Inc/*.h "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Src/*.c "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Inc/*.h "$ROOT/BLE/_reference/" 2>/dev/null || true

# ── 2. VL53L8CX ULD ───────────────────────────────────────────────────────────
if [[ -n "$VL53L8CX_PATH" ]]; then
  info "Installing VL53L8CX from $VL53L8CX_PATH ..."
  rm -rf "$ROOT/Drivers/VL53L8CX/modules"
  mkdir -p "$ROOT/Drivers/VL53L8CX"/{modules,platform}

  # Try common package layouts from STSW-IMG040.
  ULD="$VL53L8CX_PATH"
  if [[ -d "$ULD/Middlewares/ST/VL53L8CX_ULD" ]]; then
    ULD="$ULD/Middlewares/ST/VL53L8CX_ULD"
  elif [[ -d "$ULD/VL53L8CX_ULD" ]]; then
    ULD="$ULD/VL53L8CX_ULD"
  elif [[ -d "$ULD/VL53L8CX_ULD_API" ]]; then
    ULD="$ULD"
  else
    shopt -s nullglob
    candidates=("$ULD"/VL53L8CX_ULD_driver_*/VL53L8CX_ULD_API)
    shopt -u nullglob
    if [[ ${#candidates[@]} -gt 0 ]]; then
      ULD="$(dirname "${candidates[0]}")"
    fi
  fi

  if [[ -d "$ULD/modules" ]]; then
    [[ -d "$ULD/platform" ]] || die "Cannot find VL53L8CX_ULD/platform under $VL53L8CX_PATH"
    cp "$ULD"/modules/*.c  "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true
    cp "$ULD"/modules/*.h  "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true

    if [[ -f "$ROOT/Drivers/VL53L8CX/platform/platform.h" ]]; then
      echo "NOTE: Preserving existing VL53L8CX platform wrapper."
    else
      cp "$ULD"/platform/*.c "$ROOT/Drivers/VL53L8CX/platform/" 2>/dev/null || true
      cp "$ULD"/platform/*.h "$ROOT/Drivers/VL53L8CX/platform/" 2>/dev/null || true
    fi
  elif [[ -d "$ULD/VL53L8CX_ULD_API/inc" && -d "$ULD/VL53L8CX_ULD_API/src" ]]; then
    [[ -d "$ULD/Platform" ]] || die "Cannot find STSW-IMG040 Platform under $VL53L8CX_PATH"
    cp "$ULD"/VL53L8CX_ULD_API/src/*.c "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true
    cp "$ULD"/VL53L8CX_ULD_API/inc/*.h "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true
    perl -0pi -e 's/goto exit\r?\n([ \t]*\})/goto exit;\n$1/' \
      "$ROOT/Drivers/VL53L8CX/modules/vl53l8cx_api.c"
    cat > "$ROOT/Drivers/VL53L8CX/platform/platform.h" <<'EOF'
/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef OPENOTTER_VL53L8CX_PLATFORM_H
#define OPENOTTER_VL53L8CX_PLATFORM_H

#include <stdint.h>
#include <string.h>

typedef struct {
  uint16_t address;
  uint8_t (*Write)(void *handle, uint16_t register_addr, uint8_t *data,
                   uint32_t size);
  uint8_t (*Read)(void *handle, uint16_t register_addr, uint8_t *data,
                  uint32_t size);
  uint8_t (*Wait)(void *handle, uint32_t time_ms);
  void *handle;
} VL53L8CX_Platform;

#ifndef VL53L8CX_NB_TARGET_PER_ZONE
#define VL53L8CX_NB_TARGET_PER_ZONE 1U
#endif

uint8_t VL53L8CX_RdByte(VL53L8CX_Platform *p_platform,
                        uint16_t RegisterAdress, uint8_t *p_value);
uint8_t VL53L8CX_WrByte(VL53L8CX_Platform *p_platform,
                        uint16_t RegisterAdress, uint8_t value);
uint8_t VL53L8CX_RdMulti(VL53L8CX_Platform *p_platform,
                         uint16_t RegisterAdress, uint8_t *p_values,
                         uint32_t size);
uint8_t VL53L8CX_WrMulti(VL53L8CX_Platform *p_platform,
                         uint16_t RegisterAdress, uint8_t *p_values,
                         uint32_t size);
uint8_t VL53L8CX_Reset_Sensor(VL53L8CX_Platform *p_platform);
void VL53L8CX_SwapBuffer(uint8_t *buffer, uint16_t size);
uint8_t VL53L8CX_WaitMs(VL53L8CX_Platform *p_platform, uint32_t TimeMs);

#endif
EOF
    cat > "$ROOT/Drivers/VL53L8CX/platform/platform.c" <<'EOF'
/* SPDX-License-Identifier: BSD-3-Clause */
#include "platform.h"

#define VL53L8CX_PLATFORM_ERROR 255U

uint8_t VL53L8CX_RdByte(VL53L8CX_Platform *p_platform,
                        uint16_t RegisterAdress, uint8_t *p_value)
{
  return VL53L8CX_RdMulti(p_platform, RegisterAdress, p_value, 1U);
}

uint8_t VL53L8CX_WrByte(VL53L8CX_Platform *p_platform,
                        uint16_t RegisterAdress, uint8_t value)
{
  return VL53L8CX_WrMulti(p_platform, RegisterAdress, &value, 1U);
}

uint8_t VL53L8CX_RdMulti(VL53L8CX_Platform *p_platform,
                         uint16_t RegisterAdress, uint8_t *p_values,
                         uint32_t size)
{
  if (p_platform == 0 || p_platform->Read == 0) {
    return VL53L8CX_PLATFORM_ERROR;
  }
  return p_platform->Read(p_platform->handle, RegisterAdress, p_values, size);
}

uint8_t VL53L8CX_WrMulti(VL53L8CX_Platform *p_platform,
                         uint16_t RegisterAdress, uint8_t *p_values,
                         uint32_t size)
{
  if (p_platform == 0 || p_platform->Write == 0) {
    return VL53L8CX_PLATFORM_ERROR;
  }
  return p_platform->Write(p_platform->handle, RegisterAdress, p_values, size);
}

uint8_t VL53L8CX_Reset_Sensor(VL53L8CX_Platform *p_platform)
{
  if (p_platform == 0 || p_platform->Wait == 0) {
    return VL53L8CX_PLATFORM_ERROR;
  }
  uint8_t status = p_platform->Wait(p_platform->handle, 100U);
  status |= p_platform->Wait(p_platform->handle, 100U);
  return status;
}

void VL53L8CX_SwapBuffer(uint8_t *buffer, uint16_t size)
{
  uint32_t i;
  for (i = 0; i < size; i += 4U) {
    uint32_t tmp = ((uint32_t)buffer[i] << 24) |
                   ((uint32_t)buffer[i + 1U] << 16) |
                   ((uint32_t)buffer[i + 2U] << 8) |
                   ((uint32_t)buffer[i + 3U]);
    memcpy(&buffer[i], &tmp, 4U);
  }
}

uint8_t VL53L8CX_WaitMs(VL53L8CX_Platform *p_platform, uint32_t TimeMs)
{
  if (p_platform == 0 || p_platform->Wait == 0) {
    return VL53L8CX_PLATFORM_ERROR;
  }
  return p_platform->Wait(p_platform->handle, TimeMs);
}
EOF
  else
    die "Cannot find VL53L8CX ULD files under $VL53L8CX_PATH"
  fi
else
  echo ""
  echo "VL53L8CX: REQUIRED - download STSW-IMG040 from:"
  echo "  https://www.st.com/en/embedded-software/stsw-img040.html"
  echo "Then re-run: $0 --vl53l8cx-path /path/to/extracted/stsw-img040"
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
check "$ROOT/BLE/ble_core/bluenrg_gap_aci.c"
check "$ROOT/BLE/tl/tl_ble_hci.c"
check "$ROOT/BLE/hw/hw_spi.c"
check "$ROOT/BLE/ble_services/svc_ctl.c"
check "$ROOT/BLE/utilities/scheduler.c"
check "$ROOT/Drivers/VL53L8CX/modules/vl53l8cx_api.h"
check "$ROOT/Drivers/VL53L8CX/platform/platform.h"

if [[ $errors -eq 0 ]]; then
  echo ""
  echo "All dependencies installed. Build with:"
  echo "  cd build/Debug && cmake --build ."
else
  echo "$errors file(s) missing — check the fetch output above." >&2
  exit 1
fi
