/* SPDX-License-Identifier: BSD-3-Clause */
#include "pwm_control.h"

int16_t PwmControl_ClampPulse(int16_t pulse_us) {
  if (pulse_us < PWM_MIN_US) return PWM_MIN_US;
  if (pulse_us > PWM_MAX_US) return PWM_MAX_US;
  return pulse_us;
}

int16_t PwmControl_SlewToward(int16_t current_us,
                              int16_t target_us,
                              uint16_t max_step_us) {
  int16_t current = PwmControl_ClampPulse(current_us);
  int16_t target = PwmControl_ClampPulse(target_us);

  if (max_step_us == 0u || current == target) return current;

  int32_t delta = (int32_t)target - (int32_t)current;
  int32_t step = (int32_t)max_step_us;
  if (delta > step) return (int16_t)(current + step);
  if (delta < -step) return (int16_t)(current - step);
  return target;
}

int16_t PwmControl_TimedSlewToward(int16_t current_us,
                                   int16_t target_us,
                                   uint32_t elapsed_ms,
                                   uint16_t us_per_ms,
                                   uint16_t max_elapsed_ms) {
  if (elapsed_ms == 0u || us_per_ms == 0u || max_elapsed_ms == 0u) {
    return PwmControl_ClampPulse(current_us);
  }

  uint32_t capped_elapsed = elapsed_ms;
  if (capped_elapsed > (uint32_t)max_elapsed_ms) {
    capped_elapsed = (uint32_t)max_elapsed_ms;
  }

  uint32_t max_step = capped_elapsed * (uint32_t)us_per_ms;
  if (max_step > UINT16_MAX) {
    max_step = UINT16_MAX;
  }

  return PwmControl_SlewToward(current_us, target_us, (uint16_t)max_step);
}
