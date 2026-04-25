/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * firmware_panic — last-resort recovery for ARM Cortex-M fault handlers.
 *
 * On HardFault, MemManage, BusFault, or UsageFault, the CPU has hit an
 * unrecoverable condition (null deref, alignment error, division by zero,
 * stack overflow, etc.). The default CubeMX behavior is `while (1) {}` —
 * which freezes the system with the last PWM value latched on TIM3, leaving
 * the vehicle physically running. Unacceptable for a safety-critical
 * actuator path.
 *
 * Firmware_Panic() instead:
 *   1. Forces TIM3 CH1 (throttle) and CH4 (steering) to PWM neutral by
 *      writing CCR registers directly. The PWM peripheral keeps running
 *      from its own clock even if the CPU core has faulted, so this stops
 *      the ESC and centers the servo before the system reboots.
 *   2. Best-effort writes a panic-reason byte to UART1 (direct register
 *      write — HAL may be in an inconsistent state during a fault).
 *   3. Triggers NVIC_SystemReset(). The board reboots into a clean state
 *      and the BLE stack reconnects within a couple of seconds.
 *
 * Pure C (header is host-includable; the .c file pulls in HAL register
 * names but uses only volatile mem-mapped writes — no HAL function calls).
 */

#ifndef FIRMWARE_PANIC_H
#define FIRMWARE_PANIC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  FW_PANIC_NONE         = 0,
  FW_PANIC_HARD_FAULT   = 1,
  FW_PANIC_MEM_MANAGE   = 2,
  FW_PANIC_BUS_FAULT    = 3,
  FW_PANIC_USAGE_FAULT  = 4,
  FW_PANIC_NMI          = 5,
  FW_PANIC_ASSERT       = 6,
  FW_PANIC_STACK        = 7, /* sentinel guard at stack bottom corrupted */
} Firmware_PanicReason_t;

/*
 * Map a panic reason to the single-byte tag emitted on UART1 right before
 * NVIC_SystemReset(). Pure, host-testable.
 *
 * The reset cause is encoded as one ASCII byte so a test fixture or a
 * serial-monitoring script can read the reboot reason out of the UART log
 * without needing to interpret framing. NONE returns '?' (sentinel).
 */
char Firmware_PanicTag(Firmware_PanicReason_t reason);

/*
 * Panic entry point. Call only from a fault handler context — does NOT
 * return. Forces PWM outputs to neutral (1500 µs), writes one tag byte to
 * UART1, then triggers NVIC_SystemReset().
 */
void Firmware_Panic(Firmware_PanicReason_t reason) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif /* FIRMWARE_PANIC_H */
