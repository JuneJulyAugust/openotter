/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * firmware_mpu — Cortex-M4 MPU configuration: hardware stack guard region.
 *
 * Complements firmware_stack_guard.c (sentinel-based detection) with
 * atomic detection: a no-access region at the bottom of the stack
 * traps any push that would overflow on the FAULTING instruction itself
 * via MemManage exception. The existing MemManage_Handler already calls
 * Firmware_Panic(FW_PANIC_MEM_MANAGE), so the panic path is reused.
 *
 * Why both:
 *   - Sentinel: cheap, periodic (per main-loop tick). May miss a fast
 *     overflow that pushes far past the bottom in a single function call
 *     before we get back to the check.
 *   - MPU: instant; faulting PC points at the offending instruction.
 *     Costs an MPU region (we have 8 on Cortex-M4) and a few cycles
 *     during the access check.
 *
 * Together, no realistic stack overflow goes undetected.
 *
 * Pure region-encoding math is host-tested. The actual MPU programming
 * uses HAL_MPU_ConfigRegion under the on-target build.
 */

#ifndef FIRMWARE_MPU_H
#define FIRMWARE_MPU_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Size of the MPU stack guard region in bytes. Must be a power of 2 ≥ 32.
 * Cortex-M4 MPU minimum region size is 32 bytes. We use 32 to leave the
 * remaining stack region usable. */
#define FW_MPU_STACK_GUARD_SIZE 32u

/*
 * Compute the Cortex-M4 MPU RASR.SIZE field for a given region size in
 * bytes. The encoding is `log2(size) - 1` (so 32 B → 4, 64 B → 5, ...).
 *
 * Returns 0 if `size_bytes` is not a power of 2 or is < 32 (the MPU
 * hardware minimum). Pure, host-testable.
 */
uint8_t FwMpu_EncodeSize(uint32_t size_bytes);

/*
 * Returns true iff `addr` is aligned to `size_bytes`. Cortex-M4 MPU
 * requires the region base address to be a multiple of the region size.
 *
 * Pure, host-testable.
 */
bool FwMpu_IsAligned(uintptr_t addr, uint32_t size_bytes);

/*
 * Compute the hardware no-access guard address for the stack layout.
 *
 * The sentinel lives at `estack_addr - stack_size`; the MPU guard sits
 * immediately below it so sentinel init/check can still read and write
 * the magic word while an overflow past the configured stack bottom
 * traps in hardware.
 *
 * Returns 0 if the inputs would underflow.
 */
uintptr_t FwMpu_HardwareGuardAddress(uintptr_t estack_addr,
                                     uintptr_t stack_size);

#ifndef HOST_TEST
/*
 * Configure an MPU region as no-access at the stack bottom, then enable
 * the MPU. Also enables the MemManage fault so an SP push into the
 * guard region is delivered as MemManage rather than escalating directly
 * to HardFault.
 *
 * Call once near the start of main(), after the linker-provided symbols are
 * available. The MPU guard sits below the sentinel word, so either call order
 * relative to FwStackGuard_Init() is safe.
 */
void FwMpu_Init(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* FIRMWARE_MPU_H */
