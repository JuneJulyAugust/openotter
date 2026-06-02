/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_topology.h"

#include <assert.h>

static void test_default_pair_uses_separate_buses_and_control_pins(void)
{
  const TofL8SlotTopology_t *rear = TofL8_TopologyDefaultRear();
  const TofL8SlotTopology_t *front = TofL8_TopologyDefaultFront();

  assert(rear != 0);
  assert(front != 0);
  assert(rear->sensor_id == TOF_L8_SENSOR_REAR);
  assert(front->sensor_id == TOF_L8_SENSOR_FRONT);
  assert(rear->bus_id == TOF_L8_BUS_I2C3);
  assert(front->bus_id == TOF_L8_BUS_I2C1);
  assert(rear->run_addr_8bit == TOF_L8_DEFAULT_I2C_ADDR_8BIT);
  assert(front->run_addr_8bit == TOF_L8_DEFAULT_I2C_ADDR_8BIT);
  assert(rear->lpn != front->lpn);
  assert(rear->gpio1 != front->gpio1);
  assert(rear->pwr_en != front->pwr_en);
  assert(TofL8_TopologyValidatePair(rear, front) == TOF_L8_TOPOLOGY_OK);
}

static void test_shared_bus_requires_unique_runtime_addresses(void)
{
  TofL8SlotTopology_t rear = *TofL8_TopologyDefaultRear();
  TofL8SlotTopology_t front = *TofL8_TopologyDefaultFront();

  front.bus_id = rear.bus_id;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_ERR_SAME_BUS_DUP_ADDR);

  front.run_addr_8bit = 0x54u;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_OK);
}

static void test_duplicate_roles_and_shared_control_pins_are_rejected(void)
{
  TofL8SlotTopology_t rear = *TofL8_TopologyDefaultRear();
  TofL8SlotTopology_t front = *TofL8_TopologyDefaultFront();

  front.sensor_id = rear.sensor_id;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_ERR_DUPLICATE_ROLE);

  front = *TofL8_TopologyDefaultFront();
  front.lpn = rear.lpn;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_ERR_SHARED_LPN);

  front = *TofL8_TopologyDefaultFront();
  front.gpio1 = rear.gpio1;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_ERR_SHARED_GPIO1);
}

static void test_lpn_is_required_for_two_online_sensors(void)
{
  TofL8SlotTopology_t rear = *TofL8_TopologyDefaultRear();
  TofL8SlotTopology_t front = *TofL8_TopologyDefaultFront();

  front.lpn = TOF_L8_GPIO_NONE;
  assert(TofL8_TopologyValidatePair(&rear, &front) ==
         TOF_L8_TOPOLOGY_ERR_MISSING_LPN);
}

int main(void)
{
  test_default_pair_uses_separate_buses_and_control_pins();
  test_shared_bus_requires_unique_runtime_addresses();
  test_duplicate_roles_and_shared_control_pins_are_rejected();
  test_lpn_is_required_for_two_online_sensors();
  return 0;
}
