#!/usr/bin/env python3
"""Generate high-resolution PNG diagrams for figure-eight controller docs."""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import to_rgba
from matplotlib.patches import Arc, Polygon


REPO_ROOT = Path(__file__).resolve().parents[2]
FIGURE_DIR = REPO_ROOT / "docs" / "superpowers" / "specs" / "figures"
DPI = 220
CAR_MARKER_COLOR = "#0f172a"
CAR_MARKER_ALPHA = 0.50


def forward_vector(yaw: float) -> tuple[float, float]:
    """Return map components of the body +x_B forward axis."""
    return math.cos(yaw), -math.sin(yaw)


def right_vector(yaw: float) -> tuple[float, float]:
    """Return map components of OpenOtter's local +z_L right axis."""
    return math.sin(yaw), math.cos(yaw)


def left_vector(yaw: float) -> tuple[float, float]:
    """Return map components of the standard body +y_B left axis."""
    rx, rz = right_vector(yaw)
    return -rx, -rz


def plot_ground_axes(ax, title: str, xlim=(-2.0, 2.0), ylim=(-1.4, 1.4)) -> None:
    """Draw app-map axes: horizontal is z, vertical is x."""
    ax.axhline(0, color="#9ca3af", lw=1.1, zorder=0)
    ax.axvline(0, color="#9ca3af", lw=1.1, zorder=0)
    ax.annotate(
        r"$+z_M$ right on app map",
        xy=(xlim[1] * 0.92, 0),
        xytext=(xlim[1] * 0.56, 0.14),
        arrowprops=dict(arrowstyle="->", color="#374151", lw=1.5),
        color="#111827",
        fontsize=11,
        ha="left",
    )
    ax.annotate(
        r"$+x_M$ forward / up on app map",
        xy=(0, ylim[1] * 0.92),
        xytext=(0.14, ylim[1] * 0.70),
        arrowprops=dict(arrowstyle="->", color="#374151", lw=1.5),
        color="#111827",
        fontsize=11,
        ha="left",
    )
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlabel(r"app-map horizontal coordinate $z_M$ (m)")
    ax.set_ylabel(r"app-map vertical coordinate $x_M$ (m)")
    ax.set_title(title, fontsize=17, weight="bold", pad=14)
    ax.grid(True, color="#e5e7eb", lw=0.8)


def arrow_xz(
    ax,
    start,
    vector,
    color,
    label,
    scale=1.0,
    width=None,
    text_offset=(0.04, 0.04),
    lw=1.8,
    mutation_scale=14,
    linestyle="-",
):
    """Draw a vector whose components are (x, z), plotted as (z, x)."""
    sx, sz = start
    vx, vz = vector
    end_x = sx + vx * scale
    end_z = sz + vz * scale
    ax.annotate(
        "",
        xy=(end_z, end_x),
        xytext=(sz, sx),
        arrowprops=dict(
            arrowstyle="-|>",
            color=color,
            lw=lw,
            mutation_scale=mutation_scale,
            linestyle=linestyle,
        ),
        zorder=4,
    )
    ax.text(
        end_z + text_offset[0],
        end_x + text_offset[1],
        label,
        color=color,
        fontsize=12,
        weight="bold",
        ha="left",
        va="bottom",
        zorder=12,
    )


def rotated_box_points(center, yaw: float, length: float, width: float) -> np.ndarray:
    """Return car-local rectangle corners as map (x, z) points."""
    center = np.asarray(center, dtype=float)
    forward = np.asarray(forward_vector(yaw))
    right = np.asarray(right_vector(yaw))
    return np.array(
        [
            center + forward * (length / 2) + right * (width / 2),
            center + forward * (length / 2) - right * (width / 2),
            center - forward * (length / 2) - right * (width / 2),
            center - forward * (length / 2) + right * (width / 2),
        ]
    )


def add_rotated_box(
    ax,
    center,
    yaw: float,
    length: float,
    width: float,
    facecolor: str,
    edgecolor: str,
    lw: float,
    zorder: int,
) -> None:
    points = rotated_box_points(center, yaw, length, width)
    ax.add_patch(
        Polygon(
            [(point[1], point[0]) for point in points],
            closed=True,
            facecolor=facecolor,
            edgecolor=edgecolor,
            lw=lw,
            zorder=zorder,
        )
    )


