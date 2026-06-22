import math
from dataclasses import dataclass
from typing import Optional

from .geometry import clamp, wrap_to_pi
from .lqr import diagonal, dlqr, model_matrices, multiply_vector
from .path_reference import project_path
from .simulation_types import Command, Pose
from .trajectory import Point


@dataclass
class TangentTrack:
    max_throttle: float = 0.4
    steering_gain: float = 0.9 / 1.5707963267948966
    cross_track_gain: float = 2.2
    cross_track_softening_distance: float = 0.18
    curvature_feedforward_gain: float = 0.10

    def command(self, pose: Pose, waypoints: list[Point], current_index: int, speed_mps: float) -> Command:
        reference = project_path(pose, waypoints, current_index)
        correction = math.atan2(
            self.cross_track_gain * reference.cross_track_error,
            self.cross_track_softening_distance,
        )
        desired_yaw = wrap_to_pi(reference.tangent_yaw + correction)
        yaw_error = wrap_to_pi(desired_yaw - pose.yaw)
        tangent_error = wrap_to_pi(reference.tangent_yaw - pose.yaw)
        steering = clamp(
            -self.curvature_feedforward_gain * reference.curvature - self.steering_gain * yaw_error,
            -1.0,
            1.0,
        )
        fade = 1.0 - abs(tangent_error) / math.pi
        throttle = self.max_throttle * max(0.35, fade)
        return Command(steering=steering, throttle=clamp(throttle, 0.0, self.max_throttle), index=reference.index)


@dataclass
class LQRTrack:
    max_throttle: float = 0.4
    target_speed_mps: float = 0.20
    wheelbase_m: float = 0.35
    steering_scale: float = 1.0
    throttle_accel_scale: float = 0.15
    curvature_feedforward_gain: float = 0.10
    q: tuple[float, float, float, float, float] = (3.0, 0.2, 2.5, 0.2, 0.8)
    r: tuple[float, float] = (1.0, 2.0)
    derivative_reset_index_jump: int = 8

    _previous_error: Optional[float] = None
    _previous_heading_error: Optional[float] = None
    _previous_index: Optional[int] = None

    def command(self, pose: Pose, waypoints: list[Point], current_index: int, speed_mps: float) -> Command:
        reference = project_path(pose, waypoints, current_index)
        dt = 0.1
        heading_error = wrap_to_pi(pose.yaw - reference.tangent_yaw)
        lateral_error = -reference.cross_track_error
        reset_derivative = self._reference_jumped(reference.index, len(waypoints))
        previous_error = lateral_error if reset_derivative or self._previous_error is None else self._previous_error
        previous_heading_error = (
            heading_error
            if reset_derivative or self._previous_heading_error is None
            else self._previous_heading_error
        )
        state = [
            lateral_error,
            (lateral_error - previous_error) / dt,
            heading_error,
            wrap_to_pi(heading_error - previous_heading_error) / dt,
            speed_mps - self.target_speed_mps,
        ]
        a, b = model_matrices(dt, max(speed_mps, self.target_speed_mps), self.wheelbase_m)
        gain = dlqr(a, b, diagonal(list(self.q)), diagonal(list(self.r)))
        feedback = multiply_vector(gain, state)

        steering = clamp(
            -self.curvature_feedforward_gain * reference.curvature + self.steering_scale * feedback[0],
            -1.0,
            1.0,
        )
        base = max(self.max_throttle * 0.35, self.max_throttle * min(1.0, self.target_speed_mps / 0.20))
        throttle = clamp(base - self.throttle_accel_scale * feedback[1], 0.0, self.max_throttle)

        self._previous_error = lateral_error
        self._previous_heading_error = heading_error
        self._previous_index = reference.index
        return Command(steering=steering, throttle=throttle, index=reference.index)

    def _reference_jumped(self, index: int, count: int) -> bool:
        if self._previous_index is None or count <= 0:
            return True
        forward_delta = (index - self._previous_index) % count
        return forward_delta > self.derivative_reset_index_jump
