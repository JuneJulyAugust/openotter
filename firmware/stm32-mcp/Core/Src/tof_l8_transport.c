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

uint16_t TofL8Transport_SpiWriteHeader(uint16_t register_addr)
{
  return (uint16_t)(register_addr | 0x8000u);
}

uint16_t TofL8Transport_SpiReadHeader(uint16_t register_addr)
{
  return (uint16_t)(register_addr & 0x7FFFu);
}

#ifdef STM32L475xx
#include "firmware_watchdog.h"
#include "main.h"
#include "stm32l4xx_hal.h"
#include "vl53l8cx_api.h"

extern I2C_HandleTypeDef hi2c3;
extern SPI_HandleTypeDef hspi1;

#define TOF_L8_TRANSFER_MIN_TIMEOUT_MS 1000u
#define TOF_L8_TRANSFER_MAX_TIMEOUT_MS 15000u

static uint32_t transfer_timeout_for_size(uint16_t size)
{
  uint32_t timeout = TOF_L8_TRANSFER_MIN_TIMEOUT_MS + ((uint32_t)size / 4u);
  return (timeout > TOF_L8_TRANSFER_MAX_TIMEOUT_MS)
             ? TOF_L8_TRANSFER_MAX_TIMEOUT_MS
             : timeout;
}

static int ncs_pin(TofL8GpioTag_t ncs, GPIO_TypeDef **port, uint16_t *pin)
{
  if (ncs == TOF_L8_GPIO_PB2_D8) {
    *port = ARD_D8_GPIO_Port;
    *pin = ARD_D8_Pin;
    return 1;
  }
  if (ncs == TOF_L8_GPIO_PA2_D10) {
    *port = ARD_D10_GPIO_Port;
    *pin = ARD_D10_Pin;
    return 1;
  }
  return 0;
}

static uint8_t set_ncs(TofL8GpioTag_t ncs, GPIO_PinState state)
{
  GPIO_TypeDef *port = 0;
  uint16_t pin = 0;
  if (!ncs_pin(ncs, &port, &pin)) return VL53L8CX_MCU_ERROR;

  HAL_GPIO_WritePin(port, pin, state);
  return VL53L8CX_STATUS_OK;
}

static uint8_t i2c_write(TofL8TransportHandle_t *transport,
                         uint16_t register_addr, uint8_t *data,
                         uint32_t size)
{
  if (transport->i2c.bus != TOF_L8_I2C_BUS_3 || size > UINT16_MAX) {
    return VL53L8CX_MCU_ERROR;
  }

  FwWatchdog_Refresh();
  uint16_t tx_size = (uint16_t)size;
  HAL_StatusTypeDef s = HAL_I2C_Mem_Write(
      &hi2c3, transport->i2c.addr_8bit, register_addr, I2C_MEMADD_SIZE_16BIT,
      data, tx_size, transfer_timeout_for_size(tx_size));
  return (s == HAL_OK) ? VL53L8CX_STATUS_OK : VL53L8CX_MCU_ERROR;
}

static uint8_t i2c_read(TofL8TransportHandle_t *transport,
                        uint16_t register_addr, uint8_t *data, uint32_t size)
{
  if (transport->i2c.bus != TOF_L8_I2C_BUS_3 || size > UINT16_MAX) {
    return VL53L8CX_MCU_ERROR;
  }

  FwWatchdog_Refresh();
  uint16_t rx_size = (uint16_t)size;
  HAL_StatusTypeDef s = HAL_I2C_Mem_Read(
      &hi2c3, transport->i2c.addr_8bit, register_addr, I2C_MEMADD_SIZE_16BIT,
      data, rx_size, transfer_timeout_for_size(rx_size));
  return (s == HAL_OK) ? VL53L8CX_STATUS_OK : VL53L8CX_MCU_ERROR;
}

