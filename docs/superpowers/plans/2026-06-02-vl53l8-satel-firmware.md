# VL53L8 SATEL Firmware Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the active firmware ToF deployment path with one SATEL-VL53L8 sensor, support both I2C and SPI wiring with boot-time detection, and leave the shape ready for a second sensor.

**Architecture:** Keep generic `Tof_Frame_t`/BLE V2 framing stable while the VL53L8 wrapper owns sensor policy. Add a narrow transport module under the ST `VL53L8CX_Platform` callback seam so the same firmware can probe I2C3 first, then SPI1, and run the one transport that responds after a power-off wiring change.

**Tech Stack:** STM32L475 HAL C firmware, ST VL53L8CX ULD from STSW-IMG040, host C unit tests, CMake/STM32CubeCLT target build.

---

## Release-Candidate Status

- Version prepared: `stm32-mcp` `1.2.0`.
- Branch status: implemented and committed as a release candidate; not merged
  or tagged yet.
- Hardware status: one SATEL-VL53L8 on I2C3 produced stable 4x4 safety frames
  at about 30 Hz after the sensor was repositioned away from the bench.
- New transport scope: keep the proven I2C3 path and add SPI1 support. The
  firmware will not hot-swap modes; it probes transports at boot after the user
  powers off and rewires `EXT_SPI_I2C_N`.
- Future scope: two-sensor front/rear safety should prefer shared SPI1 with
  independent `NCS` and `LPn`. Separate I2C buses remain a fallback.

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
- Create: `firmware/stm32-mcp/Core/Inc/tof_l8_transport.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_l8_transport.c`
- Create: `firmware/stm32-mcp/tests/host/test_tof_l8_transport.c`
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

## Task 0.1: Document Dual Transport Design

- [x] **Step 1: Update the design doc**

Modify `docs/superpowers/specs/2026-06-02-vl53l8-satel-firmware-design.md`
with the dual-transport invariant:

```text
SATEL wiring selects I2C or SPI
  -> firmware probes I2C3, then SPI1
  -> exactly one transport should answer for a single populated sensor
  -> VL53L8CX ULD receives transport callbacks through one platform object
  -> ranging, safety, BLE, and iOS-facing frame semantics stay unchanged
```

- [x] **Step 2: Update this implementation plan**

Add transport files, tests, and commit checkpoints for the SPI/I2C work.

- [ ] **Step 3: Commit documentation**

Run:

```sh
git add docs/superpowers/specs/2026-06-02-vl53l8-satel-firmware-design.md \
        docs/superpowers/plans/2026-06-02-vl53l8-satel-firmware.md
git commit -m "Docs: Plan VL53L8 dual transport"
```

Expected: one docs-only commit.

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

## Task 9: Add Pure Transport Model

- [ ] **Step 1: Write the failing transport test**

Create `firmware/stm32-mcp/tests/host/test_tof_l8_transport.c`:

```c
/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_transport.h"

#include <assert.h>

static void test_i2c_handle_configures_default_address(void)
{
  TofL8TransportHandle_t handle;
  TofL8Transport_InitI2c(&handle, TOF_L8_I2C_BUS_3,
                         TOF_L8_DEFAULT_I2C_ADDR_8BIT);

  assert(handle.kind == TOF_L8_TRANSPORT_I2C);
  assert(handle.i2c.bus == TOF_L8_I2C_BUS_3);
  assert(handle.i2c.addr_8bit == TOF_L8_DEFAULT_I2C_ADDR_8BIT);
}

static void test_spi_handle_configures_chip_select(void)
{
  TofL8TransportHandle_t handle;
  TofL8Transport_InitSpi(&handle, TOF_L8_SPI_BUS_1, TOF_L8_GPIO_PB2_D8);

  assert(handle.kind == TOF_L8_TRANSPORT_SPI);
  assert(handle.spi.bus == TOF_L8_SPI_BUS_1);
  assert(handle.spi.ncs == TOF_L8_GPIO_PB2_D8);
}

static void test_probe_choice_prefers_i2c_then_spi(void)
{
  assert(TofL8Transport_ChooseProbe(1, 0) == TOF_L8_TRANSPORT_I2C);
  assert(TofL8Transport_ChooseProbe(0, 1) == TOF_L8_TRANSPORT_SPI);
  assert(TofL8Transport_ChooseProbe(0, 0) == TOF_L8_TRANSPORT_NONE);
  assert(TofL8Transport_ChooseProbe(1, 1) == TOF_L8_TRANSPORT_AMBIGUOUS);
}

int main(void)
{
  test_i2c_handle_configures_default_address();
  test_spi_handle_configures_chip_select();
  test_probe_choice_prefers_i2c_then_spi();
  return 0;
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_transport
```

Expected: FAIL because `tof_l8_transport.h` does not exist.

- [ ] **Step 3: Add the HAL-free transport model**

Create `firmware/stm32-mcp/Core/Inc/tof_l8_transport.h` and
`firmware/stm32-mcp/Core/Src/tof_l8_transport.c` with only value types and the
pure probe-choice function. This task must not call HAL.

- [ ] **Step 4: Wire the host Makefile**

