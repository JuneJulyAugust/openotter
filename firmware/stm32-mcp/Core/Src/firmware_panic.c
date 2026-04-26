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
    case FW_PANIC_STACK:       return 'S';
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

static void uart1_puts_direct(const char *s) {
  while (*s) uart1_putc_direct(*s++);
}

static void uart1_put_hex32(uint32_t v) {
  static const char hex[] = "0123456789ABCDEF";
  for (int i = 7; i >= 0; --i) {
    uart1_putc_direct(hex[(v >> (i * 4)) & 0xFu]);
  }
}

static void uart1_put_kv(const char *key, uint32_t v) {
  uart1_putc_direct(' ');
  uart1_puts_direct(key);
  uart1_putc_direct('=');
  uart1_put_hex32(v);
}

/* Log Cortex-M4 fault status registers + the relevant slice of the stacked
 * exception frame. These pinpoint the faulting instruction and operand
 * without a debugger attached. */
static void log_fault_context(void) {
  uint32_t cfsr  = SCB->CFSR;
  uint32_t hfsr  = SCB->HFSR;
  uint32_t mmfar = SCB->MMFAR;
  uint32_t bfar  = SCB->BFAR;

  /* MSP at fault entry. PSP isn't useful here: the BLE middleware does not
   * use PSP, so kernel and app share MSP. The hardware-stacked frame is
   * therefore at the current MSP. */
  uint32_t msp = __get_MSP();
  uint32_t *frame = (uint32_t *)msp;
  uint32_t r0 = frame[0];
  uint32_t r1 = frame[1];
  uint32_t r2 = frame[2];
  uint32_t r3 = frame[3];
  uint32_t r12 = frame[4];
  uint32_t lr  = frame[5];
  uint32_t pc  = frame[6];
  uint32_t psr = frame[7];

  uart1_puts_direct("FAULT");
  uart1_put_kv("CFSR", cfsr);
  uart1_put_kv("HFSR", hfsr);
  uart1_put_kv("MMFAR", mmfar);
  uart1_put_kv("BFAR", bfar);
  uart1_put_kv("PC", pc);
  uart1_put_kv("LR", lr);
  uart1_put_kv("R0", r0);
  uart1_put_kv("R1", r1);
  uart1_put_kv("R2", r2);
  uart1_put_kv("R3", r3);
  uart1_put_kv("R12", r12);
  uart1_put_kv("PSR", psr);
  uart1_put_kv("MSP", msp);
  uart1_puts_direct("\r\n");
}

void Firmware_Panic(Firmware_PanicReason_t reason) {
  __disable_irq();

  /* Step 1: stop the actuators. This is the most important step. */
  force_pwm_neutral_direct();

  /* Step 2: emit the reason tag so a serial monitor can see why we rebooted.
   * Frame as "PANIC:X\r\n" so it stands out in the UART log. */
  uart1_puts_direct("PANIC:");
  uart1_putc_direct(Firmware_PanicTag(reason));
  uart1_puts_direct("\r\n");

  /* Step 3: dump fault registers + stacked frame. Useful for HardFault,
   * MemManage, BusFault, UsageFault. NMI/STACK/ASSERT also benefit because
   * SCB->CFSR is harmless to print. */
  log_fault_context();

  /* Step 4: reset. The vector table reload + clean BLE re-advertise gives
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
