# 05 — Extending the Firmware (Sensors, Pose, ToF)

This document is a cookbook for adding new features on top of the
existing control firmware. It assumes you have already read
`03-architecture.md` (source layout, execution model) and
`04-ble-integration.md` (GATT flow).

The B-L475E-IOT01A is a rich reference board. Most of the sensors below
are soldered on and wired to buses that `MX_GPIO_Init` already brings
up — you "only" need drivers and a fusion pipeline. The goal of this
doc is not to write those drivers for you, but to tell you where to put
them so the rest of the firmware remains testable and extensible.

Topics:
1. Design pattern for new subsystems
2. Reading the IMU (LSM6DSL + LIS3MDL)
3. Pose estimation skeleton
4. VL53L0X time-of-flight range sensor
5. Exposing new data over BLE

---

## 1. Recommended pattern: one subsystem = one pair of files

Every new peripheral or algorithm should live in its own pair of files
under `Core/`:

```
Core/Inc/<subsystem>.h
Core/Src/<subsystem>.c
```

Public API (in the header) should be three functions:

```c
int  <Subsystem>_Init(...);   // idempotent, returns 0 on success
void <Subsystem>_Process(void);    // called once per main-loop iteration
/* + any data getters / setters the subsystem needs to expose */
```

Then:
1. Add the `.c` file to `MX_Application_Src` in
   `cmake/stm32cubemx/CMakeLists.txt` (under `# STM32CubeMX generated
   application sources`).
2. Call `<Subsystem>_Init` from `main.c` just before `BLE_App_Init`.
3. Call `<Subsystem>_Process` from the main `while(1)` loop, alongside
   `BLE_App_Process`.

Why this shape:
- It mirrors `ble_app.c`, so the main loop stays uniform and readable.
- Init is idempotent so you can re-init after a fault without rebooting.
- Process is a cooperative step — never block, never spin. If the driver
  needs to wait for an ISR, let the ISR `SCH_SetTask(...)` and handle
  the work in the scheduler callback (same pattern as `BLE_TlEvtTask`).

### 1.1 Keep the interface narrow

Follow the project's SOLID guidelines (see `CLAUDE.md`):
- Don't pass `htim3` into a function that only needs a pulse-width
  setter.
- Don't expose sensor raw values *and* filtered values *and* calibration
  parameters from the same struct — split into an interface for each
  consumer.
- Never `#include "main.h"` from a sensor driver just to grab pin
  macros. Put pin names in the subsystem header, or pass them in.

### 1.2 Testability

Unit-testing MCU code end-to-end is impractical, but algorithm modules
(complementary filter, Madgwick, EKF, any math that doesn't require a
HAL call) should be written as **pure functions** that take
plain-C structs. Keep those in a separate `.c` file and you can compile
them under a native GCC into a test harness on macOS. Do **not** test
private functions through the public API; if you're tempted to, extract
the math into its own component.

---

## 2. IMU: LSM6DSL (accel + gyro) + LIS3MDL (mag)

### 2.1 Hardware

Both sensors sit on the internal **I²C2** bus, which `MX_I2C2_Init` has
already configured (PB10 SCL / PB11 SDA, fast-mode 400 kHz, timing word
`0x10D19CE4`).

| Sensor     | I²C address (7-bit) | Data-ready IRQ pin   |
|------------|---------------------|----------------------|
| LSM6DSL    | `0x6A` (SA0=0)      | PD11 (EXTI11)        |
| LIS3MDL    | `0x1E` (SA1=0)      | PC8  (EXTI8)         |

Both DRDY pins are already configured as EXTI rising in
`MX_GPIO_Init` and already routed through `EXTI15_10_IRQHandler` and
`EXTI9_5_IRQHandler` respectively. The IRQ handlers currently dispatch
to `HAL_GPIO_EXTI_Callback`, which in `ble_app.c:474` only matches
`GPIO_PIN_6` (BlueNRG IRQ). Extend that function with additional
`else if` branches for your pins:

```c
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    if      (GPIO_Pin == GPIO_PIN_6)  { HW_BNRG_SpiIrqCb(); }
    else if (GPIO_Pin == GPIO_PIN_11) { SCH_SetTask(CFG_IdleTask_Imu); }
    else if (GPIO_Pin == GPIO_PIN_8)  { SCH_SetTask(CFG_IdleTask_Mag); }
}
```

