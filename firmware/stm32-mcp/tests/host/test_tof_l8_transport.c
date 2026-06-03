/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_transport.h"

#include <assert.h>

static void test_i2c_handle_configures_default_address(void)
{
  TofL8TransportHandle_t handle;
  TofL8Transport_InitI2c(&handle, TOF_L8_I2C_BUS_3,
                         TOF_L8_DEFAULT_I2C_ADDR_8BIT);

  assert(handle.kind == TOF_L8_TRANSPORT_I2C);
  assert(handle.i2c.bus == TOF_L8_I2C_BUS_3);
  assert(handle.i2c.addr_8bit == TOF_L8_DEFAULT_I2C_ADDR_8BIT);
}

static void test_spi_handle_configures_chip_select(void)
{
  TofL8TransportHandle_t handle;
  TofL8Transport_InitSpi(&handle, TOF_L8_SPI_BUS_1, TOF_L8_GPIO_PB2_D8);

  assert(handle.kind == TOF_L8_TRANSPORT_SPI);
  assert(handle.spi.bus == TOF_L8_SPI_BUS_1);
  assert(handle.spi.ncs == TOF_L8_GPIO_PB2_D8);
}

static void test_probe_choice_prefers_i2c_then_spi(void)
{
  assert(TofL8Transport_ChooseProbe(1, 0) == TOF_L8_TRANSPORT_I2C);
  assert(TofL8Transport_ChooseProbe(0, 1) == TOF_L8_TRANSPORT_SPI);
  assert(TofL8Transport_ChooseProbe(0, 0) == TOF_L8_TRANSPORT_NONE);
  assert(TofL8Transport_ChooseProbe(1, 1) == TOF_L8_TRANSPORT_AMBIGUOUS);
}

int main(void)
{
  test_i2c_handle_configures_default_address();
  test_spi_handle_configures_chip_select();
  test_probe_choice_prefers_i2c_then_spi();
  return 0;
}
