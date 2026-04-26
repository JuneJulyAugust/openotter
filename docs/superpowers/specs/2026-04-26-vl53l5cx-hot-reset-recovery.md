# VL53L5CX Hot-Reset Recovery

## Problem

After STM32 NRST while the iOS app is connected and the VL53L5CX is actively ranging, only LED1 (heartbeat) blinks on reboot — LED2 (L5 frame heartbeat on PB14) stays dark and no depth frames are produced. The reverse-safety supervisor therefore sits without sensor data even though the BLE link reconnects normally.

Cold power-on (STM32 + sensor power up together) recovers correctly. The failure is specific to STM32-side reset while sensor power is uninterrupted.

## Why Cold Boot Works But Hot Reset Doesn't

The init sequence is identical on both paths:

```
BLE_Tof_Init   → safety_config_pending=1, retry_tick=now+1000ms
BLE_Tof_Process @ t=1s → mode==DRIVE → BLE_Tof_EnforceSafetyConfig
                                       → TofL5_EnsureInitialized → TofL5_Init
                                          → pulse_reset (ARD_A1)
                                          → vl53l5cx_is_alive
                                          → vl53l5cx_init (~3s firmware download)
                                          → vl53l5cx_start_ranging
```

What differs is the sensor's pre-init state:

| Boot type | VL53L5CX state at TofL5_Init entry |
|-----------|------------------------------------|
| Cold      | unpowered → fresh, idle            |
| Hot reset | mid-ranging, host-loaded firmware running |

`pulse_reset()` (`tof_l5.c:140-147`) drives `ARD_A1` high → low. Per UM2884 §6, the `I2C_RST` pin resets only the **I²C interface state machine** — it does not stop the ranging engine, does not clear the host-loaded firmware in sensor RAM, and does not return the sensor to a fresh boot state.

After STM32 NRST while the sensor was streaming at 30 Hz, the sensor sits in continuous-ranging mode. `pulse_reset` clears any lingering bus stretch but ranging keeps going. `vl53l5cx_init` then attempts to re-download ~85 KB of firmware over I²C while the sensor is still actively running its previous firmware → register writes race against the ranging loop's own register accesses inside the sensor → typically `is_alive` succeeds (register 0 still readable) but `vl53l5cx_init` returns non-OK, or returns OK with a corrupted firmware state that causes `start_ranging` to fail silently.

Net result: `g_initialized` stays 0 (or 1 with `g_streaming=0`). No frames arrive, LED2 stays dark, the reverse-safety supervisor never receives a tof_class signal.

The retry path (`BLE_Tof_Process` re-runs every 3 s in DRIVE) hits the same wall on every retry — sensor is still ranging from before, init still races.

## Why It Isn't a BLE-Protocol Issue

iOS reconnect timing is not the trigger. BlueNRG-MS is reset by STM32 via PA8 on every boot, advertising restarts cleanly, and the iOS reconnect / mode-write traffic runs in parallel with — not on top of — L5 init. The only meaningful deltas at L5 init time between cold and hot boot live on the sensor side:

1. **Sensor power state**: cold boot just powered up; hot reset → untouched, still ranging.
2. **I²C bus state**: cold boot idle; hot reset possibly mid-clock-stretch.

Both deltas are sensor-local. The fix has to live in the sensor init path, not in BLE.

## Fix

Issue an opportunistic `vl53l5cx_stop_ranging` at the top of `TofL5_Init`, immediately after the platform layer is wired up but before `vl53l5cx_is_alive` and `vl53l5cx_init`:

```c
g_dev.platform.address = TOF_L5_DEFAULT_I2C_ADDR_8BIT;
g_dev.platform.Write   = l5_i2c_write;
g_dev.platform.Read    = l5_i2c_read;
g_dev.platform.GetTick = l5_get_tick;

/* ARD_A1 only resets the I2C state machine, not the ranging engine. After
 * an STM32 NRST while the sensor was streaming, ranging continues and the
 * next vl53l5cx_init firmware download races against active ranging
 * interrupts. Best-effort stop_ranging via the platform layer (only needs
 * g_dev.platform populated) so the firmware download lands on an idle
 * sensor. Cold boot returns an error here — that is fine, ignored. */
uint8_t pre_stop = vl53l5cx_stop_ranging(&g_dev);
HAL_Delay(5);

uint8_t alive = 0;
uint8_t s = vl53l5cx_is_alive(&g_dev, &alive);
```

`vl53l5cx_stop_ranging` (in `Drivers/VL53L5CX/modules/vl53l5cx_api.c`) only requires `g_dev.platform` to be populated; it issues raw I²C writes (registers `0x14`, `0x15`, `0x09`, `0x7fff`) to undo the MCU stop and bypass xshut. The function reads `is_auto_stop_enabled` from the device struct, which is `0` after `memset` — so the auto-stop poll branch is skipped on a fresh device. The bottom block of register writes runs unconditionally and is what we need.

On **cold boot**, the sensor isn't running any firmware, so several of those writes return I²C errors. The aggregated status byte is non-zero. We ignore it — the subsequent `vl53l5cx_is_alive` and `vl53l5cx_init` proceed normally on the fresh sensor.

On **hot reset**, the sensor is running its previous firmware. The same writes successfully push the ranging engine into a stopped state. The `HAL_Delay(5)` lets the sensor settle before we begin the firmware redownload. `vl53l5cx_init` then runs against an idle sensor and succeeds.

A diagnostic UART line (`VL53L5 pre-stop=N alive_rd=M alive=K`) is logged on every init so failure modes are visible from the serial console:

- `pre-stop=0` on hot reset = stop succeeded (sensor was running, now stopped).
- `pre-stop != 0` on cold boot = expected, sensor was never running.
- `alive=1` after = sensor responding to register reads → init can proceed.

## Invariant

The invariant restored by this fix is:

> When `vl53l5cx_init` runs, the sensor MUST NOT be in the middle of a ranging cycle. Either it has never been started (cold boot) or it has been explicitly stopped (hot reset).

`pulse_reset` alone does not maintain this invariant because `ARD_A1` is a pure I²C-interface reset, not a system reset. Only `vl53l5cx_stop_ranging` (or full power cycle via `LPn`/`PWREN`, which is not wired on this board) can.

## Files Touched

- `firmware/stm32-mcp/Core/Src/tof_l5.c` — added `vl53l5cx_stop_ranging` call + diagnostic log inside `TofL5_Init`.

No host-test changes: the affected path is the bare-metal init flow, which is HAL-bound and not reachable from `tests/host/`. Verification is on-target (UART log + LED2 observation after NRST while iOS is connected).

## Future Hardware Note

A wired `LPn` (or `PWREN`) line to a STM32 GPIO would let firmware perform a hard power-cycle of the sensor on STM32 boot, bypassing the need for any software stop sequence. For the current board (only `ARD_A1`/I2C_RST routed to STM32) the software stop is the correct fix.