static uint8_t spi_write(TofL8TransportHandle_t *transport,
                         uint16_t register_addr, uint8_t *data,
                         uint32_t size)
{
  if (transport->spi.bus != TOF_L8_SPI_BUS_1 || size > UINT16_MAX) {
    return VL53L8CX_MCU_ERROR;
  }

  uint16_t header_word = TofL8Transport_SpiWriteHeader(register_addr);
  uint8_t header[2] = {
      (uint8_t)(header_word >> 8),
      (uint8_t)(header_word & 0xFFu),
  };
  uint16_t tx_size = (uint16_t)size;
  uint32_t timeout = transfer_timeout_for_size(tx_size);

  FwWatchdog_Refresh();
  if (set_ncs(transport->spi.ncs, GPIO_PIN_RESET) != VL53L8CX_STATUS_OK) {
    return VL53L8CX_MCU_ERROR;
  }
  HAL_StatusTypeDef s = HAL_SPI_Transmit(&hspi1, header,
                                         (uint16_t)sizeof(header), timeout);
  if (s == HAL_OK && tx_size > 0u) {
    s = HAL_SPI_Transmit(&hspi1, data, tx_size, timeout);
  }
  (void)set_ncs(transport->spi.ncs, GPIO_PIN_SET);
  return (s == HAL_OK) ? VL53L8CX_STATUS_OK : VL53L8CX_MCU_ERROR;
}

static uint8_t spi_read(TofL8TransportHandle_t *transport,
                        uint16_t register_addr, uint8_t *data, uint32_t size)
{
  if (transport->spi.bus != TOF_L8_SPI_BUS_1 || size > UINT16_MAX) {
    return VL53L8CX_MCU_ERROR;
  }

  uint16_t header_word = TofL8Transport_SpiReadHeader(register_addr);
  uint8_t header[2] = {
      (uint8_t)(header_word >> 8),
      (uint8_t)(header_word & 0xFFu),
  };
  uint16_t rx_size = (uint16_t)size;
  uint32_t timeout = transfer_timeout_for_size(rx_size);

  FwWatchdog_Refresh();
  if (set_ncs(transport->spi.ncs, GPIO_PIN_RESET) != VL53L8CX_STATUS_OK) {
    return VL53L8CX_MCU_ERROR;
  }
  HAL_StatusTypeDef s = HAL_SPI_Transmit(&hspi1, header,
                                         (uint16_t)sizeof(header), timeout);
  if (s == HAL_OK && rx_size > 0u) {
    s = HAL_SPI_Receive(&hspi1, data, rx_size, timeout);
  }
  (void)set_ncs(transport->spi.ncs, GPIO_PIN_SET);
  return (s == HAL_OK) ? VL53L8CX_STATUS_OK : VL53L8CX_MCU_ERROR;
}

uint8_t TofL8Transport_Write(void *handle, uint16_t register_addr,
                             uint8_t *data, uint32_t size)
{
  if (handle == 0) return VL53L8CX_MCU_ERROR;

  TofL8TransportHandle_t *transport = (TofL8TransportHandle_t *)handle;
  if (transport->kind == TOF_L8_TRANSPORT_I2C) {
    return i2c_write(transport, register_addr, data, size);
  }
  if (transport->kind == TOF_L8_TRANSPORT_SPI) {
    return spi_write(transport, register_addr, data, size);
  }
  return VL53L8CX_MCU_ERROR;
}

uint8_t TofL8Transport_Read(void *handle, uint16_t register_addr,
                            uint8_t *data, uint32_t size)
{
  if (handle == 0) return VL53L8CX_MCU_ERROR;

  TofL8TransportHandle_t *transport = (TofL8TransportHandle_t *)handle;
  if (transport->kind == TOF_L8_TRANSPORT_I2C) {
    return i2c_read(transport, register_addr, data, size);
  }
  if (transport->kind == TOF_L8_TRANSPORT_SPI) {
    return spi_read(transport, register_addr, data, size);
  }
  return VL53L8CX_MCU_ERROR;
}

uint8_t TofL8Transport_Wait(void *handle, uint32_t time_ms)
{
  (void)handle;
  uint32_t start = HAL_GetTick();
  while ((HAL_GetTick() - start) < time_ms) {
    FwWatchdog_Refresh();
  }
  return VL53L8CX_STATUS_OK;
}
#endif
