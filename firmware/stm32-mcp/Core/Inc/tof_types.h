/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_TYPES_H
#define TOF_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_MAX_ZONES 64u

typedef enum {
  TOF_SENSOR_NONE     = 0,
  TOF_SENSOR_VL53L1CB = 1,
  TOF_SENSOR_VL53L5CX = 2,
} Tof_SensorType_t;

typedef enum {
  TOF_PROFILE_L5_CONTINUOUS = 1,
} Tof_Profile_t;

typedef struct __attribute__((packed)) {
  uint16_t range_mm;
  uint8_t  status;
  uint8_t  flags;
} Tof_Zone_t;

typedef struct {
  uint8_t    sensor_type;
  uint8_t    layout;
  uint8_t    zone_count;
  uint8_t    profile;
  uint32_t   seq;
  uint32_t   tick_ms;
  Tof_Zone_t zones[TOF_MAX_ZONES];
} Tof_Frame_t;

typedef struct __attribute__((packed)) {
  uint8_t  sensor_type;
  uint8_t  layout;
  uint8_t  profile;
  uint8_t  frequency_hz;
  uint16_t integration_ms;
  uint16_t budget_ms;
} Tof_Config_t;

typedef enum {
  TOF_STATUS_OK              = 0,
  TOF_STATUS_NO_SENSOR       = 1,
  TOF_STATUS_BOOT_FAILED     = 2,
  TOF_STATUS_IO              = 3,
  TOF_STATUS_BAD_CONFIG      = 4,
  TOF_STATUS_DRIVER_MISSING  = 5,
  TOF_STATUS_DRIVER_DEAD     = 6,
  TOF_STATUS_LOCKED_IN_DRIVE = 11,
} Tof_Status_t;

#ifdef __cplusplus
}
#endif

#endif /* TOF_TYPES_H */
