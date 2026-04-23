# STM32 Reverse Safety Supervisor & iOS↔Firmware Safety Protocol — Design

**Status:** Design complete — awaiting user review before implementation planning
**Date:** 2026-04-23
**Scope:** STM32 firmware safety supervisor for reverse-direction collision avoidance using the rear-facing VL53L1CB ToF sensor, plus the BLE protocol that carries velocity from iOS to firmware and emergency state from firmware to iOS.

---

## 1. Purpose and Split of Responsibility

The iPhone is mounted facing forward. Its LiDAR feeds the iOS `SafetySupervisor` which handles **forward** collision avoidance. See `openotter-ios/Sources/Planner/Safety/DESIGN.md` for the forward policy — its critical-distance formula, latched-speed rule, and release logic are the reference this document builds on.

This document covers the symmetric problem: **reverse** collision avoidance using the VL53L1CB ToF sensor mounted on the STM32 board, facing rearward. Because the MCU has direct, low-latency control of the PWM outputs, the reverse supervisor runs on the firmware rather than on iOS.

Split of responsibility:

| Direction | Sensor                | Supervisor location | Overrides |
|-----------|-----------------------|---------------------|-----------|
| Forward   | iPhone LiDAR (30 Hz)  | iOS                 | Forces throttle to neutral when forward obstacle too close. |
| Reverse   | VL53L1CB ToF (~4 Hz)  | STM32 firmware      | Forces throttle to neutral when rear obstacle too close while reversing. |

Both supervisors produce a binary SAFE/BRAKE state and force the throttle to neutral on BRAKE. Neither commands a reverse torque to stop (see iOS DESIGN.md §5.1.1 for the rationale — it applies identically here).

---

## 2. Sensor Configuration (Hard Requirement)

The VL53L1CB is locked to the configuration that was validated on the bench:

- **Layout:** 3×3 multi-zone.
- **Distance mode:** LONG.
- **Per-zone timing budget:** 30 ms → total scan period ≈ 270 ms, effective rate ≈ 4 Hz.
- **Valid range:** up to ~2.3 m (bench-measured under the above config).

The supervisor consumes only the **center zone** (index 4 in the 3×3 grid, top-to-bottom left-to-right). The narrower field of view is preferred over the full 3×3 mean for reverse safety — it corresponds to the path directly behind the vehicle and avoids false triggers from off-axis obstacles that the vehicle will not actually hit.

Zones with a non-OK `VL53L1_RangeStatus` (anything other than `0 = OK`) are treated as **invalid** measurements. Out-of-range, signal fail, phase fail, wrap-around — all collapse to the same "no trustworthy depth this tick" signal. Handling of invalid samples is policy-level — see §3.4.

---

## 3. Design

### 3.1 Velocity Transport (iOS → MCU)

The 0xFE41 command characteristic is extended from 4 bytes to **6 bytes**:

```c
typedef struct __attribute__((packed)) {
  int16_t steering_us;       // pulse width, microseconds
  int16_t throttle_us;       // pulse width, microseconds
  int16_t velocity_mm_per_s; // signed; negative = reversing
} BLE_CommandPayload_t;
```

- Little-endian on the wire (host byte order on both ARM and Apple Silicon).
- One atomic write per control tick — throttle command and measured velocity describe the same instant, which matters for the latched-speed rule.
- Existing 1.5 s stale-command watchdog also covers stale velocity (no separate staleness path).
- This is a breaking wire-format change; firmware and iOS must ship together. MCP is pre-1.0, so no compatibility shim is required.

### 3.2 Direction Inference (When the Supervisor Arms)

The reverse supervisor arms when **either**:

- `velocity_mm_per_s < -v_eps_mm_s` (actively moving backward, e.g. `v_eps = 50 mm/s`), **OR**
- `throttle_us < PWM_NEUTRAL_US - throttle_eps` (operator commanding reverse).

Rationale: fail-open on reverse safety is a collision. The union covers both coast-backward (e.g. rolling off a slope with neutral throttle) and explicit reverse commands. Transient false arming during a forward-to-reverse transition is acceptable — it briefly forces neutral throttle at near-zero speed, which is harmless.

