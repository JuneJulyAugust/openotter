import struct
import tempfile
import unittest
from pathlib import Path

from openotter_sim.cli import write_png
from openotter_sim.controllers import LQRTrack, TangentTrack
from openotter_sim.simulation import Pose, simulate
from openotter_sim.trajectory import FigureEightConfig, figure_eight_waypoints


class CliPlotTests(unittest.TestCase):
    def test_write_png_saves_two_panel_controller_comparison(self) -> None:
        waypoints = figure_eight_waypoints(
            FigureEightConfig(segment_count=120, length=3.2, width=1.6)
        )
        results = [
            ("TangentTrack", simulate(TangentTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=30)),
            ("LQRTrack", simulate(LQRTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=30)),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            output = Path(tmpdir) / "figure8-comparison.png"

            write_png(str(output), waypoints, results)

            data = output.read_bytes()

        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", data[16:24])
        self.assertGreater(
            width,
            height,
            "two controller subplots should produce a wide comparison PNG",
        )
        self.assertGreaterEqual(width, 1600)
        self.assertGreaterEqual(height, 700)


if __name__ == "__main__":
    unittest.main()
