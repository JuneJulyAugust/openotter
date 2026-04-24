/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef REV_SAFETY_TOF_H
#define REV_SAFETY_TOF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  REV_SAFETY_TOF_INVALID = 0,
  REV_SAFETY_TOF_CLEAR   = 1,
  REV_SAFETY_TOF_VALID   = 2,
} RevSafetyTofClass_t;

typedef struct {
  RevSafetyTofClass_t tof_class;
  float               depth_m;
} RevSafetyTofReading_t;

#define REV_SAFETY_TOF_CLEAR_DEPTH_M 3.0f

/* Classify a serialized center-zone reading from TofL1_Frame_t for the
 * reverse-safety supervisor:
 *   - range-valid statuses become VALID with their measured depth
 *   - zero-range "no target" statuses become CLEAR with a synthetic far depth
 *   - true sensor faults remain INVALID and feed the blind-frame counter
 */
RevSafetyTofReading_t RevSafety_ClassifyTofReading(uint16_t range_mm,
                                                   uint8_t status);

#ifdef __cplusplus
}
#endif

#endif /* REV_SAFETY_TOF_H */
