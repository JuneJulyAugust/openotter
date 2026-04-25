/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * firmware_watchdog — IWDG (Independent Watchdog) wrapper.
 *
 * The IWDG runs from the always-on LSI clock and resets the chip if not
 * refreshed within its window. This is the last line of defense against
 * a stuck main loop: even if every other safety mechanism fails (BLE
 * stack hung, I²C blocked, ToF driver spinning), the IWDG fires within
 * the configured timeout and reboots into a clean state.
 *
 * Timeout sizing: ~2 seconds gives enough slack for the slowest documented
 * blocking operation (VL53L5CX firmware download — bounded to 15 s of
 * I²C work but happens during cold boot before the loop is ticking, so
 * not a refresh concern). Normal main-loop iterations are sub-millisecond.
 *
 * Refresh policy: refresh once per main-loop iteration. If the loop stops
 * iterating, the IWDG resets.
 *
 * Tests cover the timeout calculation (pure function); the HAL plumbing is
 * exercised by the firmware build.
 */

#ifndef FIRMWARE_WATCHDOG_H
#define FIRMWARE_WATCHDOG_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* LSI nominal frequency on STM32L4 = 32 kHz. */
#define FW_WATCHDOG_LSI_HZ          32000u

/* Default timeout. 2 s is comfortably above any normal loop iteration
 * (< 1 ms) and well below any operator-perceptible "vehicle is stuck". */
#define FW_WATCHDOG_DEFAULT_TIMEOUT_MS  2000u

/*
 * Pure helper: compute the IWDG reload value for a given timeout in
 * milliseconds and prescaler divider. Clamps to the IWDG hardware limits
 * (12-bit reload, 0..4095).
 *
 * Returns 0 if the requested timeout is unrepresentable (e.g. divider == 0
 * or timeout exceeds what the prescaler can reach with the maximum reload).
 *
 * Host-testable; no HAL dependency.
 */
uint16_t FwWatchdog_ComputeReload(uint32_t timeout_ms,
                                  uint32_t lsi_hz,
                                  uint16_t prescaler_div);

/*
 * Pick the smallest IWDG prescaler index that can represent the requested
 * timeout. Returns one of {4, 8, 16, 32, 64, 128, 256} (the supported
 * dividers); returns 0 if no prescaler is large enough.
 *
 * Host-testable.
 */
uint16_t FwWatchdog_PickPrescaler(uint32_t timeout_ms, uint32_t lsi_hz);

#ifndef HOST_TEST
/*
 * Initialize and start the IWDG with FW_WATCHDOG_DEFAULT_TIMEOUT_MS.
 * Must be called once near the start of main(), AFTER the HAL is ready
 * and BEFORE the main loop. Once started the IWDG cannot be disabled.
 */
void FwWatchdog_Init(void);

/*
 * Refresh the IWDG counter. Call once per main-loop iteration.
 */
void FwWatchdog_Refresh(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* FIRMWARE_WATCHDOG_H */
