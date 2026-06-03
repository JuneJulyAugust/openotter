/* SPDX-License-Identifier: BSD-3-Clause */
#include <assert.h>
#include <math.h>
#include <string.h>

#include "drive_safety.h"

static void test_rear_projection_is_identity(void)
{
  RevSafetyInput_t physical = {
      .velocity_mps = -0.4f,
      .throttle_us = 1400,
      .raw_depth_m = 0.8f,
      .zone_valid = true,
      .frame_is_new = true,
      .now_ms = 100,
  };
  RevSafetyInput_t projected = {0};

  DriveSafety_ProjectInput(DRIVE_SAFETY_DIRECTION_REAR, 1500u,
                           &physical, &projected);

  assert(fabsf(projected.velocity_mps - physical.velocity_mps) < 1e-6f);
  assert(projected.throttle_us == physical.throttle_us);
  assert(projected.zone_valid == physical.zone_valid);
}

static void test_front_projection_maps_forward_to_reverse_model(void)
{
  RevSafetyInput_t physical = {
      .velocity_mps = 0.6f,
      .throttle_us = 1650,
      .raw_depth_m = 0.7f,
      .zone_valid = true,
      .frame_is_new = true,
      .now_ms = 200,
  };
  RevSafetyInput_t projected = {0};

  DriveSafety_ProjectInput(DRIVE_SAFETY_DIRECTION_FRONT, 1500u,
                           &physical, &projected);

  assert(fabsf(projected.velocity_mps - -0.6f) < 1e-6f);
  assert(projected.throttle_us == 1350);
  assert(projected.raw_depth_m == physical.raw_depth_m);
}

static void test_front_event_reports_physical_velocity(void)
{
  RevSafetyEvent_t projected = {
      .state = REV_SAFETY_STATE_BRAKE,
      .cause = REV_SAFETY_CAUSE_OBSTACLE,
      .trigger_velocity_mps = -0.7f,
      .latched_speed_mps = 0.7f,
      .trigger_depth_m = 0.4f,
  };
  RevSafetyEvent_t physical = {0};

  DriveSafety_ProjectEvent(DRIVE_SAFETY_DIRECTION_FRONT, &projected,
                           &physical);

  assert(physical.state == REV_SAFETY_STATE_BRAKE);
  assert(physical.cause == REV_SAFETY_CAUSE_OBSTACLE);
  assert(fabsf(physical.trigger_velocity_mps - 0.7f) < 1e-6f);
  assert(fabsf(physical.latched_speed_mps - 0.7f) < 1e-6f);
}

static void test_directional_throttle_blocking(void)
{
  assert(DriveSafety_ThrottleBlocked(DRIVE_SAFETY_DIRECTION_REAR,
                                     1400, 1500u));
  assert(!DriveSafety_ThrottleBlocked(DRIVE_SAFETY_DIRECTION_REAR,
                                      1600, 1500u));
  assert(DriveSafety_ThrottleBlocked(DRIVE_SAFETY_DIRECTION_FRONT,
                                     1600, 1500u));
  assert(!DriveSafety_ThrottleBlocked(DRIVE_SAFETY_DIRECTION_FRONT,
                                      1400, 1500u));
}

int main(void)
{
  test_rear_projection_is_identity();
  test_front_projection_maps_forward_to_reverse_model();
  test_front_event_reports_physical_velocity();
  test_directional_throttle_blocking();
  return 0;
}
