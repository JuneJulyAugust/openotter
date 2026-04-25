/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * firmware_stack_guard — sentinel-based stack overflow detection.
 *
 * Cortex-M without an MPU silently corrupts memory below the stack
 * region when recursion or deep call chains exceed the linker's
 * `_Min_Stack_Size`. Symptoms range from random crashes to "the wrong
 * variable changed value" — extremely hard to triage post-mortem.
 *
 * This module places a known magic word at the bottom of the stack
 * region at boot. The main loop calls Firmware_StackGuard_Check()
 * each iteration; if the magic value has changed, the stack has
 * grown past its allocated bottom and we panic-reboot before the
 * corruption causes downstream chaos.
 *
 * Pure mapping math is host-tested. The guard read/write itself
 * touches a fixed address in RAM and only runs on the target.
 */

#ifndef FIRMWARE_STACK_GUARD_H
#define FIRMWARE_STACK_GUARD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FW_STACK_GUARD_MAGIC 0xDEADBEEFu

/*
 * Pure helper: compute the address of the stack guard word.
 *
 * The Cortex-M stack grows down from `estack_addr`. The bottom of the
 * configured stack region is `estack_addr - stack_size`. Returns 0 if
 * either input is 0 or stack_size > estack_addr (would underflow).
 *
 * Host-testable.
 */
uintptr_t FwStackGuard_BottomAddress(uintptr_t estack_addr,
                                     uintptr_t stack_size);

#ifndef HOST_TEST
/*
 * Stamp FW_STACK_GUARD_MAGIC at the bottom of the stack region. Call
 * once near the start of main(), AFTER global init (so it doesn't get
 * overwritten by .data/.bss copy) and BEFORE the main loop.
 */
void FwStackGuard_Init(void);

/*
 * Returns true if the magic word at the stack bottom is still intact.
 * Cheap (one memory read + compare); safe to call from any non-fault
 * context on every main-loop iteration.
 *
 * Returning false means the stack has overflowed at some point since
 * Init — call Firmware_Panic(FW_PANIC_STACK) to reset cleanly before
 * the corruption manifests as something less diagnosable.
 */
bool FwStackGuard_Check(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* FIRMWARE_STACK_GUARD_H */
