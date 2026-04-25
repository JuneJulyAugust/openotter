/* SPDX-License-Identifier: BSD-3-Clause */
#include "firmware_watchdog.h"

#include <stddef.h>

#ifndef HOST_TEST
#include "stm32l4xx_hal.h"
static IWDG_HandleTypeDef s_iwdg;
#endif

/* IWDG reload register is 12 bits → max 4095. */
#define IWDG_RELOAD_MAX 4095u

uint16_t FwWatchdog_ComputeReload(uint32_t timeout_ms,
                                  uint32_t lsi_hz,
                                  uint16_t prescaler_div) {
  if (lsi_hz == 0u || prescaler_div == 0u) return 0u;

  /* IWDG counter ticks at lsi_hz / prescaler_div. We want the counter to
   * span timeout_ms; reload = (lsi_hz / prescaler_div) * (timeout_ms / 1000)
   *                        = (lsi_hz * timeout_ms) / (prescaler_div * 1000)
   * Compute as 64-bit to avoid overflow on extreme inputs. */
  uint64_t numerator = (uint64_t)lsi_hz * (uint64_t)timeout_ms;
  uint64_t reload    = numerator / ((uint64_t)prescaler_div * 1000u);

  if (reload == 0u) return 0u; /* timeout too short for this prescaler */
  if (reload > IWDG_RELOAD_MAX) return 0u; /* timeout exceeds prescaler range */
  return (uint16_t)reload;
}

uint16_t FwWatchdog_PickPrescaler(uint32_t timeout_ms, uint32_t lsi_hz) {
  static const uint16_t k_dividers[] = {4, 8, 16, 32, 64, 128, 256};
  for (size_t i = 0; i < sizeof(k_dividers) / sizeof(k_dividers[0]); ++i) {
    if (FwWatchdog_ComputeReload(timeout_ms, lsi_hz, k_dividers[i]) > 0u) {
      return k_dividers[i];
    }
  }
  return 0u;
}

#ifndef HOST_TEST

/*
 * Map a divider value (4, 8, 16, ..., 256) to the HAL IWDG_PRESCALER_*
 * constant the IWDG_InitTypeDef expects.
 */
static uint32_t prescaler_to_hal(uint16_t divider) {
  switch (divider) {
    case 4:   return IWDG_PRESCALER_4;
    case 8:   return IWDG_PRESCALER_8;
    case 16:  return IWDG_PRESCALER_16;
    case 32:  return IWDG_PRESCALER_32;
    case 64:  return IWDG_PRESCALER_64;
    case 128: return IWDG_PRESCALER_128;
    case 256: return IWDG_PRESCALER_256;
    default:  return IWDG_PRESCALER_256; /* safest fallback: longest period */
  }
}

void FwWatchdog_Init(void) {
  uint16_t prescaler = FwWatchdog_PickPrescaler(
      FW_WATCHDOG_DEFAULT_TIMEOUT_MS, FW_WATCHDOG_LSI_HZ);
  uint16_t reload = FwWatchdog_ComputeReload(
      FW_WATCHDOG_DEFAULT_TIMEOUT_MS, FW_WATCHDOG_LSI_HZ, prescaler);

  s_iwdg.Instance       = IWDG;
  s_iwdg.Init.Prescaler = prescaler_to_hal(prescaler);
  s_iwdg.Init.Reload    = reload;
  s_iwdg.Init.Window    = IWDG_WINDOW_DISABLE;

  /* If init fails, do NOT spin — we don't want to brick the system before
   * the main loop ever runs. The unprotected loop is no worse than the
   * pre-watchdog state. */
  (void)HAL_IWDG_Init(&s_iwdg);
}

void FwWatchdog_Refresh(void) {
  /* Cheap; safe to call from any context once the IWDG is started. */
  (void)HAL_IWDG_Refresh(&s_iwdg);
}

#endif /* HOST_TEST */
