# VL53L8 SATEL Firmware Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the active firmware ToF deployment path with one SATEL-VL53L8 sensor and leave the shape ready for a second sensor.

**Architecture:** Migrate the current VL53L5 wrapper and reverse-safety selector to VL53L8-facing names and STSW-IMG040 driver symbols. Keep generic `Tof_Frame_t`/BLE V2 framing stable so iOS can be updated later without a firmware protocol churn.

**Tech Stack:** STM32L475 HAL C firmware, ST VL53L8CX ULD from STSW-IMG040, host C unit tests, CMake/STM32CubeCLT target build.

---

## Release-Candidate Status

- Version prepared: `stm32-mcp` `1.2.0`.
- Branch status: implemented and committed as a release candidate; not merged
  or tagged yet.
- Hardware status: one SATEL-VL53L8 on I2C3 produced stable 4x4 safety frames
  at about 30 Hz after the sensor was repositioned away from the bench.
- Future scope: two-sensor front/rear safety should use separate I2C buses
  when possible: rear on I2C3 A5/A4, front on I2C1 D15/D14, with independent
  `LPn` and optional independent `PWR_EN`.

## Files

- Create: `firmware/stm32-mcp/VERSION`
- Create: `firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md`
- Create: `firmware/stm32-mcp/Core/Inc/tof_l8.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_l8.c`
- Create: `firmware/stm32-mcp/Core/Src/tof_l8_config.c`
- Create: `firmware/stm32-mcp/Core/Inc/tof_l8_debounce.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_l8_debounce.c`
- Create: `firmware/stm32-mcp/Core/Inc/tof_l8_topology.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_l8_topology.c`
- Create: `firmware/stm32-mcp/Core/Inc/rev_safety_l8.h`
- Create: `firmware/stm32-mcp/Core/Src/rev_safety_l8.c`
- Create: `firmware/stm32-mcp/tests/host/test_tof_l8_config.c`
- Create: `firmware/stm32-mcp/tests/host/test_tof_l8_debounce.c`
- Create: `firmware/stm32-mcp/tests/host/test_tof_l8_topology.c`
- Create: `firmware/stm32-mcp/tests/host/test_rev_safety_l8.c`
- Modify: `firmware/stm32-mcp/scripts/fetch-deps.sh`
- Modify: `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`
- Modify: `firmware/stm32-mcp/Core/Inc/tof_types.h`
- Modify: `firmware/stm32-mcp/Core/Src/main.c`
- Modify: `firmware/stm32-mcp/Core/Src/stm32l4xx_hal_msp.c`
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof.c`
- Modify: `firmware/stm32-mcp/Core/Inc/ble_tof.h`
- Modify: `firmware/stm32-mcp/tests/host/Makefile`
- Modify: `firmware/stm32-mcp/README.md`
- Modify: `firmware/stm32-mcp/CHANGELOG.md`

## Task 1: Preserve Baseline

- [x] **Step 1: Run host tests before edits**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

Actual baseline: passed on 2026-06-02 in the feature worktree.

## Task 2: Document Wiring

- [x] **Step 1: Add bring-up wiring doc**

Create `firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md` with:

```markdown
# 10 — SATEL-VL53L8 Firmware Bring-Up

## Corrected one-sensor wiring