When neither condition holds, the supervisor stays disarmed and passes the iOS throttle command through unchanged.

### 3.3 Supervisor Math

Mirror the iOS critical-distance formula. Physics is identical in reverse (same drivetrain, same linear-drag deceleration model); only geometry and latency constants differ.

```
criticalDistance(v) = |v| · tSysFW  +  stoppingDistance(|v|)  +  dMarginRear

stoppingDistance(v) = v/k − (a₀/k²) · ln(1 + k·v/a₀)      (exact integral, iOS DESIGN.md §4)
```

Constants:

| Constant        | Value                          | Source |
|-----------------|--------------------------------|--------|
| `decelIntercept` (a₀) | 0.66 m/s²                | Reused from iOS — same motor and friction. |
| `decelSlope` (k)      | 0.87 1/s                 | Reused from iOS — same back-EMF. |
| `tSysFW`              | 0.34 s (default) | Reaction latency on the reverse path. See §3.9 for decomposition and feedback-loop tuning. |
| `dMarginRear`         | 0.17 m (default) | 0.10 m sensor-to-rear-bumper offset + 0.07 m clearance. Matches the structure of iOS `dMarginM` (0.13 + 0.07 = 0.20 m). |

State machine and release rules mirror iOS (`DESIGN.md` §5) with three adjustments:

1. **Latch the magnitude of reverse speed.** On trigger, `latchedSpeed = |velocity|`. Critical distance while BRAKE uses this latched magnitude.
2. **Symmetric operator-release rule.** Firmware drops the rear latch when the iOS throttle command goes forward (`throttle_us > PWM_NEUTRAL_US + throttle_eps`). Mirrors the iOS rule that drops the forward latch when the operator commands reverse.
3. **No stop snapshot on the MCU.** The empirical-deceleration feedback loop (iOS DESIGN.md §7) stays on iOS where pose data exists. The MCU reports the trigger snapshot to iOS over the safety protocol (§3.6); iOS correlates with its pose history to compute `actualDecelMPS2` for reverse brake events, same as for forward.

Smoothing: single exponential moving average on the center-zone depth with one `alpha` (default `0.5`), same shape as iOS. No per-direction asymmetry.

### 3.4 Invalid / Stale Measurement Policy

Three distinct staleness sources, three distinct rules.

**(A) ToF center-zone reports non-OK status this frame.** Hold the last valid smoothed depth and increment an invalid-frame counter. After **2 consecutive invalid frames** (≈540 ms at 4 Hz), fail-safe to BRAKE while armed. A single dropout is tolerated — bench data shows occasional one-frame `PHA`/`SIG` transients even with a clean target. Two in a row means the sensor is genuinely blind.

**(B) Frame-gap watchdog (driver hang, I²C fault).** If `TofL1_GetLatestFrame().seq` has not advanced for **> 500 ms** (≈2× nominal scan period) while the supervisor is armed, force BRAKE. Recovers automatically when frames resume. If `TofL1_ERR_DRIVER_DEAD` is also raised by the driver, BRAKE remains latched; recovery requires reboot.

**(C) Stale iOS velocity.** The existing 1.5 s BLE command watchdog already forces PWM to neutral on timeout. The supervisor requires no extra logic for this case — without a fresh command there is no throttle to override, and the supervisor stays disarmed (no basis for direction inference). When the watchdog recovers with a new command, the supervisor uses the fresh velocity on the next tick.

### 3.5 Actuator Arbitration

Three sources can influence the final PWM throttle; steering is always the iOS value.

| Source | Effect |
|--------|--------|
| S1 — iOS command (0xFE41)          | Sets throttle target each tick. |
| S2 — BLE command watchdog (1.5 s)  | On timeout, forces throttle to `PWM_NEUTRAL_US`. Unchanged from current firmware. |
| S3 — Reverse safety supervisor     | Per-direction clamp while BRAKE. |

Arbitration rule (evaluated in order each tick, last writer wins on PWM):