def draw_car(
    ax,
    center,
    yaw: float,
    length: float = 0.62,
    width: float = 0.34,
    steering: float = 0.0,
) -> None:
    """Draw a top-view car in map coordinates."""
    center = np.asarray(center, dtype=float)
    forward = np.asarray(forward_vector(yaw))
    right = np.asarray(right_vector(yaw))
    car_color = to_rgba(CAR_MARKER_COLOR, CAR_MARKER_ALPHA)
    add_rotated_box(ax, center, yaw, length, width, car_color, car_color, 1.6, 6)

    nose = center + forward * (length * 0.36)
    ax.plot([center[1], nose[1]], [center[0], nose[0]], color=car_color, lw=1.4, zorder=7)
    ax.scatter([center[1]], [center[0]], s=26, color=[car_color], zorder=8)

    wheel_offsets = [
        forward * (length * 0.30) + right * (width * 0.58),
        forward * (length * 0.30) - right * (width * 0.58),
        -forward * (length * 0.30) + right * (width * 0.58),
        -forward * (length * 0.30) - right * (width * 0.58),
    ]
    for index, offset in enumerate(wheel_offsets):
        wheel_yaw = yaw + steering if index < 2 else yaw
        add_rotated_box(
            ax,
            center + offset,
            wheel_yaw,
            length * 0.20,
            width * 0.13,
            car_color,
            car_color,
            0.8,
            8,
        )


def shortened_segment_end(start, end, fraction: float):
    """Return a point between start and end, useful for labels that point at a car."""
    start = np.asarray(start, dtype=float)
    end = np.asarray(end, dtype=float)
    return start + (end - start) * fraction


def save(fig, name: str) -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURE_DIR / name, dpi=DPI, bbox_inches="tight")
    plt.close(fig)


def generate_coordinate_conventions() -> None:
    yaw = math.radians(35)
    body_x = forward_vector(yaw)
    body_y = left_vector(yaw)
    local_z = right_vector(yaw)

    fig, ax = plt.subplots(figsize=(12.4, 7.6))
    plot_ground_axes(
        ax,
        "Vehicle frame and OpenOtter app-map convention",
        xlim=(-2.05, 2.25),
        ylim=(-1.12, 1.65),
    )

    car_center = np.array([0.18, 0.08])
    draw_car(ax, car_center, yaw, length=0.72, width=0.42, steering=0.0)
    ax.text(
        car_center[1] + 0.30,
        car_center[0] - 0.38,
        "car pose / mission anchor",
        fontsize=11,
        color="#111827",
    )

    arrow_xz(
        ax,
        car_center,
        body_x,
        "#2563eb",
        r"${}^{M}\mathbf{e}_{x_B}$ body forward",
        scale=0.82,
        text_offset=(-0.18, 0.07),
        lw=2.0,
    )
    arrow_xz(
        ax,
        car_center,
        body_y,
        "#7c3aed",
        r"${}^{M}\mathbf{e}_{y_B}$ body left",
        scale=0.54,
        text_offset=(-0.68, 0.02),
        lw=1.8,
    )
    arrow_xz(
        ax,
        car_center,
        local_z,
        "#16a34a",
        r"${}^{M}\mathbf{e}_{z_L}=-{}^{M}\mathbf{e}_{y_B}$",
        scale=0.50,
        text_offset=(0.06, -0.13),
        lw=1.5,
        mutation_scale=12,
        linestyle="--",
    )

    # Positive yaw arc: from +x/up toward screen-left (-z) in app-map drawing.
    arc = Arc(
        (car_center[1], car_center[0]),
        0.82,
        0.82,
        angle=0,
        theta1=90,
        theta2=125,
        color="#ef4444",
        lw=1.8,
    )
    ax.add_patch(arc)
    ax.annotate(
        "",
        xy=(car_center[1] - 0.26, car_center[0] + 0.34),
        xytext=(car_center[1] - 0.16, car_center[0] + 0.38),
        arrowprops=dict(arrowstyle="->", color="#ef4444", lw=1.8),
    )
    ax.text(
        -1.84,
        0.64,
        r"positive yaw $\psi$ turns" + "\n" + r"the nose left toward $-z_M$",
        color="#ef4444",
        fontsize=12,
    )

    ax.text(
        -1.94,
        -0.98,
        r"$M$: app map stores points as $(x_M,z_M)$; $+z_M$ draws right." + "\n"
        r"$B$: standard vehicle body frame; $+x_B$ forward, $+y_B$ left, $+z_B$ up." + "\n"
        r"$L$: OpenOtter mission-local frame; $x_L=x_B$ and $z_L=-y_B$." + "\n"
        r"$\psi$ is pose.yaw: car-body heading measured from $+x_M$.",
        fontsize=11,
        color="#111827",
        bbox=dict(boxstyle="round,pad=0.45", fc="#f9fafb", ec="#d1d5db"),
    )

    save(fig, "figure-eight-coordinate-conventions.png")


