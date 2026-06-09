/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef REV_SAFETY_L8_H
#define REV_SAFETY_L8_H

#include "rev_safety_tof.h"
#include "tof_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define REV_SAFETY_L8_LAYOUT 4u
#define REV_SAFETY_L8_ZONE_ROW3_COL2 9u
#define REV_SAFETY_L8_ZONE_ROW3_COL3 10u
#define REV_SAFETY_L8_TRUSTED_MAX_MM 3800u
#define REV_SAFETY_L8_CLEAR_DEPTH_M 3.8f

RevSafetyTofReading_t RevSafetyL8_SelectReverseReading(const Tof_Frame_t *frame);
RevSafetyTofReading_t RevSafetyL8_SelectFrontReading(const Tof_Frame_t *frame);

#ifdef __cplusplus
}
#endif

#endif /* REV_SAFETY_L8_H */
