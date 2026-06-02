/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_L8_TOPOLOGY_H
#define TOF_L8_TOPOLOGY_H

#include <stdint.h>

#include "tof_l8.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_L8_TOPOLOGY_OK                    0
#define TOF_L8_TOPOLOGY_ERR_NULL              1
#define TOF_L8_TOPOLOGY_ERR_DUPLICATE_ROLE    2
#define TOF_L8_TOPOLOGY_ERR_MISSING_LPN       3
#define TOF_L8_TOPOLOGY_ERR_SHARED_LPN        4
#define TOF_L8_TOPOLOGY_ERR_SHARED_GPIO1      5
#define TOF_L8_TOPOLOGY_ERR_SAME_BUS_DUP_ADDR 6

typedef enum {
  TOF_L8_BUS_I2C1 = 1,
  TOF_L8_BUS_I2C3 = 3,
} TofL8BusId_t;

typedef enum {
  TOF_L8_GPIO_NONE = 0,
  TOF_L8_GPIO_PC2_A3,
  TOF_L8_GPIO_PC3_A2,
  TOF_L8_GPIO_PC4_A1,
  TOF_L8_GPIO_PC5_A0,
  TOF_L8_GPIO_PA15_D9,
  TOF_L8_GPIO_PA2_D10,
} TofL8GpioTag_t;

typedef struct {
  TofL8SensorId_t sensor_id;
  TofL8BusId_t bus_id;
  uint16_t boot_addr_8bit;
  uint16_t run_addr_8bit;
  TofL8GpioTag_t lpn;
  TofL8GpioTag_t gpio1;
  TofL8GpioTag_t pwr_en;
} TofL8SlotTopology_t;

const TofL8SlotTopology_t *TofL8_TopologyDefaultRear(void);
const TofL8SlotTopology_t *TofL8_TopologyDefaultFront(void);
int TofL8_TopologyValidatePair(const TofL8SlotTopology_t *a,
                               const TofL8SlotTopology_t *b);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L8_TOPOLOGY_H */
