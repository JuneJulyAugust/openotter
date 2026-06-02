/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_L8_H
#define TOF_L8_H

#include <stdint.h>

#include "tof_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_L8_DEFAULT_I2C_ADDR_8BIT 0x52u
#define TOF_L8_MAX_FREQ_4X4_HZ       60u
#define TOF_L8_MAX_FREQ_8X8_HZ       15u

typedef enum {
  TOF_L8_SENSOR_REAR = 0,
  TOF_L8_SENSOR_FRONT = 1,
} TofL8SensorId_t;

int TofL8_ValidateConfig(const Tof_Config_t *cfg);

int TofL8_Init(void);
int TofL8_EnsureInitialized(void);
int TofL8_Configure(const Tof_Config_t *cfg);
void TofL8_Process(void);

const Tof_Frame_t *TofL8_GetLatestFrame(void);
int  TofL8_HasNewFrame(void);
void TofL8_ClearNewFrame(void);
int  TofL8_IsInitialized(void);
int  TofL8_IsDriverDead(void);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L8_H */
