import math
import unittest

from openotter_sim.trajectory import FigureEightConfig, figure_eight_waypoints


class FigureEightTrajectoryTests(unittest.TestCase):
    def test_app_map_horizontal_axis_is_local_z(self) -> None:
        config = FigureEightConfig(segment_count=240, length=3.2, width=1.6)
        waypoints = figure_eight_waypoints(config)

        max_abs_x = max(abs(point.x) for point in waypoints)
        max_abs_z = max(abs(point.z) for point in waypoints)

        self.assertAlmostEqual(max_abs_x, config.width / 2.0, delta=0.03)
        self.assertAlmostEqual(max_abs_z, config.length / 2.0, delta=0.03)

    def test_start_and_halfway_cross_center(self) -> None:
        config = FigureEightConfig(segment_count=240, length=3.2, width=1.6)
        waypoints = figure_eight_waypoints(config)

        self.assertAlmostEqual(waypoints[0].x, 0.0, delta=1e-6)
        self.assertAlmostEqual(waypoints[0].z, 0.0, delta=1e-6)
        self.assertGreater(waypoints[1].x, 0.0)
        self.assertGreater(waypoints[1].z, 0.0)
        self.assertAlmostEqual(waypoints[120].x, 0.0, delta=0.03)
        self.assertAlmostEqual(waypoints[120].z, 0.0, delta=0.03)

    def test_waypoints_are_arc_length_resampled(self) -> None:
        config = FigureEightConfig(segment_count=240, length=3.2, width=1.6)
        waypoints = figure_eight_waypoints(config)
        distances = [
            math.hypot(
                waypoints[(index + 1) % len(waypoints)].x - point.x,
                waypoints[(index + 1) % len(waypoints)].z - point.z,
            )
            for index, point in enumerate(waypoints)
        ]

        average = sum(distances) / len(distances)
        self.assertLess(max(abs(distance - average) for distance in distances), average * 0.35)


if __name__ == "__main__":
    unittest.main()
