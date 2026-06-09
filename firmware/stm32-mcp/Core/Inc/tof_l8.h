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
  TOF_L8_SENSOR_COUNT = 2,
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

const Tof_Frame_t *TofL8_GetLatestFrameForSensor(TofL8SensorId_t sensor_id);
int  TofL8_HasNewFrameForSensor(TofL8SensorId_t sensor_id);
void TofL8_ClearNewFrameForSensor(TofL8SensorId_t sensor_id);
int  TofL8_IsSensorAvailable(TofL8SensorId_t sensor_id);
int  TofL8_IsDriverDeadForSensor(TofL8SensorId_t sensor_id);
uint8_t TofL8_AvailableMask(void);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L8_H */
