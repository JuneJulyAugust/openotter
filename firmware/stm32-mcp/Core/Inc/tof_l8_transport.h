/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_L8_TRANSPORT_H
#define TOF_L8_TRANSPORT_H

#include <stdint.h>

#include "tof_l8.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  TOF_L8_TRANSPORT_NONE = 0,
  TOF_L8_TRANSPORT_I2C,
  TOF_L8_TRANSPORT_SPI,
  TOF_L8_TRANSPORT_AMBIGUOUS,
} TofL8TransportKind_t;

typedef enum {
  TOF_L8_I2C_BUS_1 = 1,
  TOF_L8_I2C_BUS_3 = 3,
} TofL8I2cBus_t;

typedef enum {
  TOF_L8_SPI_BUS_1 = 1,
} TofL8SpiBus_t;

typedef enum {
  TOF_L8_GPIO_NONE = 0,
  TOF_L8_GPIO_PC2_A3,
  TOF_L8_GPIO_PC3_A2,
  TOF_L8_GPIO_PC4_A1,
  TOF_L8_GPIO_PC5_A0,
  TOF_L8_GPIO_PA15_D9,
  TOF_L8_GPIO_PA2_D10,
  TOF_L8_GPIO_PB2_D8,
} TofL8GpioTag_t;

typedef struct {
  TofL8I2cBus_t bus;
  uint16_t addr_8bit;
} TofL8I2cTransport_t;

typedef struct {
  TofL8SpiBus_t bus;
  TofL8GpioTag_t ncs;
} TofL8SpiTransport_t;

typedef struct {
  TofL8TransportKind_t kind;
  union {
    TofL8I2cTransport_t i2c;
    TofL8SpiTransport_t spi;
  };
} TofL8TransportHandle_t;

void TofL8Transport_InitI2c(TofL8TransportHandle_t *handle,
                            TofL8I2cBus_t bus, uint16_t addr_8bit);
void TofL8Transport_InitSpi(TofL8TransportHandle_t *handle,
                            TofL8SpiBus_t bus, TofL8GpioTag_t ncs);
TofL8TransportKind_t TofL8Transport_ChooseProbe(int i2c_alive, int spi_alive);
uint16_t TofL8Transport_SpiWriteHeader(uint16_t register_addr);
uint16_t TofL8Transport_SpiReadHeader(uint16_t register_addr);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L8_TRANSPORT_H */
