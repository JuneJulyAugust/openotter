#!/usr/bin/env python3
"""Generate SATEL-VL53L8 bottom-mount case CAD artifacts with CadQuery.

Coordinate convention:
  Z=0 is the flat case bottom that mounts to the car.
  +Z is the ToF optical direction through the lid aperture.
  +Y is the harness exit direction.
"""

from __future__ import annotations

import argparse
import os
import struct
from dataclasses import dataclass
from pathlib import Path

os.environ.setdefault("XDG_CACHE_HOME", "/private/tmp/openotter-cad-cache")

import cadquery as cq
from cadquery import exporters
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
from mpl_toolkits.mplot3d.art3d import Poly3DCollection


@dataclass(frozen=True)
class CaseConfig:
    name: str
    title: str
    out_dir: Path
    board_w: float
    board_h: float
    board_t: float
    sensor_x: float
    sensor_y: float
    board_center_y: float
    component_clearance_z: float
    header_clearance_z: float
    header_bay_h: float
    optic_opening: float
    cable_slot_w: float
    cable_slot_z: float
    strain_bar_w: float
    strain_bar_h: float
    ear_w: float
    ear_h: float
    screw_d: float
    screw_head_d: float
    corner_r: float
    body_color: str
    fov_color: str


BOARD_CLEARANCE = 0.8
FLOOR_T = 1.6
WALL_T = 1.9
LID_T = 1.5
EDGE_RAIL_W = 0.8
EDGE_RAIL_H = 1.2
EDGE_STOP_H = 1.2
RETAINER_PAD_W = 4.0
RETAINER_PAD_L = 7.0
RETAINER_PAD_H = 0.9
TIE_SLOT_W = 2.0
TIE_SLOT_L = 8.0
LID_GAP = 2.0


def rounded_box(w: float, h: float, z: float, radius: float) -> cq.Workplane:
    box = cq.Workplane("XY").rect(w, h).extrude(z)
    if radius > 0:
        box = box.edges("|Z").fillet(radius)
    return box


def box(w: float, h: float, z: float, x: float = 0, y: float = 0, zbase: float = 0) -> cq.Workplane:
    return cq.Workplane("XY").box(w, h, z, centered=(True, True, False)).translate((x, y, zbase))


def cyl(d: float, h: float, x: float = 0, y: float = 0, zbase: float = 0) -> cq.Workplane:
    return cq.Workplane("XY").circle(d / 2.0).extrude(h).translate((x, y, zbase))


def case_dimensions(cfg: CaseConfig) -> dict[str, float]:
    inner_w = cfg.board_w + 2 * BOARD_CLEARANCE
    inner_h = cfg.board_h + 2 * BOARD_CLEARANCE
    outer_w = inner_w + 2 * WALL_T
    outer_h = inner_h + 2 * WALL_T
    body_z = FLOOR_T + cfg.board_t + max(cfg.component_clearance_z, cfg.header_clearance_z)
    return {
        "inner_w": inner_w,
        "inner_h": inner_h,
        "outer_w": outer_w,
        "outer_h": outer_h,
        "body_z": body_z,
    }


def side_ears(cfg: CaseConfig, z: float, dims: dict[str, float]) -> cq.Workplane:
    outer_w = dims["outer_w"]
    left = rounded_box(cfg.ear_w, cfg.ear_h, z, 1.8).translate((-(outer_w / 2 + cfg.ear_w / 2 - 0.05), 0, 0))
    right = rounded_box(cfg.ear_w, cfg.ear_h, z, 1.8).translate(((outer_w / 2 + cfg.ear_w / 2 - 0.05), 0, 0))
    return left.union(right)


def screw_cuts(cfg: CaseConfig, h: float, dims: dict[str, float]) -> cq.Workplane:
    outer_w = dims["outer_w"]
    cuts = None
    for x in [-(outer_w / 2 + cfg.ear_w / 2), outer_w / 2 + cfg.ear_w / 2]:
        hole = cyl(cfg.screw_d, h, x=x, zbase=-0.5)
        cuts = hole if cuts is None else cuts.union(hole)
    return cuts


def screw_head_cuts(cfg: CaseConfig, dims: dict[str, float]) -> cq.Workplane:
    outer_w = dims["outer_w"]
    body_z = dims["body_z"]
    cuts = None
    for x in [-(outer_w / 2 + cfg.ear_w / 2), outer_w / 2 + cfg.ear_w / 2]:
        relief = cyl(cfg.screw_head_d, 1.4, x=x, zbase=body_z - 1.0)
        cuts = relief if cuts is None else cuts.union(relief)
    return cuts


