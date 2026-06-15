"""OpenOtter trajectory-following simulation package."""

from .controllers import LQRTrack, TangentTrack
from .simulation import Pose, SimulationResult, simulate
from .trajectory import FigureEightConfig, Point, figure_eight_waypoints

__all__ = [
    "FigureEightConfig",
    "LQRTrack",
    "Point",
    "Pose",
    "SimulationResult",
    "TangentTrack",
    "figure_eight_waypoints",
    "simulate",
]