Add `test_tof_l8_transport` to `TESTS` and compile it with
`../../Core/Src/tof_l8_transport.c`.

- [ ] **Step 5: Verify transport host tests**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_transport
build/test_tof_l8_transport
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```sh
git add firmware/stm32-mcp/Core/Inc/tof_l8_transport.h \
        firmware/stm32-mcp/Core/Src/tof_l8_transport.c \
        firmware/stm32-mcp/tests/host/test_tof_l8_transport.c \
        firmware/stm32-mcp/tests/host/Makefile
git commit -m "Firmware: Add VL53L8 transport model"
```

## Task 10: Extend Topology For SPI

- [ ] **Step 1: Write the failing topology expectations**

Update `firmware/stm32-mcp/tests/host/test_tof_l8_topology.c` so the default
future pair uses SPI1, distinct chip-selects, distinct `LPn`, and distinct
`GPIO1`:

```c
assert(rear->transport == TOF_L8_TRANSPORT_SPI);
assert(front->transport == TOF_L8_TRANSPORT_SPI);
assert(rear->bus_id == TOF_L8_BUS_SPI1);
assert(front->bus_id == TOF_L8_BUS_SPI1);
assert(rear->ncs == TOF_L8_GPIO_PB2_D8);
assert(front->ncs == TOF_L8_GPIO_PA2_D10);
assert(rear->ncs != front->ncs);
```

Also add a rejection test for two SPI sensors sharing `NCS`.

- [ ] **Step 2: Run topology test to verify it fails**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_topology
```

Expected: FAIL because topology has no SPI fields yet.

- [ ] **Step 3: Implement minimal topology changes**

Extend `tof_l8_topology.h` with `TOF_L8_BUS_SPI1`, `transport`, and `ncs`.
Change defaults to SPI1. Keep the I2C duplicate-address validation only for
I2C slots on the same bus. Reject duplicate `NCS` for SPI slots on the same bus.

- [ ] **Step 4: Verify topology test**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make build/test_tof_l8_topology
build/test_tof_l8_topology
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```sh
git add firmware/stm32-mcp/Core/Inc/tof_l8_topology.h \
        firmware/stm32-mcp/Core/Src/tof_l8_topology.c \
        firmware/stm32-mcp/tests/host/test_tof_l8_topology.c
git commit -m "Firmware: Prefer SPI topology for dual VL53L8"
```

## Task 11: Add Target SPI Transport

- [ ] **Step 1: Refactor current I2C callbacks behind transport**

Move the current I2C callback logic from `tof_l8.c` to target-only functions in
`tof_l8_transport.c`. Keep the public callback signatures compatible with
`VL53L8CX_Platform`.

- [ ] **Step 2: Add SPI1 init**

Add `SPI_HandleTypeDef hspi1`, `MX_SPI1_Init()`, and SPI1 clock enable. SPI1
uses `D13/PA5` SCK, `D12/PA6` MISO, and `D11/PA7` MOSI. Use SPI mode 3, MSB
first, 8-bit data, software NSS, and a prescaler that stays at or below 3 MHz.

- [ ] **Step 3: Add SPI callbacks**

Implement VL53L8CX SPI read/write framing:

```text
write: assert NCS low, send 16-bit register with bit 15 set, send payload, NCS high
read:  assert NCS low, send 16-bit register with bit 15 clear, receive payload, NCS high
```

Refresh the watchdog before each blocking transfer.

- [ ] **Step 4: Probe I2C then SPI at boot**

In `TofL8_Init()`, build an I2C platform and call `vl53l8cx_is_alive()`. If it
answers, keep I2C. Otherwise build an SPI platform and call `vl53l8cx_is_alive()`.
If SPI answers, keep SPI. If neither answers, return `TOF_STATUS_NO_SENSOR`.
Log every transport attempt and the selected transport.

- [ ] **Step 5: Build target firmware**

Run:

```sh
cd firmware/stm32-mcp
./build.sh build
```

Expected: target firmware builds.

- [ ] **Step 6: Run host tests**

Run:

```sh
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

- [ ] **Step 7: Commit**

Run:

```sh
git add firmware/stm32-mcp/Core/Inc/main.h \
        firmware/stm32-mcp/Core/Inc/tof_l8_transport.h \
        firmware/stm32-mcp/Core/Src/main.c \
        firmware/stm32-mcp/Core/Src/stm32l4xx_hal_msp.c \
        firmware/stm32-mcp/Core/Src/tof_l8.c \
        firmware/stm32-mcp/Core/Src/tof_l8_transport.c \
        firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt
git commit -m "Firmware: Probe VL53L8 over I2C or SPI"
```

## Task 12: Update Bring-Up Docs

- [ ] **Step 1: Add SPI wiring table**

Update `firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md` with the
single-sensor SPI wiring table and the boot-time probe logs.

- [ ] **Step 2: Add two-sensor SPI plan**

Document shared SPI1 with separate rear/front `NCS`, `LPn`, and optional
`GPIO1`.

- [ ] **Step 3: Commit**

Run:

```sh
git add firmware/stm32-mcp/docs/dev/10-vl53l8-satel-bringup.md
git commit -m "Docs: Add VL53L8 SPI bring-up wiring"
```
