#!/usr/bin/env python3
"""Generate high-resolution PNG diagrams for figure-eight controller docs."""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Arc


REPO_ROOT = Path(__file__).resolve().parents[2]
FIGURE_DIR = REPO_ROOT / "docs" / "superpowers" / "specs" / "figures"
DPI = 220


def forward_vector(yaw: float) -> tuple[float, float]:
    """Return (x, z) forward unit vector, matching RobotGeometry.swift."""
    return math.cos(yaw), -math.sin(yaw)


def right_vector(yaw: float) -> tuple[float, float]:
    """Return (x, z) right unit vector, matching RobotGeometry.swift."""
    return math.sin(yaw), math.cos(yaw)


def plot_ground_axes(ax, title: str, xlim=(-2.0, 2.0), ylim=(-1.4, 1.4)) -> None:
    """Draw app-map axes: horizontal is z, vertical is x."""
    ax.axhline(0, color="#9ca3af", lw=1.1, zorder=0)
    ax.axvline(0, color="#9ca3af", lw=1.1, zorder=0)
    ax.annotate(
        "+z right on app map",
        xy=(xlim[1] * 0.92, 0),
        xytext=(xlim[1] * 0.56, 0.14),
        arrowprops=dict(arrowstyle="->", color="#374151", lw=1.5),
        color="#111827",
        fontsize=11,
        ha="left",
    )
    ax.annotate(
        "+x forward / up on app map",
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
    ax.set_xlabel("app-map horizontal coordinate z (m)")
    ax.set_ylabel("app-map vertical coordinate x (m)")
    ax.set_title(title, fontsize=17, weight="bold", pad=14)
    ax.grid(True, color="#e5e7eb", lw=0.8)


def arrow_xz(ax, start, vector, color, label, scale=1.0, width=0.018, text_offset=(0.04, 0.04)):
    """Draw a vector whose components are (x, z), plotted as (z, x)."""
    sx, sz = start
    vx, vz = vector
    ax.arrow(
        sz,
        sx,
        vz * scale,
        vx * scale,
        head_width=0.075,
        head_length=0.10,
        length_includes_head=True,
        color=color,
        lw=2.2,
        width=width,
        zorder=4,
    )
    ax.text(
        sz + vz * scale + text_offset[0],
        sx + vx * scale + text_offset[1],
        label,
        color=color,
        fontsize=12,
        weight="bold",
        ha="left",
        va="bottom",
    )


def save(fig, name: str) -> None:
    FIGURE_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURE_DIR / name, dpi=DPI, bbox_inches="tight")
    plt.close(fig)


