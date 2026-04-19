/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * Host test for TofL1_BuildRoi. Pure function, no HAL — compiles with gcc.
 *
 *   cc -std=c11 -Wall -Wextra -Werror -I ../../Core/Inc \
 *      ../../Core/Src/tof_l1_roi.c test_tof_l1_roi.c -o test_tof_l1_roi
 *   ./test_tof_l1_roi
 ******************************************************************************/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tof_l1.h"

static int g_fails = 0;

static void expect_roi(const char *label, TofL1_Roi_t got, TofL1_Roi_t want)
{
  if (got.tlx != want.tlx || got.tly != want.tly ||
      got.brx != want.brx || got.bry != want.bry) {
    fprintf(stderr,
            "FAIL %s: got {%u,%u,%u,%u} want {%u,%u,%u,%u}\n",
            label, got.tlx, got.tly, got.brx, got.bry,
                   want.tlx, want.tly, want.brx, want.bry);
    g_fails++;
  }
}

static void expect_count(const char *label, uint8_t got, uint8_t want)
{
  if (got != want) {
    fprintf(stderr, "FAIL %s: n=%u want %u\n", label, got, want);
    g_fails++;
  }
}

int main(void)
{
  TofL1_Roi_t out[16];

  memset(out, 0xAA, sizeof(out));
  expect_count("1x1 count", TofL1_BuildRoi(TOF_LAYOUT_1x1, out), 1);
  expect_roi("1x1 zone0", out[0], (TofL1_Roi_t){0, 15, 15, 0});

  memset(out, 0xAA, sizeof(out));
  expect_count("3x3 count", TofL1_BuildRoi(TOF_LAYOUT_3x3, out), 9);
  expect_roi("3x3 zone0 (TL)",     out[0], (TofL1_Roi_t){ 0, 14,  4, 10});
  expect_roi("3x3 zone4 (center)", out[4], (TofL1_Roi_t){ 5,  9,  9,  5});
  expect_roi("3x3 zone8 (BR)",     out[8], (TofL1_Roi_t){10,  4, 14,  0});

  memset(out, 0xAA, sizeof(out));
  expect_count("4x4 count", TofL1_BuildRoi(TOF_LAYOUT_4x4, out), 16);
  expect_roi("4x4 zone0 (TL)",  out[0],  (TofL1_Roi_t){ 0, 15,  3, 12});
  expect_roi("4x4 zone4",       out[4],  (TofL1_Roi_t){ 0, 11,  3,  8});
  expect_roi("4x4 zone8",       out[8],  (TofL1_Roi_t){ 0,  7,  3,  4});
  expect_roi("4x4 zone15 (BR)", out[15], (TofL1_Roi_t){12,  3, 15,  0});

  expect_count("invalid layout returns 0", TofL1_BuildRoi((TofL1_Layout_t)7, out), 0);

  /* Constraint: tly >= bry for every emitted ROI. */
  for (uint8_t layout_i = 0; layout_i < 3; ++layout_i) {
    TofL1_Layout_t layout = (TofL1_Layout_t[]){TOF_LAYOUT_1x1, TOF_LAYOUT_3x3, TOF_LAYOUT_4x4}[layout_i];
    uint8_t n = TofL1_BuildRoi(layout, out);
    for (uint8_t i = 0; i < n; ++i) {
      if (out[i].tly < out[i].bry) {
        fprintf(stderr, "FAIL layout=%u zone=%u tly<bry (%u<%u)\n",
                (unsigned)layout, i, out[i].tly, out[i].bry);
        g_fails++;
      }
      if (out[i].tlx > out[i].brx) {
        fprintf(stderr, "FAIL layout=%u zone=%u tlx>brx (%u>%u)\n",
                (unsigned)layout, i, out[i].tlx, out[i].brx);
        g_fails++;
      }
      if (out[i].tly > 15 || out[i].bry > 15 ||
          out[i].tlx > 15 || out[i].brx > 15) {
        fprintf(stderr, "FAIL layout=%u zone=%u out of [0,15]\n",
                (unsigned)layout, i);
        g_fails++;
      }
    }
  }

  if (g_fails) {
    fprintf(stderr, "\n%d failure(s)\n", g_fails);
    return 1;
  }
  printf("PASS all TofL1_BuildRoi assertions\n");
  return 0;
}
