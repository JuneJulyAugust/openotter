# VL53L5CX Reverse Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use VL53L5CX 4x4 row 3 center zones for firmware reverse safety and stop full depth-map streaming in Self Driving view.

**Architecture:** Add a small HAL-free L5 safety selector, feed its output into the existing `RevSafety_Tick` path, and configure L5 safety mode on Drive entry. Keep FE62 depth frames Debug-only and keep STM32 Control view as the debug tool.

**Tech Stack:** STM32 C firmware, HAL-free host C tests, Swift iOS BLE client tests.

---

### Task 1: Add L5 Safety Selector

**Files:**
- Create: `firmware/stm32-mcp/Core/Inc/rev_safety_l5.h`
- Create: `firmware/stm32-mcp/Core/Src/rev_safety_l5.c`
- Create: `firmware/stm32-mcp/tests/host/test_rev_safety_l5.c`
- Modify: `firmware/stm32-mcp/tests/host/Makefile`

- [ ] **Step 1: Write failing host test**

Add tests that build `Tof_Frame_t` fixtures and assert selected-zone behavior:

```c
static void test_uses_min_of_row3_center_zones(void) {
  Tof_Frame_t f = make_l5_4x4();
  f.zones[9].range_mm = 900u;
  f.zones[9].status = 0u;
  f.zones[10].range_mm = 700u;
  f.zones[10].status = 0u;
  RevSafetyTofReading_t r = RevSafetyL5_SelectReverseReading(&f);
  expect_class("min class", r.tof_class, REV_SAFETY_TOF_VALID);
  expect_near("min depth", r.depth_m, 0.7f, 1e-6f);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make build/test_rev_safety_l5
```

Expected: compile fails because `rev_safety_l5.h` does not exist.

- [ ] **Step 3: Implement selector**

Implement `RevSafetyL5_SelectReverseReading(const Tof_Frame_t *frame)`.

Rules:

- Accept only `TOF_SENSOR_VL53L5CX`, layout `4`, at least `16` zones.
- Consider indices `9` and `10`.
- A zone is valid when status is usable and range is nonzero.
- Return minimum valid depth.
- Return invalid if neither selected zone is valid.

- [ ] **Step 4: Run host tests**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

### Task 2: Feed L5 Into Reverse Safety

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_app.c`
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof.c`
- Modify: `firmware/stm32-mcp/Core/Src/rev_safety_tof.c`
- Modify: `firmware/stm32-mcp/Core/Inc/rev_safety_tof.h`
- Modify: `firmware/stm32-mcp/tests/host/test_rev_safety_tof.c`

- [ ] **Step 1: Update L1 clear-distance test first**

Change `test_rev_safety_tof.c` expected clear depth to `4.0f`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make build/test_rev_safety_tof && build/test_rev_safety_tof
```

Expected: fails while constant is still `3.0f`.

- [ ] **Step 3: Change clear distance**

Set `REV_SAFETY_TOF_CLEAR_DEPTH_M` to `4.0f`.

- [ ] **Step 4: Enforce L5 safety config**

Change `BLE_Tof_EnforceSafetyConfig()` to configure:

```c
Tof_Config_t cfg = {
  .sensor_type = TOF_SENSOR_VL53L5CX,
  .layout = 4,
  .profile = TOF_PROFILE_L5_CONTINUOUS,
  .frequency_hz = 30,
  .integration_ms = 20,
  .budget_ms = 0,
};
```

Call `TofL5_EnsureInitialized()` before `TofL5_Configure(&cfg)`.

- [ ] **Step 5: Switch `BLE_App_Process` safety input**

Use `TofL5_GetLatestFrame()` and `RevSafetyL5_SelectReverseReading()` instead of `TofL1_GetLatestFrame()` center zone.

- [ ] **Step 6: Run host tests**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

### Task 3: Gate Full Depth Frames To Debug Mode

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof.c`
- Modify: `firmware/stm32-mcp/Core/Src/ble_tof_policy.c`
- Modify: `firmware/stm32-mcp/tests/host/test_ble_tof_policy.c`

- [ ] **Step 1: Add policy test**

Assert frame streaming is allowed only in Debug mode.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make build/test_ble_tof_policy && build/test_ble_tof_policy
```

Expected: fails because policy function is missing.

- [ ] **Step 3: Add policy and apply in `BLE_Tof_Process`**

Add `BLE_Tof_FrameStreamAllowed(mode)` and return early from FE62 frame publish in Drive/Park while still refreshing FE63 status.

- [ ] **Step 4: Run host tests**

Run:

```bash
cd firmware/stm32-mcp/tests/host
make test
```

Expected: all host tests pass.

### Task 4: LED2 L5 Activity Heartbeat

**Files:**
- Modify: `firmware/stm32-mcp/Core/Src/main.c`

- [ ] **Step 1: Add main-loop heartbeat**

Track `TofL5_GetLatestFrame()->seq`. If it changes, record tick. Toggle LED2 once per 1000 ms while frames are fresh. If no frame for more than 1500 ms, force LED2 low.

- [ ] **Step 2: Run firmware compile check**

Run the repo firmware build command from existing dev docs or Makefile/CMake target available in the workspace.

Expected: firmware compiles.

### Task 5: iOS Self Driving Does Not Request Depth Map

**Files:**
- Modify: `openotter-ios/Sources/Capture/SelfDrivingViewModel.swift` if needed
- Modify: `openotter-ios/Tests/Capture/STM32TofServiceTests.swift`

- [ ] **Step 1: Keep self-driving in Drive mode only**

No FE61 ToF config is sent from `SelfDrivingViewModel`. Existing `STM32ControlViewModel` remains Debug and sends config.

- [ ] **Step 2: Run iOS build**

Run:

```bash
cd openotter-ios
xcodebuild build -scheme openotter -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: build succeeds.

### Task 6: Final Verification And Commit

**Files:**
- All changed files

- [ ] **Step 1: Run checks**

Run:

```bash
git diff --check
cd firmware/stm32-mcp/tests/host && make test
cd ../../../openotter-ios && xcodebuild build -scheme openotter -destination 'platform=iOS Simulator,name=iPhone 17'
```

- [ ] **Step 2: Commit**

Commit message:

```bash
git commit -m "feat: use VL53L5CX for reverse safety"
```
