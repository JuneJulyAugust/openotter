/* SPDX-License-Identifier: BSD-3-Clause */
#include "firmware_mpu.h"

#ifndef HOST_TEST
#include "stm32l4xx_hal.h"
#endif

/* Pure helpers — host-testable. */

uint8_t FwMpu_EncodeSize(uint32_t size_bytes) {
  /* Cortex-M4 MPU minimum is 32 bytes (RASR.SIZE = 4). */
  if (size_bytes < 32u) return 0u;

  /* Must be a power of 2: x & (x - 1) == 0 for nonzero powers of 2. */
  if ((size_bytes & (size_bytes - 1u)) != 0u) return 0u;

  /* Find log2. Cap at the hardware max (4 GB → SIZE = 31). */
  uint8_t log2 = 0u;
  uint32_t v = size_bytes;
  while (v > 1u) {
    v >>= 1;
    log2++;
  }
  if (log2 == 0u || log2 > 32u) return 0u;
  return (uint8_t)(log2 - 1u);
}

bool FwMpu_IsAligned(uintptr_t addr, uint32_t size_bytes) {
  if (size_bytes == 0u) return false;
  /* Power-of-2 alignment via AND mask. Caller must ensure size_bytes is a
   * power of 2; if not, this returns false (mask test fails). */
  if ((size_bytes & (size_bytes - 1u)) != 0u) return false;
  return (addr & (size_bytes - 1u)) == 0u;
}

#ifndef HOST_TEST

extern uint32_t _estack;
extern uint32_t _Min_Stack_Size;

void FwMpu_Init(void) {
  /* Place the no-access guard at the bottom of the configured stack
   * region. Stack grows down from _estack toward this address; any push
   * that crosses into the guard triggers MemManage. */
  uintptr_t guard_addr =
      (uintptr_t)&_estack - (uintptr_t)&_Min_Stack_Size;

  /* The 1 KB stack region (0x400) at top of RAM lands on a 32-byte
   * boundary, so the natural alignment requirement is satisfied. We
   * still verify in code; if alignment is off, skip MPU setup rather
   * than enable an incorrectly placed region. */
  if (!FwMpu_IsAligned(guard_addr, FW_MPU_STACK_GUARD_SIZE)) {
    return;
  }
  uint8_t size_enc = FwMpu_EncodeSize(FW_MPU_STACK_GUARD_SIZE);
  if (size_enc == 0u) {
    return;
  }

  /* Enable MemManage faults so we get a clean MemManage exception
   * instead of an escalated HardFault when the guard fires. */
  SCB->SHCSR |= SCB_SHCSR_MEMFAULTENA_Msk;

  HAL_MPU_Disable();

  MPU_Region_InitTypeDef region;
  region.Enable           = MPU_REGION_ENABLE;
  region.Number           = MPU_REGION_NUMBER0;
  region.BaseAddress      = (uint32_t)guard_addr;
  region.Size             = size_enc;          /* 4 = 32 B */
  region.SubRegionDisable = 0x00;
  region.TypeExtField     = MPU_TEX_LEVEL0;
  region.AccessPermission = MPU_REGION_NO_ACCESS;
  region.DisableExec      = MPU_INSTRUCTION_ACCESS_DISABLE;
  region.IsShareable      = MPU_ACCESS_NOT_SHAREABLE;
  region.IsCacheable      = MPU_ACCESS_NOT_CACHEABLE;
  region.IsBufferable     = MPU_ACCESS_NOT_BUFFERABLE;
  HAL_MPU_ConfigRegion(&region);

  /* Enable MPU with PRIVDEFENA so privileged accesses to other regions
   * (peripheral MMIO, etc.) keep working without explicit configuration.
   * Only the guard region restricts. */
  HAL_MPU_Enable(MPU_PRIVILEGED_DEFAULT);
}

#endif /* HOST_TEST */
