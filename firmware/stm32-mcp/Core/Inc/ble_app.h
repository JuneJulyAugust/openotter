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
/* Added in v0.4.0 — see
 * docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md */
#define OPENOTTER_SAFETY_CHAR_UUID 0xFE43 /* Notify: safety state + snapshot */
#define OPENOTTER_MODE_CHAR_UUID   0xFE44 /* Write+read: 0=Drive, 1=Debug */

typedef enum {
  OPENOTTER_MODE_DRIVE = 0,
  OPENOTTER_MODE_DEBUG = 1,
} OpenOtterMode_t;

typedef struct __attribute__((packed)) {
  int16_t steering_us;
  int16_t throttle_us;
  int16_t velocity_mm_per_s;   /* signed; negative = reversing */
} BLE_CommandPayload_t;

_Static_assert(sizeof(BLE_CommandPayload_t) == 6,
               "BLE_CommandPayload_t must be 6 B on wire");

typedef struct __attribute__((packed)) {
  uint32_t seq;
  uint32_t timestamp_ms;
  uint8_t  state;                  /* 0=SAFE, 1=BRAKE */
  uint8_t  cause;                  /* RevSafetyCause_t */
  uint8_t  _pad[2];
  int16_t  trigger_velocity_mm_s;
  uint16_t trigger_depth_mm;
  uint16_t critical_distance_mm;
  uint16_t latched_speed_mm_s;
} BLE_SafetyEventPayload_t;

_Static_assert(sizeof(BLE_SafetyEventPayload_t) == 20,
               "BLE_SafetyEventPayload_t must be 20 B on wire");

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
 *         Runs the reverse safety supervisor, applies arbitrated PWM,
 *         and publishes safety notifications as needed.
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

/**
 * @brief  Query current operating mode (used by ble_tof.c to gate
 *         config writes and frame notifications).
 */
OpenOtterMode_t BLE_App_GetMode(void);

#ifdef __cplusplus
}
#endif

#endif /* __BLE_APP_H */
