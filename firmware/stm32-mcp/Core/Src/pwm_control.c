/* SPDX-License-Identifier: BSD-3-Clause */
#include "pwm_control.h"

int16_t PwmControl_ClampPulse(int16_t pulse_us) {
  if (pulse_us < PWM_MIN_US) return PWM_MIN_US;
  if (pulse_us > PWM_MAX_US) return PWM_MAX_US;
  return pulse_us;
}
