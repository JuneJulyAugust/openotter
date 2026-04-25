# Reverse Safety Supervisor — Bringup Checklist

Follow after flashing firmware ≥ v1.0.0 and pairing with an iOS build that
speaks the 6 B command and 0xFE43/0xFE44 protocol. All checks run with the
vehicle on blocks (wheels off the ground) except items that explicitly say
otherwise.

1. **Default mode on connect.** After BLE connect, read 0xFE44. Expect Park
   from the iOS app during idle, then Drive after a movement command.

2. **Drive rejects ToF config writes.** Write an arbitrary valid config
   (e.g. layout=1, dist_mode=2, budget=50000) to 0xFE61. Read 0xFE63.
   Expect `last_error = 11` (`TOF_L1_ERR_LOCKED_IN_DRIVE`).

3. **Drive suppresses ToF frames.** Subscribe to 0xFE62. Expect zero
   notifications during a 10 s observation.

4. **Switch to Debug.** Write `0x01` to 0xFE44. Write a legal config to
   0xFE61 (e.g. 3x3 LONG 30 ms). Expect 0xFE62 notifications to start and
   arrive at ≈4 Hz.

5. **Switch back to Drive.** Write `0x00` to 0xFE44. 0xFE62 must stop
   within 1 s. Read 0xFE63; `state = 1` and `last_error = 0`.

6. **Reverse-into-wall (vehicle on the floor, spotter present).** Command
   throttle 1350 µs (mild reverse) with the rear aimed at a wall 1 m away.
   Expect:
   - BRAKE notification on 0xFE43 with `state=1`, `cause=1` (obstacle)
     within one 270 ms scan.
   - Throttle is clamped to 1500 µs (neutral) within the same main-loop
     tick.
   - Driving forward (throttle > 1530 µs) clears the BRAKE — 0xFE43
     notifies `state=0`.

7. **Cover the lens.** While reversing at 1350 µs with 2 m clear, block the
   ToF lens with a hand. Expect BRAKE with `cause=2` (tof_blind) within 2
   scan periods (≈540 ms). Uncover; expect release after 0.3 s of continuous
   clearance.

8. **Park clears emergency state.** Trigger reverse BRAKE, then send Park from
   Telegram or the app. Expect 0xFE43 to clear and the Self Driving emergency
   panel to dismiss without another BRAKE while speed is zero.

9. **BLE watchdog.** Disconnect the iPhone while reversing. PWM must go to
   neutral within `BLE_SAFETY_TIMEOUT_MS` (1.5 s). Reconnect; supervisor
   should resume from SAFE.

---

## Known Bug History

### False `TOF_BLIND` brake with no obstacle (fixed in stm32-mcp-v1.1.0)

**Symptom:** "Rear Emergency Brake — Sensor blind" fires during normal reverse
with no obstacle present. The UART log shows L5 frames arriving (LED2 toggling)
but the supervisor declares blind after a few frames.

**Cause:** `rev_safety_l5.c` was copy-pasted from the VL53L1 path and used the
VL53L1 valid-status whitelist `{0, 3, 6, 11}`. VL53L5CX `target_status` uses
different code semantics: status 5 = range valid (the common healthy case), but
it was rejected as invalid. After four such frames `REV_SAFETY_CAUSE_TOF_BLIND`
latched.

**Fix:** Whitelist updated to `{5, 6, 9, 10}` per ST UM2884 §5.5.6. Host
regression tests added. See `09-ble-gatt-slot-bug-postmortem.md` §Secondary Bug.
