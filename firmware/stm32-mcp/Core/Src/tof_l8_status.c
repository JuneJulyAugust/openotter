/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_status.h"

/*
 * VL53L8CX target_status codes documented as valid ranges:
 *   5  range valid
 *   6  wrap-around not performed
 *   9  range valid with large pulse
 *   10 range valid, no previous target
 */
int TofL8_StatusIsRangeValid(uint8_t status)
{
  return status == 5u || status == 6u || status == 9u || status == 10u;
}