1. Start with `throttle_us = iOS_throttle_us` (clamped to `[PWM_MIN_US, PWM_MAX_US]`).
2. **If S3 is BRAKE**, apply the reverse clamp: `throttle_us = max(throttle_us, PWM_NEUTRAL_US)`. This zeroes any reverse command while letting forward commands pass through. Forward passthrough is the operator escape hatch and feeds the symmetric release rule in §3.3.
3. **If S2 has tripped**, override with `throttle_us = PWM_NEUTRAL_US`. S2 beats everything.

Semantically: S3 is a per-direction mask (affects reverse only); S2 is a full override (affects any direction). Matches the iOS forward supervisor's "neutral, not reverse" invariant — same clamp shape, opposite direction.

### 3.6 MCU → iOS Safety Protocol

A new characteristic **0xFE43 "safety"** is added to the existing control service 0xFE40, alongside the command (0xFE41) and status (0xFE42) characteristics. 0xFE42 remains reserved for generic firmware heartbeat/telemetry (battery, uptime, build id) to be defined later; safety gets its own lifetime semantics.

Characteristic properties: `NOTIFY | READ`, fixed 18 B payload.

```c
typedef struct __attribute__((packed)) {
  uint32_t seq;                   // monotonic; increments on every state change
  uint32_t timestamp_ms;          // HAL_GetTick() at event
  uint8_t  state;                 // 0 = SAFE, 1 = BRAKE
  uint8_t  cause;                 // 0 = none, 1 = obstacle, 2 = tof_blind,
                                  // 3 = frame_gap, 4 = driver_dead
  uint8_t  _pad[2];               // must be 0
  int16_t  trigger_velocity_mm_s; // velocity at BRAKE entry; 0 while SAFE
  uint16_t trigger_depth_mm;      // smoothed center-zone depth at BRAKE entry; 0 while SAFE
  uint16_t critical_distance_mm;  // criticalDistance(|v_latched|) at trigger; 0 while SAFE
  uint16_t latched_speed_mm_s;    // |velocity| latched at trigger; 0 while SAFE
} BLE_SafetyEventPayload_t;

_Static_assert(sizeof(BLE_SafetyEventPayload_t) == 18, "...");
```

Cause codes:

| Code | Name          | Meaning                                                          |
|------|---------------|------------------------------------------------------------------|
| 0    | none          | State is SAFE. Snapshot fields are 0.                            |
| 1    | obstacle      | `smoothedDepth ≤ criticalDistance(latchedSpeed)` — real obstacle.|
| 2    | tof_blind     | 2 consecutive invalid center-zone status frames (§3.4 A).        |
| 3    | frame_gap     | No new `seq` for > 500 ms (§3.4 B).                              |
| 4    | driver_dead   | `TofL1_ERR_DRIVER_DEAD` — latched until reboot (§3.4 B).         |

Emission policy:
- Notify on every state transition (SAFE→BRAKE and BRAKE→SAFE). `seq` increments on each transition.
- While BRAKE, re-notify every 1 s as a liveness refresh (iOS may subscribe after the MCU is already in BRAKE; the periodic push guarantees iOS observes the state within one refresh window).
- iOS dedupes by `seq`. Any gap indicates a missed notification; iOS can trigger a read of 0xFE43 to recover.

iOS integration (out of scope for this doc but sketched for completeness):
- New `FirmwareSafetyEvent` model in the BLE layer.
- Plumbed into `PlannerContext` (or a peer channel) so the HUD shows a rear emergency card symmetric to the forward `SafetyBrakeRecord` card.
- Trigger snapshot fields map 1:1 to the iOS `SafetyBrakeTrigger` shape — UI code largely reuses.

### 3.7 Operating Modes and Sensor Config Ownership

A global MCU operating mode governs sensor configurability, ToF frame streaming, and whether the reverse supervisor is armed.