def make_base(cfg: CaseConfig) -> cq.Workplane:
    dims = case_dimensions(cfg)
    inner_w = dims["inner_w"]
    inner_h = dims["inner_h"]
    outer_w = dims["outer_w"]
    outer_h = dims["outer_h"]
    body_z = dims["body_z"]

    base = rounded_box(outer_w, outer_h, body_z, cfg.corner_r).union(side_ears(cfg, body_z, dims))
    base = base.cut(box(inner_w, inner_h, body_z + 0.8, y=cfg.board_center_y, zbase=FLOOR_T))
    base = base.cut(box(cfg.cable_slot_w, WALL_T + 0.7, cfg.cable_slot_z, y=outer_h / 2 + 0.1, zbase=FLOOR_T))

    if cfg.header_bay_h > 0:
        base = base.cut(
            box(
                inner_w,
                cfg.header_bay_h,
                cfg.header_clearance_z + 0.6,
                y=cfg.board_center_y + inner_h / 2 - cfg.header_bay_h / 2,
                zbase=FLOOR_T + cfg.board_t,
            )
        )

    for x in [-cfg.strain_bar_w / 2 - 2.0, cfg.strain_bar_w / 2 + 2.0]:
        base = base.cut(box(TIE_SLOT_W, TIE_SLOT_L, FLOOR_T + 0.6, x=x, y=outer_h / 2 - WALL_T - 5.0, zbase=-0.2))

    base = base.cut(screw_cuts(cfg, body_z + 2.0, dims))
    base = base.cut(screw_head_cuts(cfg, dims))

    base = base.union(box(cfg.strain_bar_w, cfg.strain_bar_h, cfg.strain_bar_h, y=outer_h / 2 - WALL_T - 2.0, zbase=FLOOR_T + 0.4))

    for x in [-(inner_w / 2 - 2.2), inner_w / 2 - 2.2]:
        for y in [cfg.board_center_y - inner_h / 2 + 4.0, cfg.board_center_y + inner_h / 2 - 4.0]:
            base = base.union(box(2.4, 5.0, 0.9, x=x, y=y, zbase=FLOOR_T))

    usable_rail_h = max(4.0, cfg.board_h - cfg.header_bay_h - 8.0)
    rail_y = cfg.board_center_y - cfg.header_bay_h / 2 - 3.0 if cfg.header_bay_h > 0 else cfg.board_center_y
    for x in [-(cfg.board_w / 2 + BOARD_CLEARANCE / 2), cfg.board_w / 2 + BOARD_CLEARANCE / 2]:
        base = base.union(box(EDGE_RAIL_W, usable_rail_h, EDGE_RAIL_H, x=x, y=rail_y, zbase=FLOOR_T))

    base = base.union(
        box(
            cfg.board_w - 5.0,
            EDGE_RAIL_W,
            EDGE_STOP_H,
            y=cfg.board_center_y - cfg.board_h / 2 - BOARD_CLEARANCE / 2,
            zbase=FLOOR_T,
        )
    )
    return base


def make_lid(cfg: CaseConfig) -> cq.Workplane:
    dims = case_dimensions(cfg)
    inner_w = dims["inner_w"]
    inner_h = dims["inner_h"]
    outer_w = dims["outer_w"]
    outer_h = dims["outer_h"]

    lid = rounded_box(outer_w, outer_h, LID_T, cfg.corner_r).union(side_ears(cfg, LID_T, dims))
    lid = lid.cut(box(cfg.optic_opening, cfg.optic_opening, LID_T + 1.0, x=cfg.sensor_x, y=cfg.board_center_y + cfg.sensor_y, zbase=-0.2))
    lid = lid.cut(box(cfg.cable_slot_w, WALL_T + 0.7, 2.2, y=outer_h / 2 + 0.1, zbase=0.4))
    lid = lid.cut(screw_cuts(cfg, LID_T + RETAINER_PAD_H + 2.0, dims))

    lip = rounded_box(inner_w - 0.6, inner_h - 0.6, 0.6, 1.0).cut(rounded_box(inner_w - 3.4, inner_h - 3.4, 0.8, 0.8))
    lid = lid.union(lip.translate((0, cfg.board_center_y, -0.55)))

    pad_y_values = [
        cfg.board_center_y - cfg.board_h / 2 + 6.0,
        cfg.board_center_y + cfg.board_h / 2 - max(6.0, cfg.header_bay_h + 5.0),
    ]
    for x in [-(cfg.board_w / 2 - 3.0), cfg.board_w / 2 - 3.0]:
        for y in pad_y_values:
            lid = lid.union(box(RETAINER_PAD_W, RETAINER_PAD_L, RETAINER_PAD_H, x=x, y=y, zbase=-RETAINER_PAD_H))

    return lid


