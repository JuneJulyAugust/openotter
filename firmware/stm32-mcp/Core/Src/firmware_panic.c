/* SPDX-License-Identifier: BSD-3-Clause */
#include "firmware_panic.h"

#include "pwm_control.h"

#ifndef HOST_TEST
#include "stm32l4xx.h"
#endif

char Firmware_PanicTag(Firmware_PanicReason_t reason) {
  switch (reason) {
    case FW_PANIC_HARD_FAULT:  return 'H';
    case FW_PANIC_MEM_MANAGE:  return 'M';
    case FW_PANIC_BUS_FAULT:   return 'B';
    case FW_PANIC_USAGE_FAULT: return 'U';
    case FW_PANIC_NMI:         return 'N';
    case FW_PANIC_ASSERT:      return 'A';
    case FW_PANIC_NONE:        /* fallthrough */
    default:                   return '?';
  }
}

#ifndef HOST_TEST

/*
 * Force PWM neutral via direct CCR writes.
 *
 * TIM3 is configured PSC=79, ARR=19999 → 1 tick = 1 µs. CCR value in ticks
 * therefore equals the pulse width in microseconds. We write PWM_NEUTRAL_US
 * (1500 µs) directly to CCR1 (throttle) and CCR4 (steering).
 *
 * No HAL function calls — the HAL state machine may be in an inconsistent
 * state during a fault. The TIM3 peripheral is independently clocked and
 * keeps shifting out PWM as long as the clock tree is alive.
 */
static void force_pwm_neutral_direct(void) {
  TIM3->CCR1 = (uint32_t)PWM_NEUTRAL_US; /* throttle (PB4) */
  TIM3->CCR4 = (uint32_t)PWM_NEUTRAL_US; /* steering (PB1) */
}

/*
 * Best-effort write of one byte to UART1 (PB6 TX). USART1 is mapped at
 * USART1_BASE; we poll the TXE bit and write to TDR. If the UART is dead
 * we time out after a few thousand cycles instead of hanging forever.
 */
static void uart1_putc_direct(char c) {
  /* SR.TXE (Transmit Data Register Empty) is bit 7 in ISR on STM32L4. */
  for (uint32_t i = 0; i < 100000u; ++i) {
    if (USART1->ISR & USART_ISR_TXE) {
      USART1->TDR = (uint8_t)c;
      return;
    }
  }
  /* timed out — give up; reset is coming anyway */
}

void Firmware_Panic(Firmware_PanicReason_t reason) {
  __disable_irq();

  /* Step 1: stop the actuators. This is the most important step. */
  force_pwm_neutral_direct();

  /* Step 2: emit the reason tag so a serial monitor can see why we rebooted.
   * Frame as "PANIC:X\r\n" so it stands out in the UART log. */
  uart1_putc_direct('P');
  uart1_putc_direct('A');
  uart1_putc_direct('N');
  uart1_putc_direct('I');
  uart1_putc_direct('C');
  uart1_putc_direct(':');
  uart1_putc_direct(Firmware_PanicTag(reason));
  uart1_putc_direct('\r');
  uart1_putc_direct('\n');

  /* Step 3: reset. The vector table reload + clean BLE re-advertise gives
   * the iOS client a fresh session within a couple of seconds. */
  NVIC_SystemReset();

  /* unreachable */
  for (;;) { __NOP(); }
}

#else  /* HOST_TEST — host tests never call Firmware_Panic; only the tag
        * mapping is exercised. Provide a stub so linkers don't complain. */

void Firmware_Panic(Firmware_PanicReason_t reason) {
  (void)reason;
  /* Cannot abort cleanly from a unit test process; we simply don't return. */
  for (;;) { /* spin */ }
}

#endif /* HOST_TEST */
