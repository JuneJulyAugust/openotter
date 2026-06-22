import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Vector:
    x: float
    z: float


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def wrap_to_pi(angle: float) -> float:
    while angle > math.pi:
        angle -= 2.0 * math.pi
    while angle < -math.pi:
        angle += 2.0 * math.pi
    return angle


def forward_vector(yaw: float) -> Vector:
    return Vector(math.cos(yaw), -math.sin(yaw))


def right_vector(yaw: float) -> Vector:
    return Vector(math.sin(yaw), math.cos(yaw))


def heading_from_points(start_x: float, start_z: float, end_x: float, end_z: float) -> float:
    return math.atan2(-(end_z - start_z), end_x - start_x)
