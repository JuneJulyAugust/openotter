/**
 ******************************************************************************
 * @file    ble_app.h
 * @brief   OpenOtter BLE Application — public interface
 *
 *          Exposes a custom GATT service for receiving steering and throttle
 *          commands over BLE, and applying them as TIM3 PWM pulse widths.
 ******************************************************************************
 */

#ifndef __BLE_APP_H
#define __BLE_APP_H

#include "stm32l4xx_hal.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Custom GATT Service UUIDs ---- */
/* 128-bit base UUID: 00000000-BEEF-CAFE-C0DE-METALB0T0001
 * We use 16-bit short UUIDs within the BlueNRG stack for simplicity. */
#define OPENOTTER_CONTROL_SVC_UUID 0xFE40 /* Custom control service */
#define OPENOTTER_COMMAND_CHAR_UUID                                            \
  0xFE41                                  /* Write char: steering + throttle   \
                                           */
#define OPENOTTER_STATUS_CHAR_UUID 0xFE42 /* Notify char: status feedback */

/* ---- PWM Constants (matching TIM3 config: PSC=79, ARR=19999 → 50Hz) ---- */
#define PWM_PERIOD_US 20000 /* 20ms full period */
#define PWM_NEUTRAL_US 1500 /* 1.5ms = neutral position */
#define PWM_MIN_US 1000     /* 1.0ms = full reverse / left */
#define PWM_MAX_US 2000     /* 2.0ms = full forward / right */

/* ---- Safety ---- */
#define BLE_SAFETY_TIMEOUT_MS 1500 /* Revert to neutral if no command */

/* ---- Public API ---- */

/**
 * @brief  Initialize the BlueNRG-MS BLE stack and register the custom
 *         GATT service for receiving commands.
 * @param  htim  Pointer to the TIM3 handle (for PWM output)
 * @retval 0 on success, negative on error
 */
int BLE_App_Init(TIM_HandleTypeDef *htim);

/**
 * @brief  Process BLE events. Must be called in the main loop.
 *         Also checks safety timeout and reverts to neutral if needed.
 */
void BLE_App_Process(void);

/**
 * @brief  Returns the tick count of the last received BLE command.
 */
uint32_t BLE_App_GetLastCommandTime(void);

/**
 * @brief  Check if a BLE central is currently connected.
 * @retval 1 if connected, 0 otherwise
 */
int BLE_App_IsConnected(void);

#ifdef __cplusplus
}
#endif

#endif /* __BLE_APP_H */
