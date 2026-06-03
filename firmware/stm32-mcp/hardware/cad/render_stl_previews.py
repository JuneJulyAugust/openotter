#!/usr/bin/env python3
"""Render OpenSCAD-exported STL parts into documentation PNG previews."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from mpl_toolkits.mplot3d.art3d import Poly3DCollection


def read_stl(path: Path) -> np.ndarray:
    data = path.read_bytes()
    if len(data) >= 84:
        tri_count = struct.unpack_from("<I", data, 80)[0]
        expected_size = 84 + tri_count * 50
        if expected_size == len(data):
            triangles = []
            offset = 84
            for _ in range(tri_count):
                offset += 12
                vertices = []
                for _ in range(3):
                    vertices.append(list(struct.unpack_from("<fff", data, offset)))
                    offset += 12
                triangles.append(vertices)
                offset += 2
            return np.array(triangles, dtype=float)

    return read_ascii_stl(path)


def read_ascii_stl(path: Path) -> np.ndarray:
    vertices: list[list[float]] = []
    triangles: list[list[list[float]]] = []
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        words = line.strip().split()
        if len(words) == 4 and words[0] == "vertex":
            vertices.append([float(words[1]), float(words[2]), float(words[3])])
            if len(vertices) == 3:
                triangles.append(vertices)
                vertices = []
    if not triangles:
        raise ValueError(f"No ASCII STL triangles found in {path}")
    return np.array(triangles, dtype=float)


def add_mesh(ax, triangles: np.ndarray, color: str, alpha: float, offset: tuple[float, float, float]) -> np.ndarray:
    shifted = triangles + np.array(offset)
    mesh = Poly3DCollection(shifted, facecolor=color, edgecolor="#334155", linewidths=0.18, alpha=alpha)
    ax.add_collection3d(mesh)
    return shifted.reshape(-1, 3)


def set_equal_axes(ax, points: np.ndarray) -> None:
    mins = points.min(axis=0)
    maxs = points.max(axis=0)
    center = (mins + maxs) / 2.0
    span = max(maxs - mins) * 0.62
    ax.set_xlim(center[0] - span, center[0] + span)
    ax.set_ylim(center[1] - span, center[1] + span)
    ax.set_zlim(max(0, center[2] - span * 0.6), center[2] + span)


def add_fov_cone(ax, origin: tuple[float, float, float], height: float, radius: float, color: str) -> None:
    theta = np.linspace(0, 2 * np.pi, 44)
    z = np.linspace(0, height, 8)
    theta_grid, z_grid = np.meshgrid(theta, z)
    r_grid = (z_grid / height) * radius + 5.0
    x = origin[0] + r_grid * np.cos(theta_grid)
    y = origin[1] + r_grid * np.sin(theta_grid)
    zz = origin[2] + z_grid
    ax.plot_surface(x, y, zz, color=color, alpha=0.12, linewidth=0)


def add_harness(ax, start_y: float, z: float, length: float) -> None:
    colors = ["#dc2626", "#111827", "#2563eb", "#16a34a", "#f59e0b"]
    for i, color in enumerate(colors):
        x = -5.0 + i * 2.5
        ax.plot([x, x], [start_y, start_y + length], [z, z + 1.5], color=color, linewidth=2.8)


def render_case(case_dir: Path, output: Path, title: str, mini: bool) -> None:
    stl_dir = case_dir / "stl"
    prefix = "satel_vl53l8_mini" if mini else "satel_vl53l8_full_carrier"
    files = [
        (stl_dir / f"{prefix}_mount_plate.stl", "#9ca3af", 0.45, (0, 0, 0)),
        (stl_dir / f"{prefix}_case_base.stl", "#38bdf8", 0.74, (0, 0, 4 if mini else 5)),
        (stl_dir / f"{prefix}_case_lid.stl", "#7dd3fc", 0.55, (0, 0, 18 if mini else 25)),
    ]

    fig = plt.figure(figsize=(12, 8), dpi=180)
    ax = fig.add_subplot(111, projection="3d")
    all_points = []
    for path, color, alpha, offset in files:
        tris = read_stl(path)
        all_points.append(add_mesh(ax, tris, color, alpha, offset))

    points = np.vstack(all_points)
    set_equal_axes(ax, points)

    sensor_z = 22 if mini else 32
    add_fov_cone(ax, (0, -7 if mini else -20, sensor_z), 34 if mini else 42, 35 if mini else 45, "#0ea5e9")
    add_harness(ax, 16 if mini else 34, 9 if mini else 14, 34 if mini else 46)

    ax.text(0, -34 if mini else -50, sensor_z + 20, "FOV keepout", color="#075985", ha="center")
    ax.text(0, 44 if mini else 62, 18 if mini else 24, "harness exit / strain relief", color="#111827", ha="center")
    ax.text(0, 0, 2, "mount plate / car side", color="#374151", ha="center")

    ax.view_init(elev=27, azim=-42)
    ax.set_title(title, pad=24)
    ax.set_axis_off()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, bbox_inches="tight", pad_inches=0.25)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()

    full = args.root / "satel-vl53l8-full-carrier-case"
    mini = args.root / "satel-vl53l8-mini-case"
    render_case(
        full,
        full / "renders" / "satel_vl53l8_full_carrier_stl_preview.png",
        "SATEL-VL53L8 Full Carrier Case - OpenSCAD STL Preview",
        mini=False,
    )
    render_case(
        mini,
        mini / "renders" / "satel_vl53l8_mini_stl_preview.png",
        "SATEL-VL53L8 Mini-PCB Case - OpenSCAD STL Preview",
        mini=True,
    )


if __name__ == "__main__":
    main()
