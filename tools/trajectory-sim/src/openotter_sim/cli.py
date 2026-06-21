import argparse
import warnings
from pathlib import Path

from .controllers import LQRTrack, TangentTrack
from .simulation import Pose, SimulationResult, simulate
from .trajectory import FigureEightConfig, Point, figure_eight_waypoints


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenOtter figure-eight controller simulator")
    parser.add_argument("--controller", choices=["tangent", "lqr", "both"], default="both")
    parser.add_argument("--output", default="figure8-sim.png")
    parser.add_argument("--steps", type=int, default=320)
    args = parser.parse_args()

    waypoints = figure_eight_waypoints(FigureEightConfig())
    results: list[tuple[str, SimulationResult]] = []
    if args.controller in ("tangent", "both"):
        results.append((
            "TangentTrack",
            simulate(TangentTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=args.steps),
        ))
    if args.controller in ("lqr", "both"):
        results.append((
            "LQRTrack",
            simulate(LQRTrack(), waypoints, Pose(0.0, 0.0, 0.0), steps=args.steps),
        ))

    write_png(args.output, waypoints, results)
    for name, result in results:
        print(
            f"{name}: final_index={result.final_index} "
            f"max_cross_track_error={result.max_cross_track_error:.3f}m"
        )
    print(f"Wrote {args.output}")


def write_png(
    path: str,
    waypoints: list[Point],
    results: list[tuple[str, SimulationResult]],
) -> None:
    output = Path(path)
    if output.suffix.lower() != ".png":
        raise ValueError("--output must end with .png")
    output.parent.mkdir(parents=True, exist_ok=True)

    try:
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=DeprecationWarning)
            import matplotlib

            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
    except ImportError as exc:
        raise RuntimeError(
            "matplotlib is required for trajectory plots. Install with "
            "`python3 -m pip install -e .` from tools/trajectory-sim."
        ) from exc

    panel_count = max(1, len(results))
    figure_width = 8.4 * panel_count
    figure_height = 7.0
    fig, axes = plt.subplots(1, panel_count, figsize=(figure_width, figure_height), squeeze=False)

    ref_z = [point.z for point in waypoints + [waypoints[0]]]
    ref_x = [point.x for point in waypoints + [waypoints[0]]]
    colors = ["#087ea4", "#16a34a", "#7c3aed", "#ea580c"]

    for axis, (name, result), color in zip(axes[0], results, colors):
        trace_z = [pose.z for pose in result.poses]
        trace_x = [pose.x for pose in result.poses]

        axis.plot(ref_z, ref_x, color="#dc2626", linewidth=9, alpha=0.28, label="reference")
        axis.plot(ref_z, ref_x, color="#b91c1c", linewidth=2.0, alpha=0.85)
        axis.plot(trace_z, trace_x, color=color, linewidth=2.8, label=name)
        if trace_z and trace_x:
            axis.scatter(trace_z[0], trace_x[0], color="#111827", s=42, zorder=5, label="start")
            axis.scatter(trace_z[-1], trace_x[-1], color=color, s=56, zorder=6, edgecolor="white")

        axis.axhline(0, color="#9ca3af", linewidth=1.0)
        axis.axvline(0, color="#9ca3af", linewidth=1.0)
        axis.set_aspect("equal", adjustable="box")
        axis.grid(True, color="#e5e7eb", linewidth=0.8)
        axis.set_title(name, fontsize=15, weight="bold")
        axis.set_xlabel("app-map horizontal z (m)")
        axis.set_ylabel("app-map vertical x (m)")
        axis.text(
            0.02,
            0.98,
            f"max error: {result.max_cross_track_error:.2f} m\n"
            f"final index: {result.final_index}",
            transform=axis.transAxes,
            va="top",
            ha="left",
            fontsize=10,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="#f9fafb", edgecolor="#d1d5db"),
        )
        axis.legend(loc="lower right")

    fig.suptitle(
        "OpenOtter figure-eight trajectory simulation\n"
        "App map convention: +X forward/up, +Z right/horizontal",
        fontsize=17,
        weight="bold",
    )
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(output, dpi=180, format="png", bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
