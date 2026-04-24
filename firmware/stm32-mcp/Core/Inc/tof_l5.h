/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_L5_H
#define TOF_L5_H

#include <stdint.h>

#include "tof_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_L5_DEFAULT_I2C_ADDR_8BIT 0x52u
#define TOF_L5_MAX_FREQ_4X4_HZ       60u
#define TOF_L5_MAX_FREQ_8X8_HZ       15u

int TofL5_ValidateConfig(const Tof_Config_t *cfg);

int TofL5_Init(void);
int TofL5_Configure(const Tof_Config_t *cfg);
void TofL5_Process(void);

const Tof_Frame_t *TofL5_GetLatestFrame(void);
int  TofL5_HasNewFrame(void);
void TofL5_ClearNewFrame(void);
int  TofL5_IsDriverDead(void);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L5_H */
