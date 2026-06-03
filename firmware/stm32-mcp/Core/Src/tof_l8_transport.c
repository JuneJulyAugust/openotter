/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8_transport.h"

#include <string.h>

void TofL8Transport_InitI2c(TofL8TransportHandle_t *handle,
                            TofL8I2cBus_t bus, uint16_t addr_8bit)
{
  if (handle == 0) return;

  memset(handle, 0, sizeof(*handle));
  handle->kind = TOF_L8_TRANSPORT_I2C;
  handle->i2c.bus = bus;
  handle->i2c.addr_8bit = addr_8bit;
}

void TofL8Transport_InitSpi(TofL8TransportHandle_t *handle,
                            TofL8SpiBus_t bus, TofL8GpioTag_t ncs)
{
  if (handle == 0) return;

  memset(handle, 0, sizeof(*handle));
  handle->kind = TOF_L8_TRANSPORT_SPI;
  handle->spi.bus = bus;
  handle->spi.ncs = ncs;
}

TofL8TransportKind_t TofL8Transport_ChooseProbe(int i2c_alive, int spi_alive)
{
  if (i2c_alive && spi_alive) return TOF_L8_TRANSPORT_AMBIGUOUS;
  if (i2c_alive) return TOF_L8_TRANSPORT_I2C;
  if (spi_alive) return TOF_L8_TRANSPORT_SPI;
  return TOF_L8_TRANSPORT_NONE;
}
