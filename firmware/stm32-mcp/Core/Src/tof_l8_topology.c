/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_topology.h"

static const TofL8SlotTopology_t kRear = {
    .sensor_id = TOF_L8_SENSOR_REAR,
    .bus_id = TOF_L8_BUS_I2C3,
    .boot_addr_8bit = TOF_L8_DEFAULT_I2C_ADDR_8BIT,
    .run_addr_8bit = TOF_L8_DEFAULT_I2C_ADDR_8BIT,
    .lpn = TOF_L8_GPIO_PC4_A1,
    .gpio1 = TOF_L8_GPIO_PC3_A2,
    .pwr_en = TOF_L8_GPIO_PA15_D9,
};

static const TofL8SlotTopology_t kFront = {
    .sensor_id = TOF_L8_SENSOR_FRONT,
    .bus_id = TOF_L8_BUS_I2C1,
    .boot_addr_8bit = TOF_L8_DEFAULT_I2C_ADDR_8BIT,
    .run_addr_8bit = TOF_L8_DEFAULT_I2C_ADDR_8BIT,
    .lpn = TOF_L8_GPIO_PC5_A0,
    .gpio1 = TOF_L8_GPIO_PC2_A3,
    .pwr_en = TOF_L8_GPIO_PA2_D10,
};

const TofL8SlotTopology_t *TofL8_TopologyDefaultRear(void)
{
  return &kRear;
}

const TofL8SlotTopology_t *TofL8_TopologyDefaultFront(void)
{
  return &kFront;
}

int TofL8_TopologyValidatePair(const TofL8SlotTopology_t *a,
                               const TofL8SlotTopology_t *b)
{
  if (a == 0 || b == 0) return TOF_L8_TOPOLOGY_ERR_NULL;

  if (a->sensor_id == b->sensor_id) {
    return TOF_L8_TOPOLOGY_ERR_DUPLICATE_ROLE;
  }

  if (a->lpn == TOF_L8_GPIO_NONE || b->lpn == TOF_L8_GPIO_NONE) {
    return TOF_L8_TOPOLOGY_ERR_MISSING_LPN;
  }
  if (a->lpn == b->lpn) return TOF_L8_TOPOLOGY_ERR_SHARED_LPN;

  if (a->gpio1 != TOF_L8_GPIO_NONE && a->gpio1 == b->gpio1) {
    return TOF_L8_TOPOLOGY_ERR_SHARED_GPIO1;
  }

  if (a->bus_id == b->bus_id && a->run_addr_8bit == b->run_addr_8bit) {
    return TOF_L8_TOPOLOGY_ERR_SAME_BUS_DUP_ADDR;
  }

  return TOF_L8_TOPOLOGY_OK;
}
