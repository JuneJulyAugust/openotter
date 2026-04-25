/* SPDX-License-Identifier: BSD-3-Clause */
#include "firmware_stack_guard.h"

#include <stddef.h>

uintptr_t FwStackGuard_BottomAddress(uintptr_t estack_addr,
                                     uintptr_t stack_size) {
  if (estack_addr == 0u || stack_size == 0u) return 0u;
  if (stack_size > estack_addr) return 0u; /* would underflow */
  return estack_addr - stack_size;
}

#ifndef HOST_TEST

/* Linker-script symbols. Their *addresses* (not values) carry the meaning:
 *   _estack          — top of stack region (highest address; SP starts here)
 *   _Min_Stack_Size  — symbol whose address equals the configured stack size
 */
extern uint32_t _estack;
extern uint32_t _Min_Stack_Size;

static volatile uint32_t *guard_addr(void) {
  uintptr_t addr = FwStackGuard_BottomAddress(
      (uintptr_t)&_estack, (uintptr_t)&_Min_Stack_Size);
  return (volatile uint32_t *)addr;
}

void FwStackGuard_Init(void) {
  volatile uint32_t *p = guard_addr();
  if (p != NULL) {
    *p = FW_STACK_GUARD_MAGIC;
  }
}

bool FwStackGuard_Check(void) {
  volatile uint32_t *p = guard_addr();
  if (p == NULL) return true; /* misconfigured — fail open, don't reboot loop */
  return *p == FW_STACK_GUARD_MAGIC;
}

#endif /* HOST_TEST */