def generate_coordinate_conventions() -> None:
    yaw = math.radians(35)
    f = forward_vector(yaw)
    r = right_vector(yaw)

    fig, ax = plt.subplots(figsize=(11.5, 7.2))
    plot_ground_axes(
        ax,
        "OpenOtter ground-plane convention: yaw, forward, and right",
        xlim=(-1.55, 1.75),
        ylim=(-0.55, 1.45),
    )

    ax.scatter([0], [0], s=80, color="#111827", zorder=5)
    ax.text(0.05, -0.08, "car pose / anchor", fontsize=11, color="#111827")

    arrow_xz(ax, (0, 0), (1, 0), "#6b7280", r"$+\mathbf{x}$ when $\psi=0$", scale=0.65)
    arrow_xz(
        ax,
        (0, 0),
        (0, 1),
        "#6b7280",
        r"$+\mathbf{z}$ when $\psi=0$",
        scale=0.65,
        text_offset=(0.04, -0.08),
    )
    arrow_xz(
        ax,
        (0, 0),
        f,
        "#0ea5e9",
        r"$\mathbf{f}_{world}=(\cos\psi,\,-\sin\psi)$",
        scale=1.05,
        text_offset=(-0.78, 0.05),
    )
    arrow_xz(
        ax,
        (0, 0),
        r,
        "#16a34a",
        r"$\mathbf{r}_{world}=(\sin\psi,\,\cos\psi)$",
        scale=0.88,
        text_offset=(0.02, 0.02),
    )

    # Positive yaw arc: from +x/up toward screen-left (-z).
    arc = Arc((0, 0), 0.76, 0.76, angle=0, theta1=90, theta2=125, color="#ef4444", lw=2.2)
    ax.add_patch(arc)
    ax.annotate(
        "",
        xy=(-0.24, 0.31),
        xytext=(-0.16, 0.34),
        arrowprops=dict(arrowstyle="->", color="#ef4444", lw=2.2),
    )
    ax.text(
        -1.42,
        0.20,
        r"positive yaw $\psi$ turns" + "\n" + r"the nose left toward $-z$",
        color="#ef4444",
        fontsize=12,
    )

    ax.text(
        -1.48,
        -0.43,
        "Yaw is pose.yaw. It is measured from +x forward.\n"
        "psi = 0: nose points up on the app map.\n"
        "psi > 0: nose rotates left on the app map.\n"
        "Steering sign is separate: positive steering means wheel-right.",
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

    ax.scatter([0], [0], s=120, color="#f97316", edgecolor="white", linewidth=1.8, zorder=6)
    ax.text(0.08, -0.08, "start: waypoint 0\ncenter crossing\nlocal (x=0, z=0)", fontsize=11)

    ax.scatter([z[len(z) // 2]], [x[len(x) // 2]], s=70, color="#7c3aed", edgecolor="white", zorder=6)
    ax.text(-0.95, 0.18, "halfway: center crossing again", fontsize=11, color="#5b21b6")

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
    ax.text(0.18, 0.26, "first motion:\nforward + right", color="#166534", fontsize=12, weight="bold")

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
    p0 = np.array([-0.45, -1.05])  # (x, z)
    p1 = np.array([0.82, 0.82])
    s = p1 - p0
    ref = p0 + 0.58 * s
    yaw_ref = math.atan2(-(p1[1] - p0[1]), p1[0] - p0[0])
    right = np.array(right_vector(yaw_ref))
    car = ref + 0.46 * right

    fig, ax = plt.subplots(figsize=(11.8, 7.2))
    plot_ground_axes(
        ax,
        "Path-reference geometry: projection, tangent heading, and cross-track sign",
        xlim=(-1.45, 1.45),
        ylim=(-1.05, 1.15),
    )

    ax.plot([p0[1], p1[1]], [p0[0], p1[0]], color="#dc2626", lw=5, solid_capstyle="round")
    ax.scatter([p0[1], p1[1]], [p0[0], p1[0]], s=90, color="#dc2626", edgecolor="white", zorder=5)
    ax.text(p0[1] - 0.22, p0[0] - 0.12, r"$P_0$", fontsize=15, color="#991b1b")
    ax.text(p1[1] + 0.06, p1[0] + 0.02, r"$P_1$", fontsize=15, color="#991b1b")

    ax.scatter([ref[1]], [ref[0]], s=100, color="#f97316", edgecolor="white", zorder=6)
    ax.text(ref[1] + 0.08, ref[0] - 0.18, r"$P_{ref}=P_0+\alpha(P_1-P_0)$", fontsize=12)

    ax.scatter([car[1]], [car[0]], s=120, color="#0891b2", edgecolor="white", zorder=6)
    ax.text(car[1] + 0.13, car[0] + 0.10, r"car position $p$", fontsize=12, color="#0e7490")
    ax.plot([ref[1], car[1]], [ref[0], car[0]], "--", color="#0e7490", lw=2)
    ax.text((ref[1] + car[1]) / 2 - 0.20, (ref[0] + car[0]) / 2 - 0.06, r"$e_{ct}>0$", fontsize=13, color="#0e7490")

    tangent = s / np.linalg.norm(s)
    arrow_xz(ax, ref, tangent, "#2563eb", r"path tangent / $\psi_{ref}$", scale=0.42, width=0.012)
    arrow_xz(
        ax,
        ref,
        right,
        "#16a34a",
        r"path right side",
        scale=0.34,
        width=0.012,
        text_offset=(0.14, -0.20),
    )

    ax.text(
        -1.38,
        0.88,
        r"$e_{ct}=(p-P_{ref})\cdot r_{path}$" + "\n"
        r"positive $e_{ct}$ means car is right of path",
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

    fig, ax = plt.subplots(figsize=(12.2, 7.2))
    plot_ground_axes(
        ax,
        "LQRTrack error state: lateral error, heading error, and speed error",
        xlim=(-1.45, 1.55),
        ylim=(-1.05, 1.25),
    )

    ax.plot([p0[1], p1[1]], [p0[0], p1[0]], color="#dc2626", lw=5, solid_capstyle="round")
    ax.scatter([ref[1]], [ref[0]], s=90, color="#f97316", edgecolor="white", zorder=6)
    ax.scatter([car[1]], [car[0]], s=130, color="#111827", edgecolor="white", zorder=6)
    ax.plot([ref[1], car[1]], [ref[0], car[0]], "--", color="#0e7490", lw=2)

    arrow_xz(ax, ref, ref_forward, "#2563eb", r"path heading $\psi_{ref}$", scale=0.43, width=0.012)
    arrow_xz(ax, car, car_forward, "#16a34a", r"car yaw $\psi$", scale=0.43, width=0.012)
    arrow_xz(
        ax,
        ref,
        path_right,
        "#0e7490",
        r"$e_{ct}>0$ right of path",
        scale=0.34,
        width=0.010,
        text_offset=(0.14, -0.16),
    )

    ref_angle = math.degrees(math.atan2(ref_forward[0], ref_forward[1]))
    car_angle = math.degrees(math.atan2(car_forward[0], car_forward[1]))
    arc = Arc((car[1], car[0]), 0.42, 0.42, angle=0, theta1=min(ref_angle, car_angle), theta2=max(ref_angle, car_angle), color="#ef4444", lw=2)
    ax.add_patch(arc)
    ax.text(car[1] - 0.40, car[0] + 0.38, r"$\theta_e=wrap(\psi-\psi_{ref})$", color="#ef4444", fontsize=12)

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
