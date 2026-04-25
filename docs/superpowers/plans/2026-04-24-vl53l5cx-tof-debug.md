# VL53L5CX ToF Debug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add VL53L5CX 4x4/8x8 debug streaming over the existing ToF BLE service while keeping VL53L1CB code available and leaving reverse safety unchanged.

**Architecture:** Introduce sensor-generic ToF frame/config types and a variable-size frame chunk codec. The VL53L5CX backend becomes the active debug backend; the existing VL53L1CB backend remains in-tree. iOS reassembles V2 chunks and renders 4x4/8x8 maps through the existing debug card.

**Tech Stack:** STM32 HAL C11, BlueNRG-MS GATT notifications, ST VL53L5CX ULD, Swift/CoreBluetooth/SwiftUI, host C tests, XCTest.

---

## File Structure

- Create `firmware/stm32-mcp/Core/Inc/tof_types.h`: shared generic ToF enums, config, frame, zone structs, and status codes.
- Create `firmware/stm32-mcp/Core/Inc/tof_frame_codec.h`: pure C chunk encoder API.
- Create `firmware/stm32-mcp/Core/Src/tof_frame_codec.c`: V2 serialization and 20-byte chunk generation.
- Create `firmware/stm32-mcp/tests/host/test_tof_frame_codec.c`: host tests for 4x4/8x8 chunking.
- Modify `firmware/stm32-mcp/tests/host/Makefile`: build new codec test.
- Create `firmware/stm32-mcp/Core/Inc/tof_l5.h`: VL53L5CX wrapper public interface.
- Create `firmware/stm32-mcp/Core/Src/tof_l5.c`: wrapper skeleton with hardware reset/pin config and ULD integration seam.
- Modify `firmware/stm32-mcp/Core/Src/main.c`: initialize/process L5 debug backend while keeping L1 code present.
- Modify `firmware/stm32-mcp/Core/Inc/main.h`: add friendly defines for MSP01 L5 reset/interrupt pins.
- Modify `firmware/stm32-mcp/Core/Src/ble_tof.c`: use generic V2 codec when active backend is L5; keep V1 compatibility only if L1 backend selected.
- Modify `firmware/stm32-mcp/Core/Inc/ble_tof.h`: document V2 FE61/FE62 protocol.
- Modify `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`: add new sources and later driver include/source globs.
- Modify `openotter-ios/Sources/Capture/TofTypes.swift`: add V2 sensor/config/frame parsing while preserving current models enough for UI.
- Modify `openotter-ios/Sources/Capture/STM32TofService.swift`: V2 chunk reassembly, config encoding, drop counters.
- Modify `openotter-ios/Sources/Capture/STM32ControlViewModel.swift`: L5 config state and send methods.
- Modify `openotter-ios/Sources/Views/STM32ControlView.swift`: expose L5 controls and 8x8 diagnostics.
- Modify `openotter-ios/Sources/Views/TofGridView.swift`: ensure 8x8 cells stay readable.
- Create or modify `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`: parser/config/reassembly tests.

### Task 1: Firmware V2 Frame Codec

**Files:**
- Create: `firmware/stm32-mcp/Core/Inc/tof_types.h`
- Create: `firmware/stm32-mcp/Core/Inc/tof_frame_codec.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_frame_codec.c`
- Create: `firmware/stm32-mcp/tests/host/test_tof_frame_codec.c`
- Modify: `firmware/stm32-mcp/tests/host/Makefile`

- [x] **Step 1: Write failing host test**

Add `test_tof_frame_codec.c` with tests that expect a 4x4 frame to serialize to 80 bytes payload, a 8x8 frame to serialize to 272 bytes payload, and chunk data size to be 18 bytes.

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make clean
make test
```

Expected: FAIL because `tof_frame_codec.h` does not exist.

- [x] **Step 3: Implement generic ToF types and codec**

Add:

```c
typedef struct __attribute__((packed)) {
  uint16_t range_mm;
  uint8_t status;
  uint8_t flags;
} Tof_Zone_t;

typedef struct {
  uint8_t sensor_type;
  uint8_t layout;
  uint8_t zone_count;
  uint8_t profile;
  uint32_t seq;
  uint32_t tick_ms;
  Tof_Zone_t zones[64];
} Tof_Frame_t;
```

Implement `TofFrameCodec_Serialize()` and `TofFrameCodec_MakeChunk()` with fixed 20-byte chunks:

```c
#define TOF_FRAME_V2_VERSION 2u
#define TOF_FRAME_CHUNK_SIZE 20u
#define TOF_FRAME_CHUNK_DATA 18u
```

- [x] **Step 4: Run host tests**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

### Task 2: iOS V2 Parser and Config Encoding

**Files:**
- Modify: `openotter-ios/Sources/Capture/TofTypes.swift`
- Modify: `openotter-ios/Sources/Capture/STM32TofService.swift`
- Create or modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`

- [x] **Step 1: Write failing XCTest**

Add tests for:

- `VL53L5CX 4x4 config encodes FE61 as [2,4,1,freq,u16 integration,u16 budget]`
- V2 4x4 frame parse returns 16 zones.
- V2 8x8 frame parse returns 64 zones.
- Out-of-order chunk is dropped.

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
cd openotter-ios
xcodegen generate
xcodebuild test -scheme OpenOtter -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: FAIL because V2 parser/config APIs do not exist.

- [x] **Step 3: Implement Swift V2 parse/reassembly**

Add `TofSensorType`, extend `TofConfig`, and update `STM32TofService` to support chunk header `[idx|last, seqLow, 18 payload bytes]`.

