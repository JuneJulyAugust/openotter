import math
from dataclasses import dataclass

from .geometry import clamp, heading_from_points, right_vector, wrap_to_pi
from .simulation_types import Pose
from .trajectory import Point


@dataclass(frozen=True)
class PathReference:
    index: int
    projected: Point
    tangent_yaw: float
    cross_track_error: float
    curvature: float


def project_path(
    pose: Pose,
    waypoints: list[Point],
    current_index: int,
    progress_search_count: int = 32,
    curvature_sample_span: int = 3,
) -> PathReference:
    if len(waypoints) < 2:
        return PathReference(0, Point(pose.x, pose.z), pose.yaw, 0.0, 0.0)

    current_index %= len(waypoints)
    best_index = current_index
    best = _project_segment(pose, waypoints, current_index)
    for offset in range(1, min(progress_search_count, len(waypoints) - 1) + 1):
        index = (current_index + offset) % len(waypoints)
        candidate = _project_segment(pose, waypoints, index)
        if candidate.distance_squared < best.distance_squared:
            best = candidate
            best_index = index

    right = right_vector(best.tangent_yaw)
    dx = pose.x - best.projected.x
    dz = pose.z - best.projected.z
    cross_track_error = dx * right.x + dz * right.z
    return PathReference(
        index=best_index,
        projected=best.projected,
        tangent_yaw=best.tangent_yaw,
        cross_track_error=cross_track_error,
        curvature=_signed_curvature(best_index, waypoints, curvature_sample_span),
    )


@dataclass(frozen=True)
class _SegmentProjection:
    projected: Point
    tangent_yaw: float
    distance_squared: float


def _project_segment(pose: Pose, waypoints: list[Point], index: int) -> _SegmentProjection:
    start = waypoints[index]
    end = waypoints[(index + 1) % len(waypoints)]
    dx = end.x - start.x
    dz = end.z - start.z
    length_squared = dx * dx + dz * dz
    projection = 0.0
    if length_squared > 0.0:
        projection = clamp(
            ((pose.x - start.x) * dx + (pose.z - start.z) * dz) / length_squared,
            0.0,
            1.0,
        )
    projected = Point(start.x + dx * projection, start.z + dz * projection)
    return _SegmentProjection(
        projected=projected,
        tangent_yaw=heading_from_points(start.x, start.z, end.x, end.z),
        distance_squared=(pose.x - projected.x) ** 2 + (pose.z - projected.z) ** 2,
    )


def _signed_curvature(index: int, waypoints: list[Point], sample_span: int) -> float:
    if len(waypoints) < 3:
        return 0.0
    span = max(1, min(sample_span, max(1, (len(waypoints) - 1) // 2)))
    previous = waypoints[(index - span) % len(waypoints)]
    current = waypoints[index]
    next_point = waypoints[(index + span) % len(waypoints)]
    inbound = heading_from_points(previous.x, previous.z, current.x, current.z)
    outbound = heading_from_points(current.x, current.z, next_point.x, next_point.z)
    heading_delta = wrap_to_pi(outbound - inbound)
    length = 0.0
    for offset in range(-span, span):
        first = waypoints[(index + offset) % len(waypoints)]
        second = waypoints[(index + offset + 1) % len(waypoints)]
        length += math.hypot(second.x - first.x, second.z - first.z)
    return heading_delta / max(0.001, length)
