/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * pwm_control — RC servo / ESC pulse-width logic.
 *
 * Pure (HAL-free). Owns the canonical PWM pulse-width range so command
 * arbitration can reason about safe pulse values without reaching into the
 * BLE layer or the timer driver.
 *
 * The hardware adapter (writing CCR registers on TIM3) lives separately in
 * ble_app.c so this module stays host-testable.
 */

#ifndef PWM_CONTROL_H
#define PWM_CONTROL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* TIM3 config: PSC=79, ARR=19999 → 1 tick = 1µs, period = 20 ms (50 Hz). */
#define PWM_PERIOD_US  20000
#define PWM_NEUTRAL_US 1500    /* center / coast */
#define PWM_MIN_US     1000    /* full reverse / left */
#define PWM_MAX_US     2000    /* full forward / right */

/*
 * Clamp a requested pulse width into the safe [PWM_MIN_US, PWM_MAX_US] range.
 *
 * Pure, total. Out-of-range inputs (including negative or above 2000) are
 * clipped to the corresponding bound — never returned through.
 */
int16_t PwmControl_ClampPulse(int16_t pulse_us);

#ifdef __cplusplus
}
#endif

#endif /* PWM_CONTROL_H */
