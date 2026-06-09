/* SPDX-License-Identifier: BSD-3-Clause */
#include "drive_safety.h"

#include <string.h>

static int16_t mirror_throttle(int16_t throttle_us, uint16_t neutral_us)
{
  int32_t mirrored = (int32_t)neutral_us * 2 - (int32_t)throttle_us;
  if (mirrored > INT16_MAX) return INT16_MAX;
  if (mirrored < INT16_MIN) return INT16_MIN;
  return (int16_t)mirrored;
}

void DriveSafety_ProjectInput(DriveSafetyDirection_t direction,
                              uint16_t neutral_us,
                              const RevSafetyInput_t *physical,
                              RevSafetyInput_t *projected)
{
  if (!projected) return;
  if (!physical) {
    memset(projected, 0, sizeof(*projected));
    return;
  }

  *projected = *physical;
  if (direction == DRIVE_SAFETY_DIRECTION_FRONT) {
    projected->velocity_mps = -physical->velocity_mps;
    projected->throttle_us = mirror_throttle(physical->throttle_us,
                                             neutral_us);
  }
}

void DriveSafety_ProjectEvent(DriveSafetyDirection_t direction,
                              const RevSafetyEvent_t *projected,
                              RevSafetyEvent_t *physical)
{
  if (!physical) return;
  if (!projected) {
    memset(physical, 0, sizeof(*physical));
    return;
  }

  *physical = *projected;
  if (direction == DRIVE_SAFETY_DIRECTION_FRONT) {
    physical->trigger_velocity_mps = -projected->trigger_velocity_mps;
  }
}

int DriveSafety_ThrottleBlocked(DriveSafetyDirection_t direction,
                                int16_t throttle_us,
                                uint16_t neutral_us)
{
  if (direction == DRIVE_SAFETY_DIRECTION_FRONT) {
    return throttle_us > (int16_t)neutral_us;
  }
  return throttle_us < (int16_t)neutral_us;
}
