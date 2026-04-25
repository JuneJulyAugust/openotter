/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * tof_l5_debounce — debounce predicate for VL53L5CX reconfiguration.
 *
 * The VL53L5CX I²C state machine can be corrupted by rapid stop/start cycles,
 * so external Configure() calls are throttled. This module owns the predicate
 * (pure, host-testable) so the rule is verifiable without HAL.
 *
 * Sentinel: a last_configure_tick of 0 means "no prior configure". TofL5_Init
 * MUST clear last_configure_tick to 0 after its own internal Configure call,
 * otherwise the first external Configure (e.g. BLE_Tof_EnforceSafetyConfig
 * raising the sensor from 10 Hz init default to 30 Hz safety mode) is silently
 * dropped within the debounce window.
 */

#ifndef TOF_L5_DEBOUNCE_H
#define TOF_L5_DEBOUNCE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_L5_RECONFIGURE_DEBOUNCE_MS 500u

/*
 * Returns true if a Configure() call at time `now_ms` should be silently
 * dropped because a previous Configure happened too recently.
 *
 * Special case: last_configure_tick == 0 always returns false (no prior
 * configure exists, so no debounce applies). The init flow uses this to
 * release the debounce after its own internal Configure.
 */
bool TofL5Debounce_ShouldSkip(uint32_t now_ms,
                              uint32_t last_configure_tick,
                              uint32_t debounce_ms);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L5_DEBOUNCE_H */
