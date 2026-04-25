/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l5_debounce.h"

bool TofL5Debounce_ShouldSkip(uint32_t now_ms,
                              uint32_t last_configure_tick,
                              uint32_t debounce_ms) {
  if (last_configure_tick == 0u) return false;
  return (now_ms - last_configure_tick) < debounce_ms;
}