You will need to declare new task IDs in `ble_config.h` and register
them in `BLE_App_Init` (or a new `Imu_Init`).

### 2.2 Driver strategy — three options

| Approach                                 | Pros                          | Cons                                         |
|------------------------------------------|-------------------------------|----------------------------------------------|
| Roll your own minimal driver             | Small, no deps                | You write/verify every register access       |
| Import ST's `lsm6dsl_reg.c` platform-independent driver from [STMems drivers](https://github.com/STMicroelectronics/STMems_Standard_C_drivers) | Well-tested, self-test routines | One more 3rd-party dep                       |
| Use X-CUBE-MEMS1 BSP (same upstream repo we forked from) | Highest level — returns g / dps | Pulls in an entire "board" abstraction we don't need |

Recommended: **option 2**. Drop `lsm6dsl_reg.c` / `.h` into
`Core/Drivers/lsm6dsl/`, wire its `read_reg` / `write_reg` callbacks to
our `HAL_I2C_Mem_Read` / `HAL_I2C_Mem_Write`, and expose an
`Imu_GetAccelGyro(float[3], float[3])` from `imu.c`.

### 2.3 Sampling policy

The safety watchdog is 1.5 s, so anything slower than ~10 Hz is fine.
Typical pose work wants ≥ 100 Hz; both sensors support 416 Hz easily.
Options for driving the sample rate:

- **DRDY-driven**: enable DRDY on the sensor, let the EXTI handler kick
  a scheduler task. Simple, jitter-free.
- **Main-loop polled**: skip the IRQ, poll the status register in
  `Imu_Process`. Safer as a first cut — the main loop already runs at
  several kHz, so you'll never starve the sensor.

Start with polled, switch to DRDY once you need deterministic timing
(e.g. for control loops tighter than 50 Hz).

---

## 3. Pose estimation with on-board sensors

### 3.1 What "pose" can realistically mean on this board

| Sensor set                                      | What you recover                                  |
|-------------------------------------------------|---------------------------------------------------|
| Gyro only (LSM6DSL gyroscope)                   | Attitude rate; short-term integration only (drifts) |
| Gyro + accel                                    | Roll / pitch (good), yaw (drifts)                  |
| Gyro + accel + magnetometer (LIS3MDL)           | Full 3D attitude (roll / pitch / yaw)              |
| + LPS22HB barometer                             | Add relative altitude                              |
| + wheel odometry / GNSS / vision                | Position in world frame (requires external sensor) |

For a ground robot on a mostly horizontal surface, the minimum useful
pose is **roll/pitch/yaw from gyro+accel+mag**.

### 3.2 Suggested pipeline

```
  ┌────────┐   raw a [m/s²]       ┌─────────────────────┐
  │ LSM6   │ ───────────────────▶ │                     │
  │ DSL    │   raw ω [rad/s]      │   Sensor fusion     │
  └────────┘ ───────────────────▶ │  (Madgwick or       │    quaternion q
                                  │   complementary)    │ ───────────────▶
  ┌────────┐   raw B [gauss]      │                     │    Euler angles
  │ LIS3MDL│ ───────────────────▶ │                     │
  └────────┘                      └─────────────────────┘
```

### 3.3 Implementation skeleton

`Core/Inc/pose.h`:

```c
#pragma once
#include <stdint.h>

typedef struct {
    float q[4];                 // unit quaternion (w, x, y, z), Hamilton convention
    float roll_rad, pitch_rad, yaw_rad;
    uint32_t last_update_ms;
} PoseState_t;

int  Pose_Init(float sample_rate_hz);
void Pose_Update(const float accel_ms2[3],
                 const float gyro_rads[3],
                 const float mag_gauss[3]);
const PoseState_t *Pose_Get(void);
```

`Core/Src/pose.c` implements `Pose_Update` as pure math — no HAL calls.
That lets you unit-test it on the host by feeding canned IMU traces.

