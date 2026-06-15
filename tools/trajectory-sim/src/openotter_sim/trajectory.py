import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Point:
    x: float
    z: float


@dataclass(frozen=True)
class FigureEightConfig:
    segment_count: int = 240
    length: float = 3.2
    width: float = 1.6


def figure_eight_waypoints(config: FigureEightConfig = FigureEightConfig()) -> list[Point]:
    segment_count = max(12, int(config.segment_count))
    dense_count = max(segment_count * 8, 720)
    dense = _scaled_dense_points(dense_count, config)
    cumulative = _cumulative_lengths(dense)
    total = cumulative[-1]

    waypoints: list[Point] = []
    segment_index = 1
    for waypoint_index in range(segment_count):
        target_distance = total * waypoint_index / segment_count
        while segment_index < len(cumulative) - 1 and cumulative[segment_index] < target_distance:
            segment_index += 1

        previous_index = max(0, segment_index - 1)
        segment_length = cumulative[segment_index] - cumulative[previous_index]
        fraction = 0.0 if segment_length <= 0 else (
            target_distance - cumulative[previous_index]
        ) / segment_length
        previous = dense[previous_index]
        next_point = dense[segment_index]
        waypoints.append(
            Point(
                x=previous.x + (next_point.x - previous.x) * fraction,
                z=previous.z + (next_point.z - previous.z) * fraction,
            )
        )
    return waypoints


def _scaled_dense_points(count: int, config: FigureEightConfig) -> list[Point]:
    raw = [_raw_bernoulli_point(2.0 * math.pi * index / count) for index in range(count + 1)]
    max_abs_x = max(abs(point.x) for point in raw)
    max_abs_z = max(abs(point.z) for point in raw)
    x_scale = config.width / 2.0
    z_scale = config.length / 2.0
    return [
        Point(
            x=point.z / max_abs_z * x_scale,
            z=point.x / max_abs_x * z_scale,
        )
        for point in raw
    ]


def _raw_bernoulli_point(t: float) -> Point:
    theta = t + math.pi / 2.0
    sin_theta = math.sin(theta)
    cos_theta = math.cos(theta)
    denominator = 1.0 + sin_theta * sin_theta
    return Point(
        x=-cos_theta / denominator,
        z=-(sin_theta * cos_theta) / denominator,
    )


def _cumulative_lengths(points: list[Point]) -> list[float]:
    cumulative = [0.0] * len(points)
    for index in range(1, len(points)):
        previous = points[index - 1]
        current = points[index]
        cumulative[index] = cumulative[index - 1] + math.hypot(
            current.x - previous.x,
            current.z - previous.z,
        )
    return cumulative
