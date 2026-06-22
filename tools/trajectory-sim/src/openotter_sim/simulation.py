import math
from dataclasses import dataclass
from typing import Protocol

from .geometry import wrap_to_pi
from .path_reference import project_path
from .simulation_types import Command, Pose
from .trajectory import Point


class Controller(Protocol):
    def command(self, pose: Pose, waypoints: list[Point], current_index: int, speed_mps: float) -> Command:
        ...


@dataclass(frozen=True)
class SimulationResult:
    poses: list[Pose]
    commands: list[Command]
    final_index: int
    max_cross_track_error: float


def simulate(
    controller: Controller,
    waypoints: list[Point],
    initial_pose: Pose,
    steps: int = 320,
    dt: float = 0.1,
    yaw_gain: float = 0.7,
    throttle_to_mps: float = 0.65,
) -> SimulationResult:
    pose = initial_pose
    speed_mps = 0.0
    index = 0
    poses = [pose]
    commands: list[Command] = []
    max_error = 0.0

    for _ in range(steps):
        command = controller.command(pose, waypoints, index, speed_mps)
        commands.append(command)
        index = command.index
        reference = project_path(pose, waypoints, index)
        max_error = max(max_error, abs(reference.cross_track_error))

        speed_mps = max(0.0, command.throttle) * throttle_to_mps
        yaw = wrap_to_pi(pose.yaw - command.steering * yaw_gain * dt)
        pose = Pose(
            x=pose.x + math.cos(yaw) * speed_mps * dt,
            z=pose.z - math.sin(yaw) * speed_mps * dt,
            yaw=yaw,
        )
        poses.append(pose)

    return SimulationResult(
        poses=poses,
        commands=commands,
        final_index=index,
        max_cross_track_error=max_error,
    )


__all__ = ["Command", "Pose", "SimulationResult", "simulate"]