- [x] **Step 4: Run iOS tests**

Run the same `xcodebuild test` command.

Expected: parser/config tests pass.

### Task 3: BLE FE60 V2 Transport

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof.c`
- Modify: `firmware/stm32-mcp/Core/Inc/ble_tof.h`
- Modify: `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`

- [x] **Step 1: Write failing host coverage if logic is pure**

If any config validation is extracted into a pure function, add it to `test_tof_frame_codec.c`. Otherwise rely on firmware build for this task.

- [x] **Step 2: Update BLE chunk sender**

Replace fixed 76-byte chunk assumptions with `TofFrameCodec_Serialize()` and `TofFrameCodec_MakeChunk()`.

- [x] **Step 3: Update config parser**

Interpret FE61 byte 0 as `sensor_type`, byte 1 as `layout`, byte 2 as `profile`, byte 3 as `frequency_hz`, bytes 4..5 as `integration_ms`, bytes 6..7 as `budget_ms`.

- [x] **Step 4: Build firmware**

Run:

```bash
cd firmware/stm32-mcp
./build.sh
```

Expected: firmware builds.

### Task 4: VL53L5CX Backend Skeleton

**Files:**
- Create: `firmware/stm32-mcp/Core/Inc/tof_l5.h`
- Create: `firmware/stm32-mcp/Core/Src/tof_l5.c`
- Modify: `firmware/stm32-mcp/Core/Src/main.c`
- Modify: `firmware/stm32-mcp/Core/Inc/main.h`
- Modify: `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`

- [x] **Step 1: Add host-testable config validation**

Extend `test_tof_frame_codec.c` with validation expectations for L5 layouts 4/8 and rejected layout 3.

- [x] **Step 2: Implement L5 wrapper seam**

Add `TofL5_Init`, `TofL5_Configure`, `TofL5_Process`, `TofL5_GetLatestFrame`, `TofL5_HasNewFrame`, and `TofL5_ClearNewFrame`. Until ULD is imported, compile the backend as `TOF_L5_ERR_DRIVER_MISSING` without breaking firmware build.

- [x] **Step 3: Wire MSP01 pins**

Define PC3 interrupt and PC4 reset names. Toggle PC4 low/high before init. Do not enable reverse safety on L5.

- [x] **Step 4: Build firmware**

Run:

```bash
cd firmware/stm32-mcp
./build.sh
```

Expected: firmware builds with missing-driver backend status.

### Task 5: Import ST VL53L5CX ULD

**Files:**
- Create: `firmware/stm32-mcp/Drivers/VL53L5CX/**`
- Modify: `firmware/stm32-mcp/Core/Src/tof_l5.c`
- Modify: `firmware/stm32-mcp/cmake/stm32cubemx/CMakeLists.txt`

- [x] **Step 1: Fetch official ULD package**

Use the official STSW-IMG023 package from ST. If the direct package requires manual license acceptance, stop and ask the user to place the package under `firmware/stm32-mcp/Drivers/VL53L5CX/`.

- [x] **Step 2: Add STM32 HAL platform port**

Map ULD I2C read/write/wait primitives to `hi2c3` and HAL delays.

- [x] **Step 3: Replace missing-driver skeleton with ULD calls**

Use ULD init/config/start/check/get-data APIs and fill `Tof_Frame_t` zones.

- [x] **Step 4: Build firmware**

Run:

```bash
cd firmware/stm32-mcp
./build.sh
```

Expected: firmware links with VL53L5CX driver.

### Task 6: iOS Debug UI

**Files:**
- Modify: `openotter-ios/Sources/Views/STM32ControlView.swift`
- Modify: `openotter-ios/Sources/Views/TofGridView.swift`
- Modify: `openotter-ios/Sources/Capture/STM32ControlViewModel.swift`

- [x] **Step 1: Add UI tests if available**

If this project has snapshot/UI tests, add a 8x8 rendering test. Otherwise keep parser tests as coverage.

- [x] **Step 2: Add controls**

Expose resolution 4x4/8x8, frequency, integration, observed Hz, dropped chunks, and sensor type.

- [x] **Step 3: Check layout build**

Run:

```bash
cd openotter-ios
xcodegen generate
xcodebuild build -scheme OpenOtter -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: app builds.

### Task 7: Documentation and Verification

**Files:**
- Create: `firmware/stm32-mcp/docs/dev/08-vl53l5cx-tof-debug.md`
- Modify: `firmware/stm32-mcp/docs/dev/README.md`

- [x] **Step 1: Document wiring and bring-up**

Include the 3V3 warning, PC0/PC1/PC3/PC4 mapping, FE60 V2 protocol, and hardware validation checklist.

- [x] **Step 2: Run final verification**

Run:

```bash
cd firmware/stm32-mcp/tests/host && make test
cd ../../.. && ./firmware/stm32-mcp/build.sh
cd openotter-ios && xcodegen generate && xcodebuild test -scheme OpenOtter -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: host tests pass, firmware builds, iOS tests pass.

## Self-Review

- Spec coverage: wiring warning, L5 debug-first, L1 retained, variable BLE frames, iOS 4x4/8x8 debug, and no reverse-safety migration all map to tasks.
- Placeholder scan: no TODO/TBD placeholders remain. Driver import has an explicit stop condition if ST license flow blocks direct package fetch.
- Type consistency: `Tof_Frame_t`, `Tof_Zone_t`, FE61 V2 bytes, and 20-byte chunk geometry are consistent across tasks.