| IOT01A1 | SATEL-VL53L8 | Purpose |
| --- | --- | --- |
| 5V | J2 pin 11 `EXT_5V0` | SATEL regulator input |
| GND | J2 pin 1 `EXT_SPI_I2C_N` | Select I2C mode |
| 3V3 | J2 pin 7 `EXT_PWR_EN` | Enable SATEL regulators |
| A5 / PC0 | J2 pin 6 `EXT_MCLK_SCL` | I2C3 SCL |
| A4 / PC1 | J2 pin 5 `EXT_MOSI_SDA` | I2C3 SDA |
| A2 / PC3 | J1 top pad `EXT_GPIO1` | Data-ready interrupt, currently optional |
| A1 / PC4 | J2 pin 2 `EXT_LPn` | Sensor low-power/reset control |
| GND | J1 bottom square pad GND or SATEL GND | Common ground |
```

- [x] **Step 2: Note current wiring mismatches**

Include the explicit correction table from the design spec so bench wiring can
be checked without opening the schematic PDF.

## Task 3: Add VL53L8 Driver Import Path

- [x] **Step 1: Extend dependency fetch script**

Modify `firmware/stm32-mcp/scripts/fetch-deps.sh` to accept
`--vl53l8cx-path /path/to/extracted/stsw-img040` and copy:

```text
VL53L8CX_ULD/modules/*.c,h -> Drivers/VL53L8CX/modules/
VL53L8CX_ULD/platform/*.c,h -> Drivers/VL53L8CX/platform/
```

Preserve any existing project platform wrapper if present.

- [x] **Step 2: Update CMake include/source paths**

Replace `VL53L5CX_Driver` include/source glob with `VL53L8CX_Driver`:

```cmake
${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L8CX/modules
${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L8CX/platform
```

and source glob:

```cmake
file(GLOB VL53L8CX_Src CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L8CX/modules/*.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L8CX/platform/*.c
)
```

## Task 4: Rename Active Sensor Type

- [x] **Step 1: Update `tof_types.h`**

Change active multizone sensor enum to:

```c
typedef enum {
  TOF_SENSOR_NONE      = 0,
  TOF_SENSOR_VL53L1CB  = 1, /* deprecated compatibility */
  TOF_SENSOR_VL53L8CX  = 2,
} Tof_SensorType_t;
```

Keep numeric value `2` to preserve BLE V2 payload compatibility until the iOS
round can update names deliberately.

## Task 5: Migrate L5 Wrapper To L8

- [x] **Step 1: Rename files**

Use mechanical renames from `tof_l5*` to `tof_l8*` and update includes.

- [x] **Step 2: Replace vendor symbols**

In `tof_l8.c`, replace `vl53l5cx_*`, `VL53L5CX_*`, and
`VL53L5CX_Configuration`/`ResultsData` with VL53L8CX ULD symbols:

```c
#include "vl53l8cx_api.h"
static VL53L8CX_Configuration g_dev;
static VL53L8CX_ResultsData g_results;
```

- [x] **Step 3: Keep one active slot**

Add slot identifiers to `tof_l8.h`:

```c
typedef enum {
  TOF_L8_SENSOR_REAR = 0,
  TOF_L8_SENSOR_FRONT = 1,
} TofL8SensorId_t;
```

Do not implement second-sensor address sequencing yet.

## Task 6: Migrate Reverse Safety Selector

- [x] **Step 1: Rename `rev_safety_l5` to `rev_safety_l8`**

Preserve the status whitelist and row-3 center-zone invariant:

```c
#define REV_SAFETY_L8_LAYOUT 4u
#define REV_SAFETY_L8_ZONE_ROW3_COL2 9u
#define REV_SAFETY_L8_ZONE_ROW3_COL3 10u
```

- [x] **Step 2: Update host tests**

Rename `test_rev_safety_l5.c` to `test_rev_safety_l8.c`, preserving all
status-code regression tests under VL53L8 names.

## Task 7: Update Main And BLE Integration

- [x] **Step 1: Stop initializing deprecated VL53L1 at boot**

Remove the runtime `TofL1_Init()` and `TofL1_Process()` calls from `main.c`.
Keep the legacy source only if BLE compatibility still compiles through it.

- [x] **Step 2: Update active includes and calls**

Replace `tof_l5.h` with `tof_l8.h`, `TofL5_*` with `TofL8_*`, and
`RevSafetyL5_*` with `RevSafetyL8_*` in active firmware.

- [x] **Step 3: Update comments and UART log labels**

Use `VL53L8` in boot and debug labels.

## Task 7.5: Capture Two-Sensor Topology In Tests

- [x] **Step 1: Write the failing topology test**

Create `firmware/stm32-mcp/tests/host/test_tof_l8_topology.c` with tests that
prove:

- rear and front slots use different buses by default;
- each slot has a distinct `LPn` and `GPIO1` role tag;
- separate buses allow both sensors to use default HAL address `0x52`;
- a same-bus pair with duplicate runtime address is rejected;
- a same-bus pair with shared `LPn` is rejected.

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_topology
```

Expected: compilation fails because `tof_l8_topology.h` or
`tof_l8_topology.c` does not exist yet.

Actual: failed first because `../../Core/Src/tof_l8_topology.c` did not exist.

- [x] **Step 2: Implement the pure topology helper**

Create `firmware/stm32-mcp/Core/Inc/tof_l8_topology.h` and
`firmware/stm32-mcp/Core/Src/tof_l8_topology.c` with a small HAL-free model of
the front/rear bus, address, `LPn`, and `GPIO1` assignments.

- [x] **Step 3: Run the topology test**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_topology
build/test_tof_l8_topology
```

Expected: topology tests pass.

Actual: passed on 2026-06-02.

## Task 8: Verify

- [x] **Step 1: Run host tests**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make clean
make test
```

Expected: all host tests pass.

Actual: passed on 2026-06-02 after migration and again after the expanded
VL53L8 frame/config/policy/topology tests.

- [x] **Step 2: Attempt firmware build**

Run if STSW-IMG040 and STM32CubeCLT dependencies exist:

```sh
cd firmware/stm32-mcp
./build.sh build
```

Expected: firmware builds. If vendor dependencies are missing, report the exact
missing dependency instead of claiming a target build passed.

Actual: passed on 2026-06-02 after local vendor dependencies were restored.
The production image was flashed to the IOT01A1 over ST-LINK and streamed
valid 4x4 VL53L8 frames at about 30 Hz.

- [x] **Step 3: Check Git status**

Run:

```sh
git status --short
```

Expected: only intended firmware, iOS release-prep, and documentation changes
are present.

Actual: only intended firmware, iOS release-prep, and documentation changes
are modified or added in the feature worktree.

- [x] **Step 4: Record release-candidate metadata**

Update `firmware/stm32-mcp/VERSION`, `firmware/stm32-mcp/README.md`, and
`firmware/stm32-mcp/CHANGELOG.md` for `1.2.0`.

Expected: release metadata is ready for follow-on verification, but no merge or
tag is performed.

Actual: completed on 2026-06-02.

- [x] **Step 5: Run host coverage**

Run:

```sh
cd firmware/stm32-mcp/tests/host
PATH=/Users/fang/projects/openotter/.venv/bin:$PATH \
  make coverage GCOVR=/Users/fang/projects/openotter/.venv/bin/gcovr
```

Expected: host coverage renders for HAL-free project modules.

Actual: passed on 2026-06-02 with line coverage `99.3%` (`450/453`),
function coverage `98.0%` (`48/49`), and branch coverage `90.7%` (`294/324`).
Every filtered module except the host-only `Firmware_Panic` spin stub reached
100% line coverage.
