/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * Pure ROI builder for VL53L1CB multi-zone scanning.
 *
 * Intentionally HAL-free so it can be compiled against the host toolchain for
 * unit testing (tests/host/test_tof_l1_roi.c).
 *
 * Coordinate system (from VL53L1_UserRoi_t): X,Y in [0,15], SPAD array origin
 * at bottom-left, Y grows upward — so TopLeftY >= BotRightY.
 *
 * Layout tiling:
 *   1x1: one ROI covers the full array (0,15)-(15,0).
 *   3x3: stride-5 tiling of the central 15x15 window. The Y=15 top row and
 *        X=15 right column are intentionally dropped; all nine zones are a
 *        uniform 5x5 SPAD block for a flat noise floor.
 *   4x4: stride-4 tiling of the full 16x16 array; each zone is 4x4 SPAD,
 *        which is the minimum supported by the firmware.
 ******************************************************************************/

#include "tof_l1.h"

/* Static tables — top-to-bottom, left-to-right. Precomputed so runtime math
 * can't drift from test assertions. */
static const TofL1_Roi_t k_roi_1x1[1] = {
  { 0, 15, 15, 0 },
};

static const TofL1_Roi_t k_roi_3x3[9] = {
  {  0, 14,  4, 10 }, {  5, 14,  9, 10 }, { 10, 14, 14, 10 },
  {  0,  9,  4,  5 }, {  5,  9,  9,  5 }, { 10,  9, 14,  5 },
  {  0,  4,  4,  0 }, {  5,  4,  9,  0 }, { 10,  4, 14,  0 },
};

static const TofL1_Roi_t k_roi_4x4[16] = {
  {  0, 15,  3, 12 }, {  4, 15,  7, 12 }, {  8, 15, 11, 12 }, { 12, 15, 15, 12 },
  {  0, 11,  3,  8 }, {  4, 11,  7,  8 }, {  8, 11, 11,  8 }, { 12, 11, 15,  8 },
  {  0,  7,  3,  4 }, {  4,  7,  7,  4 }, {  8,  7, 11,  4 }, { 12,  7, 15,  4 },
  {  0,  3,  3,  0 }, {  4,  3,  7,  0 }, {  8,  3, 11,  0 }, { 12,  3, 15,  0 },
};

uint8_t TofL1_BuildRoi(TofL1_Layout_t layout, TofL1_Roi_t out[16])
{
  const TofL1_Roi_t *src;
  uint8_t n;

  switch (layout) {
    case TOF_LAYOUT_1x1: src = k_roi_1x1; n = 1;  break;
    case TOF_LAYOUT_3x3: src = k_roi_3x3; n = 9;  break;
    case TOF_LAYOUT_4x4: src = k_roi_4x4; n = 16; break;
    default: return 0;
  }

  for (uint8_t i = 0; i < n; ++i) {
    out[i] = src[i];
  }
  return n;
}