| Mode  | 0xFE61 config writes | 0xFE62 frame notify | Reverse supervisor | Default on boot |
|-------|----------------------|---------------------|--------------------|-----------------|
| Drive | Rejected with a new status error `TOF_L1_ERR_LOCKED_IN_DRIVE` (added to `TofL1_Status_t`). Firmware enforces the safety config `layout=3, dist_mode=LONG, budget=30 ms`. | Suppressed (BLE_Tof_Process early-returns). | Active. | Yes. |
| Debug | Accepted. iOS may reconfigure the ToF freely (any layout/mode/budget permitted by `TofL1_Configure`). | Streamed (existing chunking path re-enabled). | Disabled (passthrough; supervisor is not armed because config may not match safety assumptions). | No. |

Mode selection — new characteristic **0xFE44 "mode"** in service 0xFE40:

- Properties: `WRITE | WRITE_WITHOUT_RESP | READ`, fixed 1 B payload.
- Values: `0x00 = DRIVE`, `0x01 = DEBUG`. All other values rejected.
- On connect / boot: `DRIVE`.
- On BLE disconnect: MCU forces mode back to `DRIVE` (safest default; debug is for tethered bring-up only).
- On `DEBUG → DRIVE` transition: MCU re-applies the safety ToF config and clears any supervisor transient state.
- On `DRIVE → DEBUG` transition: MCU disarms the supervisor and stops suppressing 0xFE62 notifications.

Operator contract: the reverse supervisor is only trusted in `DRIVE`. Reversing while in `DEBUG` is the operator's responsibility.

### 3.8 Required Tests

Unit / host tests (compile for host, no STM32):

1. `criticalDistance(v)` returns iOS-matching values on the worked table (§3.3 constants). Parity test with a Swift fixture.
2. Center-zone invalid-frame counter: 1 invalid frame tolerated, 2 consecutive → BRAKE with cause `tof_blind`.
3. Frame-gap watchdog: no `seq` advance for 500 ms → BRAKE with cause `frame_gap`; resumes to SAFE after next valid frame if depth > critical.
4. Direction inference truth table (velocity sign × throttle sign vs armed).
5. Symmetric release: BRAKE with latched reverse speed → iOS commands forward → latch drops, SAFE.
6. Actuator arbitration matrix (§3.5 table, all rows).
7. Mode transitions: `DRIVE ↔ DEBUG`; BLE disconnect forces `DRIVE`; safety config re-applied on `DEBUG → DRIVE`.

On-target / HIL tests (STM32 flashed, BlueNRG-MS active):

8. Drive mode rejects 0xFE61 writes; 0xFE62 notifications not observed by iOS.
9. Debug mode accepts 0xFE61 writes; iOS observes 0xFE62 frames at configured rate.
10. Reverse into a static wall at 0.5 m/s, 1.0 m/s, 1.5 m/s → BRAKE cause `obstacle`; measured stop distance vs `criticalDistance` prediction within tolerance.
11. Cover the ToF lens with a hand during reverse → BRAKE cause `tof_blind` within 2 scan periods.
12. Disconnect BLE while reversing → PWM neutral (S2 watchdog); reconnect → supervisor state recoverable.

### 3.9 Sensor Latency and Reverse Speed Cap

`tSysFW` folds the dominant latencies on the reverse control path:

| Component                      | Contribution | Notes |
|--------------------------------|--------------|-------|
| ToF scan period (3×3 LONG 30 ms) | ~270 ms    | One full sensor age worst case. |
| EMA smoothing                  | ~0 ms added  | Treated as a bias on top of the sample age, not an independent latency. |
| BLE command cadence (iOS → MCU) | ~50 ms      | iOS sends 0xFE41 writes at ~20 Hz. |
| PWM + ESC reaction             | ~20 ms       | Throttle-to-wheel-torque response. |
| Main-loop tick                 | <5 ms        | Ignored. |

**Seed value:** `tSysFW = 0.34 s` in config.

**Feedback loop:** MCU emits the trigger snapshot over 0xFE43. iOS correlates with its own pose history to compute actual reverse stopping distance, same shape as the forward loop in iOS DESIGN.md §7. If measured reverse stopping distance is consistently greater than `criticalDistance(|v_latched|) − dMarginRear`, increase `tSysFW` (or adjust `decelIntercept` / `decelSlope` if the deviation is speed-dependent).