def make_board_preview(cfg: CaseConfig) -> cq.Workplane:
    board = box(cfg.board_w, cfg.board_h, cfg.board_t, y=cfg.board_center_y, zbase=FLOOR_T)
    sensor = box(6.4, 3.0, 1.8, x=cfg.sensor_x, y=cfg.board_center_y + cfg.sensor_y, zbase=FLOOR_T + cfg.board_t)
    return board.union(sensor)


def normalize_step(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    normalized = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    path.write_text(normalized, encoding="utf-8")


def export_case(cfg: CaseConfig) -> None:
    base = make_base(cfg)
    lid = make_lid(cfg)
    dims = case_dimensions(cfg)

    stl_dir = cfg.out_dir / "stl"
    step_dir = cfg.out_dir / "step"
    stl_dir.mkdir(parents=True, exist_ok=True)
    step_dir.mkdir(parents=True, exist_ok=True)

    base_stl = stl_dir / f"{cfg.name}_base.stl"
    lid_stl = stl_dir / f"{cfg.name}_lid.stl"
    base_step = step_dir / f"{cfg.name}_base.step"
    lid_step = step_dir / f"{cfg.name}_lid.step"
    assembly_step = step_dir / f"{cfg.name}_assembly.step"

    exporters.export(base, str(base_stl))
    exporters.export(lid, str(lid_stl))
    exporters.export(base, str(base_step))
    exporters.export(lid, str(lid_step))
    normalize_step(base_step)
    normalize_step(lid_step)

    assembly = cq.Assembly(name=f"{cfg.name}_assembly")
    assembly.add(base, name="bottom_mount_base", color=cq.Color(0.0, 0.55, 0.95, 0.55))
    assembly.add(
        lid,
        name="aperture_lid",
        loc=cq.Location(cq.Vector(0, 0, dims["body_z"] + LID_GAP)),
        color=cq.Color(0.55, 0.85, 1.0, 0.45),
    )
    assembly.add(
        make_board_preview(cfg),
        name="board_preview",
        loc=cq.Location(cq.Vector(0, 0, 0)),
        color=cq.Color(0.0, 0.2, 0.85, 0.35),
    )
    assembly.save(str(assembly_step))
    normalize_step(assembly_step)


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
        raise ValueError(f"No STL triangles found in {path}")
    return np.array(triangles, dtype=float)


def add_mesh(ax, triangles: np.ndarray, color: str, alpha: float, offset: tuple[float, float, float]) -> np.ndarray:
    shifted = triangles + np.array(offset)
    mesh = Poly3DCollection(shifted, facecolor=color, edgecolor="#334155", linewidths=0.16, alpha=alpha)
    ax.add_collection3d(mesh)
    return shifted.reshape(-1, 3)


def set_equal_axes(ax, points: np.ndarray) -> None:
    mins = points.min(axis=0)
    maxs = points.max(axis=0)
    center = (mins + maxs) / 2.0
    span = max(maxs - mins) * 0.66
    ax.set_xlim(center[0] - span, center[0] + span)
    ax.set_ylim(center[1] - span, center[1] + span)
    ax.set_zlim(max(-4.0, center[2] - span * 0.55), center[2] + span)


def add_fov_cone(ax, cfg: CaseConfig, dims: dict[str, float]) -> None:
    origin = (cfg.sensor_x, cfg.board_center_y + cfg.sensor_y, dims["body_z"] + LID_GAP + LID_T + 0.4)
    height = 42.0 if cfg.header_bay_h > 0 else 34.0
    radius = 44.0 if cfg.header_bay_h > 0 else 35.0
    theta = np.linspace(0, 2 * np.pi, 56)
    z = np.linspace(0, height, 10)
    theta_grid, z_grid = np.meshgrid(theta, z)
    r_grid = (z_grid / height) * radius + cfg.optic_opening / 2.0
    x = origin[0] + r_grid * np.cos(theta_grid)
    y = origin[1] + r_grid * np.sin(theta_grid)
    zz = origin[2] + z_grid
    ax.plot_surface(x, y, zz, color=cfg.fov_color, alpha=0.13, linewidth=0)


def add_harness(ax, cfg: CaseConfig, dims: dict[str, float]) -> None:
    colors = ["#dc2626", "#111827", "#2563eb", "#16a34a", "#f59e0b"]
    start_y = dims["outer_h"] / 2 - 1.0
    start_z = FLOOR_T + 3.0
    for i, color in enumerate(colors):
        x = -5.0 + i * 2.5
        ax.plot([x, x], [start_y, start_y + 40.0], [start_z, start_z + 1.5], color=color, linewidth=2.6)


def render_case(cfg: CaseConfig) -> None:
    dims = case_dimensions(cfg)
    stl_dir = cfg.out_dir / "stl"
    render_dir = cfg.out_dir / "renders"
    render_dir.mkdir(parents=True, exist_ok=True)

    base = read_stl(stl_dir / f"{cfg.name}_base.stl")
    lid = read_stl(stl_dir / f"{cfg.name}_lid.stl")

    fig = plt.figure(figsize=(12, 8), dpi=180)
    ax = fig.add_subplot(111, projection="3d")
    all_points = [
        add_mesh(ax, base, cfg.body_color, 0.72, (0, 0, 0)),
        add_mesh(ax, lid, "#7dd3fc", 0.52, (0, 0, dims["body_z"] + LID_GAP)),
    ]

    mount_w = dims["outer_w"] + 16.0
    mount_h = dims["outer_h"] + 12.0
    mount = np.array(
        [
            [[-mount_w / 2, -mount_h / 2, -2.2], [mount_w / 2, -mount_h / 2, -2.2], [mount_w / 2, mount_h / 2, -2.2]],
            [[-mount_w / 2, -mount_h / 2, -2.2], [mount_w / 2, mount_h / 2, -2.2], [-mount_w / 2, mount_h / 2, -2.2]],
        ]
    )
    all_points.append(add_mesh(ax, mount, "#9ca3af", 0.32, (0, 0, 0)))

    add_fov_cone(ax, cfg, dims)
    add_harness(ax, cfg, dims)

    points = np.vstack(all_points)
    set_equal_axes(ax, points)
    ax.view_init(elev=26, azim=-42)
    ax.set_title(f"{cfg.title} - CadQuery Bottom-Mount Preview", pad=24)
    ax.text(0, 0, -4.5, "bottom mount face", color="#374151", ha="center")
    ax.text(0, dims["outer_h"] / 2 + 30, FLOOR_T + 8, "harness exit", color="#111827", ha="center")
    ax.text(0, cfg.board_center_y + cfg.sensor_y - 36, dims["body_z"] + 34, "FOV keepout", color="#075985", ha="center")
    ax.set_axis_off()
    fig.savefig(render_dir / f"{cfg.name}_cadquery_preview.png", bbox_inches="tight", pad_inches=0.25)
    plt.close(fig)


def configs(root: Path) -> list[CaseConfig]:
    return [
        CaseConfig(
            name="satel_vl53l8_full_carrier",
            title="SATEL-VL53L8 Full Carrier Case",
            out_dir=root / "satel-vl53l8-full-carrier-case",
            board_w=30.5,
            board_h=66.0,
            board_t=1.6,
            sensor_x=0.0,
            sensor_y=-21.0,
            board_center_y=0.0,
            component_clearance_z=3.5,
            header_clearance_z=8.0,
            header_bay_h=18.0,
            optic_opening=18.0,
            cable_slot_w=13.0,
            cable_slot_z=4.0,
            strain_bar_w=18.0,
            strain_bar_h=2.6,
            ear_w=7.0,
            ear_h=18.0,
            screw_d=2.4,
            screw_head_d=4.8,
            corner_r=2.5,
            body_color="#38bdf8",
            fov_color="#0ea5e9",
        ),
        CaseConfig(
            name="satel_vl53l8_mini",
            title="SATEL-VL53L8 Mini-PCB Case",
            out_dir=root / "satel-vl53l8-mini-case",
            board_w=20.0,
            board_h=22.0,
            board_t=1.0,
            sensor_x=0.0,
            sensor_y=-1.5,
            board_center_y=-4.0,
            component_clearance_z=3.0,
            header_clearance_z=3.0,
            header_bay_h=0.0,
            optic_opening=14.0,
            cable_slot_w=10.0,
            cable_slot_z=3.0,
            strain_bar_w=14.0,
            strain_bar_h=2.4,
            ear_w=6.0,
            ear_h=14.0,
            screw_d=2.4,
            screw_head_d=4.4,
            corner_r=2.0,
            body_color="#f59e0b",
            fov_color="#f59e0b",
        ),
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()

    for cfg in configs(args.root):
        export_case(cfg)
        render_case(cfg)


if __name__ == "__main__":
    main()
