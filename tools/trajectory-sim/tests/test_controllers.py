import unittest

from openotter_sim.controllers import LQRTrack, TangentTrack
from openotter_sim.geometry import right_vector
from openotter_sim.path_reference import project_path
from openotter_sim.simulation import Pose, simulate
from openotter_sim.trajectory import FigureEightConfig, figure_eight_waypoints


class ControllerTests(unittest.TestCase):
    def test_tangent_track_and_lqr_track_make_progress(self) -> None:
        waypoints = figure_eight_waypoints(FigureEightConfig(segment_count=240, length=3.2, width=1.6))

        tangent = simulate(
            TangentTrack(max_throttle=0.4),
            waypoints,
            initial_pose=Pose(x=0.0, z=0.0, yaw=0.0),
            steps=260,
        )
        lqr = simulate(
            LQRTrack(max_throttle=0.4),
            waypoints,
            initial_pose=Pose(x=0.0, z=0.0, yaw=0.0),
            steps=260,
        )

        self.assertGreater(tangent.final_index, 40)
        self.assertGreater(lqr.final_index, 40)
        self.assertLess(tangent.max_cross_track_error, 0.55)
        self.assertLess(lqr.max_cross_track_error, 0.55)

    def test_lqr_track_speed_feedback_reduces_throttle_when_fast(self) -> None:
        waypoints = figure_eight_waypoints(FigureEightConfig(segment_count=240, length=3.2, width=1.6))
        controller = LQRTrack(max_throttle=0.4)

        slow = controller.command(Pose(x=0.0, z=0.0, yaw=0.0), waypoints, 0, speed_mps=0.05)
        fast = controller.command(Pose(x=0.0, z=0.0, yaw=0.0), waypoints, 0, speed_mps=0.40)

        self.assertGreater(slow.throttle, fast.throttle)
        self.assertGreaterEqual(slow.throttle, 0.0)
        self.assertLessEqual(slow.throttle, 0.4)
        self.assertGreaterEqual(fast.throttle, 0.0)
        self.assertLessEqual(fast.throttle, 0.4)

    def test_lqr_track_lateral_error_signs_survive_reference_reacquire(self) -> None:
        waypoints = figure_eight_waypoints(FigureEightConfig(segment_count=240, length=3.2, width=1.6))
        controller = LQRTrack(max_throttle=0.4)
        controller.command(Pose(x=0.0, z=0.0, yaw=0.0), waypoints, 0, speed_mps=0.2)

        right = self._path_right_vector(waypoints, index=30)
        reference = project_path(Pose(waypoints[30].x, waypoints[30].z, 0.0), waypoints, 30, 0, 3)

        right_of_path = controller.command(
            Pose(
                reference.projected.x + right.x * 0.2,
                reference.projected.z + right.z * 0.2,
                reference.tangent_yaw,
            ),
            waypoints,
            30,
            speed_mps=0.2,
        )

        controller = LQRTrack(max_throttle=0.4)
        controller.command(Pose(x=0.0, z=0.0, yaw=0.0), waypoints, 0, speed_mps=0.2)
        left_of_path = controller.command(
            Pose(
                reference.projected.x - right.x * 0.2,
                reference.projected.z - right.z * 0.2,
                reference.tangent_yaw,
            ),
            waypoints,
            30,
            speed_mps=0.2,
        )

        self.assertLess(right_of_path.steering, -0.02)
        self.assertGreater(left_of_path.steering, 0.02)

    def _path_right_vector(self, waypoints, index):
        reference = project_path(Pose(waypoints[index].x, waypoints[index].z, 0.0), waypoints, index, 0, 3)
        return right_vector(reference.tangent_yaw)


if __name__ == "__main__":
    unittest.main()