**Reverse speed cap.** The iOS throttle mapping limits commanded reverse velocity to `|v| ≤ 1.5 m/s`. At this cap, `criticalDistance(1.5) ≈ 0.34·1.5 + stopping(1.5) + 0.17 = 0.51 + 0.686 + 0.17 ≈ 1.37 m`, comfortably inside the 2.3 m valid ToF range. Higher reverse speeds are refused upstream so the supervisor never sees a velocity whose critical distance exceeds sensor range.

Tabulated critical distances for reverse with `tSysFW = 0.34 s`, `dMarginRear = 0.17 m`:

| |v|      | a(v)   | Reaction  | Stopping  | Margin  | **criticalDistance** |
|----------|--------|-----------|-----------|---------|----------------------|
| 0.3 m/s  | 0.92   | 0.102 m   | 0.043 m   | 0.17 m  | **0.32 m**           |
| 0.5 m/s  | 1.10   | 0.170 m   | 0.110 m   | 0.17 m  | **0.45 m**           |
| 1.0 m/s  | 1.53   | 0.340 m   | 0.363 m   | 0.17 m  | **0.87 m**           |
| 1.5 m/s  | 1.97   | 0.510 m   | 0.686 m   | 0.17 m  | **1.37 m**           |

---

## 4. Summary of Protocol Surface

Service **0xFE40** (existing "OpenOtter Control"):

| UUID   | Properties              | Size  | Dir        | Purpose                                            |
|--------|-------------------------|-------|------------|----------------------------------------------------|
| 0xFE41 | write, write-w/o-resp   | 6 B   | iOS → MCU  | steering_us, throttle_us, velocity_mm_per_s        |
| 0xFE42 | notify, read            | TBD   | MCU → iOS  | reserved (future generic heartbeat/telemetry)      |
| 0xFE43 | notify, read            | 18 B  | MCU → iOS  | safety state + trigger snapshot (see §3.6)         |
| 0xFE44 | write, write-w/o-resp, read | 1 B | iOS → MCU | operating mode: 0 = Drive, 1 = Debug              |

Service **0xFE60** (existing "OpenOtter ToF"):

| UUID   | Behavior in Drive mode                         | Behavior in Debug mode |
|--------|------------------------------------------------|------------------------|
| 0xFE61 | Config writes rejected; safety config enforced | Config writes accepted |
| 0xFE62 | Frame notifications suppressed                 | Frame notifications streamed (existing chunking path) |
| 0xFE63 | Status notifications as today                  | Status notifications as today |

## 5. Configuration Struct (Firmware)

```c
typedef struct {
  float t_sys_fw_s;          // reaction latency; default 0.34
  float decel_intercept;     // a0, m/s^2; default 0.66 (iOS parity)
  float decel_slope;         // k, 1/s;    default 0.87 (iOS parity)
  float d_margin_rear_m;     // 0.17 (0.10 sensor-to-bumper + 0.07 clearance)
  float alpha_smoothing;     // 0.5
  float release_hold_s;      // 0.3 (iOS parity)
  float v_eps_mm_s;          // 50 — disarm threshold
  int16_t throttle_eps_us;   // 30 — throttle deadband around PWM_NEUTRAL_US
  float stop_speed_eps_mps;  // 0.05
  uint32_t tof_blind_frames; // 2 — consecutive invalid frames before BRAKE
  uint32_t frame_gap_ms;     // 500 — frame-seq gap before BRAKE
} RevSafetySupervisorConfig_t;
```

## 6. Out of Scope

- Forward-direction safety on the MCU (stays on iOS, no change).
- iOS-side UI design of the rear emergency card (parallel to forward; implementation-plan level).
- Multi-zone fusion (other 8 zones of the 3×3). Supervisor uses center-zone only; future widen-cone work is upstream.
- Battery, IMU, odometry telemetry (planned for 0xFE42).