A decent starting algorithm is the
[Madgwick AHRS](https://ahrs.readthedocs.io/en/latest/filters/madgwick.html).
It needs no matrix libraries, runs in ~200 µs at 100 Hz on an M4 with
the FPU, and converges within a few seconds on mag lock. If you want
something Kalman-shaped later, use the quaternion state from Madgwick
as the initial estimate.

### 3.4 Calibration

Three calibrations matter, in descending order of importance:

1. **Gyro bias** — leave the board stationary for ~5 s at boot, average
   the gyro output, subtract from every subsequent sample.
2. **Accel scale + offset** — 6-position static calibration; store the
   calibration matrix in a private section of FLASH or in QSPI.
3. **Hard- / soft-iron magnetometer calibration** — rotate the board
   through all orientations, fit an ellipsoid to the samples.

Put calibration data in `pose_calib.h` so the runtime code can be
recompiled with new constants without touching the algorithm.

### 3.5 Integrating pose into the main loop

In `main.c`:

```c
Imu_Init();
Pose_Init(100.0f);         // target 100 Hz
...
while (1) {
    BLE_App_Process();
    Imu_Process();         // reads latest a, ω, B when available
    /* inside Imu_Process, once a new sample arrives: */
    /* Pose_Update(imu_a, imu_g, mag_B);                */
    /* …LED toggle… */
}
```

Keep `Pose_Update` out of ISRs. The math is fine, but FPU context save
in the M4's exception stack grows 17 words when you touch floats in an
ISR — avoidable cost.

---

## 4. VL53L0X time-of-flight range sensor

> **Note:** On the prototype hardware the on-board VL53L0X is disabled
> (XSHUT held LOW). The project now ships with a longer-range **VL53L1CB**
> on the VL53L1-Satel breakout wired to Arduino A4/A5 (I²C3). For the
> VL53L1CB driver, ROI math, GATT service `0xFE60`, and iOS grid viewer,
> see [06-vl53l1cb-multizone-tof.md](06-vl53l1cb-multizone-tof.md). The
> section below remains as reference for the on-board L0X.

### 4.1 Hardware

The VL53L0X sits on **I²C1** (PB8 SCL / PB9 SDA, AF4), **not** I²C2.
`MX_I2C1_Init` is **not** generated — if you want to use the ToF, add it
to `stm32-mcp.ioc` in CubeMX and regenerate, or configure I²C1 by hand.

Other signals (already configured in `MX_GPIO_Init`):

| Signal          | MCU pin | Direction | Purpose                                      |
|-----------------|---------|-----------|----------------------------------------------|
| XSHUT (shutdown)| PC6     | Out       | Held low at boot → sensor off until firmware raises it |
| GPIO1 (IRQ)     | PC7     | EXTI ↑    | Interrupt on range-ready (optional)          |

The XSHUT pin is driven by the firmware specifically so the host can
sequence power-on — useful if you ever add a second VL53L0X that has
the same factory I²C address (`0x29`) and must be re-addressed at boot.

### 4.2 Driver

Use ST's VL53L0X platform-independent driver. Unlike the IMU which lives on GitHub,
the VL53L0X API is distributed via the ST website as
[STSW-IMG005](https://www.st.com/en/embedded-software/stsw-img005.html). Download the
C API from there, and port the two I²C callbacks to `HAL_I2C_Mem_Read` / `HAL_I2C_Mem_Write` on
`hi2c1`. API you care about:

```c
VL53L0X_Dev_t Dev = { .I2cDevAddr = 0x29 << 1 };
VL53L0X_DataInit(&Dev);
VL53L0X_StaticInit(&Dev);
VL53L0X_PerformRefCalibration(&Dev, &phaseCal, &xtalkCal);
VL53L0X_SetDeviceMode(&Dev, VL53L0X_DEVICEMODE_CONTINUOUS_RANGING);
VL53L0X_StartMeasurement(&Dev);

VL53L0X_RangingMeasurementData_t data;
VL53L0X_GetRangingMeasurementData(&Dev, &data);
uint16_t mm = data.RangeMilliMeter;
```

Wrap that in a `Tof_Init` / `Tof_Process` / `Tof_GetRangeMm()` trio as
in section 1.

### 4.3 Power-up sequence (important)

```
boot:
    PC6 (XSHUT) is already LOW from MX_GPIO_Init → sensor off
Tof_Init:
    raise PC6                       // release XSHUT
    wait 2 ms for boot
    I²C2 ping at 0x29 → expect ACK
    (optionally) VL53L0X_SetI2CAddress(new_addr)
    VL53L0X_DataInit / StaticInit / StartMeasurement
```

Getting XSHUT wrong is the #1 cause of "sensor doesn't ACK on I²C1".

### 4.4 Range limits & use cases

VL53L0X has a usable range of ~30 mm to ~1200 mm in default mode,
extendable to ~2 m in long-range mode at the cost of ambient light
tolerance. Sample rate up to 50 Hz. Good for close-range collision
avoidance or payload-detection; **not** good for SLAM — a single beam
with ~25° field of view.

---

## 5. Exposing new data over BLE

Once the MCU has pose / range / other state, the natural next step is
publishing it to the iOS app.

### 5.1 Adding a second GATT service

In `ble_app.c` (or a new `telemetry_app.c` following the same pattern):

```c
#define OPENOTTER_TELEMETRY_SVC_UUID    0xFE50
#define OPENOTTER_POSE_CHAR_UUID        0xFE51    // notify, 16 bytes (quat)
#define OPENOTTER_RANGE_CHAR_UUID       0xFE52    // notify, 2 bytes (mm, u16)

uint16_t uuid = OPENOTTER_TELEMETRY_SVC_UUID;
aci_gatt_add_serv(UUID_TYPE_16, (const uint8_t *)&uuid, PRIMARY_SERVICE,
                  1 + 3 + 3, &telSvcHandle);    // 1 svc + 3 char (2 val + 1 CCCD)

uuid = OPENOTTER_POSE_CHAR_UUID;
aci_gatt_add_char(telSvcHandle, UUID_TYPE_16, (const uint8_t *)&uuid,
                  16, CHAR_PROP_NOTIFY, ATTR_PERMISSION_NONE,
                  GATT_NOTIFY_ATTRIBUTE_WRITE, 10, 0, &poseCharHandle);
```

Remember to bump **`BLE_CFG_SVC_MAX_NBR_CB`** in `ble_config.h` if your
new service registers its own handler via `SVCCTL_RegisterSvcHandler`.

### 5.2 Publishing notifications

```c
void Telemetry_Process(void)
{
    if (!BLE_App_IsConnected()) return;

    const PoseState_t *p = Pose_Get();
    uint8_t payload[16];
    memcpy(payload,     &p->q[0], 16);     // 4 × float32

    aci_gatt_update_char_value(telSvcHandle, poseCharHandle,
                               0, sizeof(payload), payload);
}
```

Call `Telemetry_Process` from the main loop, throttled to whatever rate
the iOS app can comfortably consume (10–50 Hz). Don't notify from inside
an ISR — `aci_gatt_update_char_value` is not reentrant.

### 5.3 Suggested characteristic layout

| UUID   | Type   | Property       | Payload                                                 |
|--------|--------|----------------|---------------------------------------------------------|
| 0xFE40 | Svc    | —              | existing control service                                |
| 0xFE41 | Char   | Write          | existing steering/throttle command                      |
| 0xFE42 | Char   | Notify / Read  | status (firmware version, safety state)                 |
| 0xFE50 | Svc    | —              | new telemetry service                                   |
| 0xFE51 | Char   | Notify         | 16-byte pose quaternion (4 × float32, wxyz)             |
| 0xFE52 | Char   | Notify         | 2-byte ToF range in mm (uint16 little-endian)           |
| 0xFE53 | Char   | Notify         | 6-byte raw accel [m/s²] (3 × int16, scale 1/100)        |
| 0xFE54 | Char   | Notify         | 6-byte raw gyro [rad/s] (3 × int16, scale 1/1000)       |

Pick fixed-length payloads wherever possible — variable-length
notifications complicate the iOS side.

---

## 6. Where not to put new code

- **Don't** edit files under `Drivers/` or under `BLE/ble_core/`,
  `BLE/tl/`, `BLE/hw/`, `BLE/utilities/` unless you are upstreaming a
  fix. Keeping them pristine makes CubeL4 version bumps trivial.
- **Don't** add sensor polling inside `BLE_App_Process`. It is the BLE
  path — mixing concerns there makes both harder to reason about.
- **Don't** introduce a second timer (TIM2, TIM4) just for PWM without
  first asking whether TIM3 CH2/CH3 could give you another pair of
  outputs on PB0 (`ARD_D3`) and PC8 (`LSM3MDL_DRDY_EXTI8_Pin` — already
  used as DRDY, so pick a different pin).

When in doubt, model your new file after `ble_app.c`. Init once, process
each loop, keep the math pure.