def bernoulli_local_points(count=720, length=3.2, width=1.6):
    t = np.linspace(0, 2 * np.pi, count, endpoint=False)
    theta = t + np.pi / 2
    raw_x = -np.cos(theta) / (1 + np.sin(theta) ** 2)
    raw_z = -(np.sin(theta) * np.cos(theta)) / (1 + np.sin(theta) ** 2)
    # Match FigureEightTrajectory.swift: raw z becomes local x; raw x becomes local z.
    local_x = raw_z / np.max(np.abs(raw_z)) * (width / 2)
    local_z = raw_x / np.max(np.abs(raw_x)) * (length / 2)
    return local_x, local_z


def generate_start_direction() -> None:
    x, z = bernoulli_local_points()
    fig, ax = plt.subplots(figsize=(12, 7.2))
    plot_ground_axes(
        ax,
        "Figure-eight start convention: center crossing, first branch, dimensions",
        xlim=(-1.95, 1.95),
        ylim=(-1.15, 1.15),
    )
    ax.plot(z, x, color="#dc2626", lw=9, solid_capstyle="round", alpha=0.34, label="reference path")
    ax.plot(z, x, color="#b91c1c", lw=2.2, alpha=0.85)

    arrow_indices = [18, 88, 178, 272, 372, 492, 612]
    for idx in arrow_indices:
        j = (idx + 6) % len(x)
        dz = z[j] - z[idx]
        dx = x[j] - x[idx]
        length = math.hypot(dx, dz)
        if length == 0:
            continue
        ax.arrow(
            z[idx],
            x[idx],
            dz / length * 0.18,
            dx / length * 0.18,
            head_width=0.045,
            head_length=0.065,
            color="#7f1d1d",
            lw=1.8,
            length_includes_head=True,
            zorder=5,
        )

    ax.scatter(
        [0],
        [0],
        s=130,
        color="#f97316",
        edgecolor="white",
        linewidth=1.8,
        zorder=8,
    )
    ax.scatter(
        [z[len(z) // 2]],
        [x[len(x) // 2]],
        s=210,
        facecolor="none",
        edgecolor="#7c3aed",
        linewidth=2.1,
        zorder=7,
    )
    ax.annotate(
        "start: waypoint 0\ncenter crossing\nlocal (x=0, z=0)",
        xy=(0, 0),
        xytext=(0.30, -0.27),
        arrowprops=dict(arrowstyle="->", color="#111827", lw=1.2),
        fontsize=11,
        color="#111827",
        bbox=dict(boxstyle="round,pad=0.30", fc="white", ec="#d1d5db", alpha=0.88),
        zorder=12,
    )
    ax.annotate(
        "halfway crossing",
        xy=(0, 0),
        xytext=(-1.18, 0.30),
        arrowprops=dict(arrowstyle="->", color="#5b21b6", lw=1.2),
        fontsize=11,
        color="#5b21b6",
        bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="#ddd6fe", alpha=0.88),
        zorder=12,
    )

    # First motion arrow.
    first_i, first_j = 0, 16
    ax.arrow(
        z[first_i],
        x[first_i],
        z[first_j] - z[first_i],
        x[first_j] - x[first_i],
        head_width=0.08,
        head_length=0.12,
        color="#16a34a",
        lw=3.0,
        length_includes_head=True,
        zorder=7,
    )
    ax.text(
        0.50,
        0.33,
        "first motion:\nforward + right",
        color="#166534",
        fontsize=12,
        weight="bold",
        bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="none", alpha=0.82),
        zorder=12,
    )

    ax.annotate(
        "length = 3.2 m along +Z/-Z\n(app-map left/right)",
        xy=(1.6, -0.93),
        xytext=(0.30, -1.08),
        arrowprops=dict(arrowstyle="<->", color="#374151", lw=1.8),
        color="#111827",
        fontsize=11,
    )
    ax.annotate(
        "width = 1.6 m along +X/-X\n(app-map forward/back)",
        xy=(-1.78, 0.8),
        xytext=(-1.88, -0.16),
        arrowprops=dict(arrowstyle="<->", color="#374151", lw=1.8),
        color="#111827",
        fontsize=11,
        rotation=90,
        va="center",
    )
    ax.legend(loc="upper right", frameon=True)
    save(fig, "figure-eight-start-and-direction.png")


def generate_path_reference_geometry() -> None:
    p0 = np.array([-0.54, -1.28])  # (x, z)
    p1 = np.array([0.84, 1.12])
    s = p1 - p0
    ref = p0 + 0.56 * s
    yaw_ref = math.atan2(-(p1[1] - p0[1]), p1[0] - p0[0])
    right = np.array(right_vector(yaw_ref))
    car = ref + 0.42 * right
    car_yaw = yaw_ref + math.radians(18)

    fig, ax = plt.subplots(figsize=(12.4, 7.6))
    plot_ground_axes(
        ax,
        "Path-reference geometry: projection, tangent heading, and cross-track sign",
        xlim=(-1.75, 1.72),
        ylim=(-1.15, 1.25),
    )

    ax.plot([p0[1], p1[1]], [p0[0], p1[0]], color="#dc2626", lw=3.2, solid_capstyle="round")
    ax.scatter([p0[1], p1[1]], [p0[0], p1[0]], s=72, color="#dc2626", edgecolor="white", zorder=5)
    ax.text(p0[1] - 0.23, p0[0] - 0.13, r"$P_0$", fontsize=14, color="#991b1b")
    ax.text(p1[1] + 0.07, p1[0] + 0.03, r"$P_1$", fontsize=14, color="#991b1b")

    ax.scatter([ref[1]], [ref[0]], s=86, color="#f97316", edgecolor="white", zorder=7)
    ax.text(
        ref[1] - 0.70,
        ref[0] + 0.13,
        r"$P_{ref}=P_0+\alpha(P_1-P_0)$",
        fontsize=12,
        color="#92400e",
    )

    projection_end = shortened_segment_end(ref, car, 0.66)
    ax.plot([ref[1], projection_end[1]], [ref[0], projection_end[0]], "--", color="#0e7490", lw=1.8)
    draw_car(ax, car, car_yaw, length=0.54, width=0.30)
    ax.annotate(
        r"car pose $p_M$",
        xy=(car[1], car[0]),
        xytext=(0.78, -0.48),
        arrowprops=dict(arrowstyle="->", color="#0e7490", lw=1.2),
        fontsize=12,
        color="#0e7490",
        bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="#bae6fd", alpha=0.88),
        zorder=12,
    )
    ax.annotate(
        r"$e_{ct}>0$",
        xy=(projection_end[1], projection_end[0]),
        xytext=(-0.46, -0.23),
        arrowprops=dict(arrowstyle="->", color="#0e7490", lw=1.2),
        fontsize=13,
        color="#0e7490",
        bbox=dict(boxstyle="round,pad=0.22", fc="white", ec="#bae6fd", alpha=0.88),
        zorder=12,
    )

    tangent = s / np.linalg.norm(s)
    arrow_xz(
        ax,
        ref,
        tangent,
        "#2563eb",
        r"path tangent ${}^{M}\mathbf{e}_{x_P}$",
        scale=0.46,
        text_offset=(0.02, 0.05),
        lw=1.9,
    )

    ax.text(
        -1.63,
        0.93,
        r"$P$: path frame at the projected point" + "\n"
        r"${}^{M}\mathbf{e}_{x_P}$: path tangent" + "\n"
        r"${}^{M}\mathbf{e}_{z_P}$: path-right axis" + "\n"
        r"$e_{ct}=(p_M-P_{ref})\cdot{}^{M}\mathbf{e}_{z_P}$",
        fontsize=12,
        bbox=dict(boxstyle="round,pad=0.45", fc="#f9fafb", ec="#d1d5db"),
    )
    save(fig, "path-reference-geometry.png")


def generate_lqr_error_state() -> None:
    p0 = np.array([-0.50, -1.05])
    p1 = np.array([0.72, 0.92])
    s = p1 - p0
    ref = p0 + 0.55 * s
    yaw_ref = math.atan2(-(p1[1] - p0[1]), p1[0] - p0[0])
    path_right = np.array(right_vector(yaw_ref))
    car = ref + 0.42 * path_right
    yaw = yaw_ref + math.radians(28)
    car_forward = np.array(forward_vector(yaw))
    ref_forward = np.array(forward_vector(yaw_ref))

    fig, ax = plt.subplots(figsize=(12.4, 7.6))
    plot_ground_axes(
        ax,
        "LQRTrack error state: lateral error, heading error, and speed error",
        xlim=(-1.55, 1.65),
        ylim=(-1.05, 1.25),
    )

    ax.plot([p0[1], p1[1]], [p0[0], p1[0]], color="#dc2626", lw=3.2, solid_capstyle="round")
    ax.scatter([ref[1]], [ref[0]], s=90, color="#f97316", edgecolor="white", zorder=8)
    projection_end = shortened_segment_end(ref, car, 0.62)
    ax.plot([ref[1], projection_end[1]], [ref[0], projection_end[0]], "--", color="#0e7490", lw=1.8)
    draw_car(ax, car, yaw, length=0.54, width=0.30)

    arrow_xz(ax, ref, ref_forward, "#2563eb", r"path heading $\psi_{ref}$", scale=0.43, lw=1.8)
    arrow_xz(ax, car, car_forward, "#16a34a", r"car yaw $\psi$", scale=0.43, lw=1.8)
    arrow_xz(
        ax,
        ref,
        path_right,
        "#0e7490",
        r"$e_{ct}>0$ right of path",
        scale=0.34,
        text_offset=(0.48, -0.26),
        lw=1.6,
    )

    ref_angle = math.degrees(math.atan2(ref_forward[0], ref_forward[1]))
    car_angle = math.degrees(math.atan2(car_forward[0], car_forward[1]))
    arc = Arc(
        (car[1], car[0]),
        0.42,
        0.42,
        angle=0,
        theta1=min(ref_angle, car_angle),
        theta2=max(ref_angle, car_angle),
        color="#ef4444",
        lw=2,
    )
    ax.add_patch(arc)
    ax.annotate(
        r"$\theta_e=wrap(\psi-\psi_{ref})$",
        xy=(ref[1], ref[0]),
        xytext=(-0.86, 0.22),
        arrowprops=dict(arrowstyle="->", color="#ef4444", lw=1.2),
        color="#ef4444",
        fontsize=12,
        bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="#fecaca", alpha=0.88),
        zorder=12,
    )

    ax.text(
        -1.35,
        0.88,
        "LQR state vector\n"
        r"$x_{LQR}=[e,\dot e,\theta_e,\dot\theta_e,v_e]^T$" + "\n\n"
        r"$e=-e_{ct}$ in LQRTrack" + "\n"
        r"$v_e=v_{measured}-v_{target}$",
        fontsize=12,
        bbox=dict(boxstyle="round,pad=0.45", fc="#f9fafb", ec="#d1d5db"),
    )
    save(fig, "lqr-error-state.png")


def main() -> None:
    generate_coordinate_conventions()
    generate_start_direction()
    generate_path_reference_geometry()
    generate_lqr_error_state()


if __name__ == "__main__":
    main()
