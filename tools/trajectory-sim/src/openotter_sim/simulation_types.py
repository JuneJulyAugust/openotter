from dataclasses import dataclass


@dataclass(frozen=True)
class Pose:
    x: float
    z: float
    yaw: float


@dataclass(frozen=True)
class Command:
    steering: float
    throttle: float
    index: int
