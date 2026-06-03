/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef DRIVE_SAFETY_H
#define DRIVE_SAFETY_H

#include <stdint.h>

#include "rev_safety.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  DRIVE_SAFETY_DIRECTION_REAR = 0,
  DRIVE_SAFETY_DIRECTION_FRONT = 1,
} DriveSafetyDirection_t;

void DriveSafety_ProjectInput(DriveSafetyDirection_t direction,
                              uint16_t neutral_us,
                              const RevSafetyInput_t *physical,
                              RevSafetyInput_t *projected);

void DriveSafety_ProjectEvent(DriveSafetyDirection_t direction,
                              const RevSafetyEvent_t *projected,
                              RevSafetyEvent_t *physical);

int DriveSafety_ThrottleBlocked(DriveSafetyDirection_t direction,
                                int16_t throttle_us,
                                uint16_t neutral_us);

#ifdef __cplusplus
}
#endif

#endif /* DRIVE_SAFETY_H */
