import argparse
from typing import Union

from .controllers import LQRTrack, TangentTrack
from .simulation import Pose, SimulationResult, simulate
from .trajectory import FigureEightConfig, Point, figure_eight_waypoints


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenOtter figure-eight controller simulator")
    parser.add_argument("--controller", choices=["tangent", "lqr", "both"], default="both")
    parser.add_argument("--output", default="figure8-sim.svg")
    parser.add_argument("--steps", type=int, default=320)
    args = parser.parse_args()

    waypoints = figure_eight_waypoints(FigureEightConfig())
    results: list[tuple[str, SimulationResult]] = []
    if args.controller in ("tangent", "both"):
        results.append(("TangentTrack", simulate(TangentTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=args.steps)))
    if args.controller in ("lqr", "both"):
        results.append(("LQRTrack", simulate(LQRTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=args.steps)))

    write_svg(args.output, waypoints, results)
    for name, result in results:
        print(
            f"{name}: final_index={result.final_index} "
            f"max_cross_track_error={result.max_cross_track_error:.3f}m"
        )
    print(f"Wrote {args.output}")


def write_svg(path: str, waypoints: list[Point], results: list[tuple[str, SimulationResult]]) -> None:
    scale = 170.0
    width = 900
    height = 620
    center_x = width / 2.0
    center_y = height / 2.0

    def screen(point: Union[Point, Pose]) -> tuple[float, float]:
        return center_x + point.z * scale, center_y - point.x * scale

    def polyline(points: list[Union[Point, Pose]], color: str, width_px: float, opacity: float = 1.0) -> str:
        coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in (screen(point) for point in points))
        return (
            f'<polyline points="{coords}" fill="none" stroke="{color}" '
            f'stroke-width="{width_px}" stroke-linecap="round" '
            f'stroke-linejoin="round" opacity="{opacity}"/>'
        )

    colors = ["#087ea4", "#16a34a"]
    lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 620" role="img">',
        '<rect width="900" height="620" fill="#fbfbfd"/>',
        '<text x="28" y="42" font-family="Arial" font-size="22" fill="#111827">'
        "OpenOtter figure-eight simulation</text>",
        '<text x="28" y="72" font-family="Arial" font-size="15" fill="#4b5563">'
        "App map: +X forward/up, +Z right/horizontal. Red = reference.</text>",
        f'<line x1="0" y1="{center_y}" x2="900" y2="{center_y}" stroke="#111827" stroke-width="1.5"/>',
        f'<line x1="{center_x}" y1="0" x2="{center_x}" y2="620" stroke="#111827" stroke-width="1.5"/>',
        polyline(waypoints + [waypoints[0]], "#dc2626", 8, 0.28),
    ]
    for index, (name, result) in enumerate(results):
        color = colors[index % len(colors)]
        lines.append(polyline(result.poses, color, 3, 0.95))
        lines.append(
            f'<text x="28" y="{104 + index * 24}" font-family="Arial" '
            f'font-size="16" fill="{color}">{name}: max error '
            f'{result.max_cross_track_error:.2f} m, final index {result.final_index}</text>'
        )
    lines.append("</svg>")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


if __name__ == "__main__":
    main()
