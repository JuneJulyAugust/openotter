#!/usr/bin/env python3
"""
Deceleration Model Fitter

Fits the speed-dependent deceleration model a(v) = a0 + k*v to empirical braking distances.
Uses the exact spatial stopping distance integral:
    d = v/k - (a0/k^2) * ln(1 + k*v/a0)

Author: Antigravity
"""

import math
import numpy as np
import matplotlib.pyplot as plt
import os

# Empirical brake test data from field runs
# Format: (trigger_speed_mps, braking_distance_m, mean_decel_mps2)
DATA = [
    (0.74, 0.22, 1.05),
    (1.83, 0.74, 2.11),
    (2.21, 1.63, 2.01),
    (2.25, 1.16, 2.11),
    (2.31, 1.19, 1.87),
    (2.40, 1.97, 2.12),
    (2.71, 2.02, 2.03),
    (3.16, 1.94, 2.11),
]

def stopping_distance(v0, a0, k):
    """
    Exact spatial stopping distance under linear drag.
    If k ~ 0, falls back to constant deceleration kinematics.
    """
    if k < 1e-6:
        return (v0**2) / (2 * max(a0, 1e-3))
    return v0/k - (a0/(k**2)) * math.log(1 + k*v0/a0)

def fit_model(data, a0_range=(0.1, 2.0), k_range=(0.0, 2.0), steps=200):
    """
    Grid search to minimize Mean Squared Error (MSE) of spatial stopping distance.
    """
    best_err = float('inf')
    best_a0 = 0
    best_k = 0

    a0_vals = np.linspace(*a0_range, steps)
    k_vals = np.linspace(*k_range, steps)

    for a0 in a0_vals:
        for k in k_vals:
            err = sum((stopping_distance(v, a0, k) - d)**2 for v, d, _ in data)
            if err < best_err:
                best_err = err
                best_a0 = a0
                best_k = k

    mse = best_err / len(data)
    return best_a0, best_k, mse

def plot_results(data, a0, k, save_path="decel_fit.png"):
    """
    Plots the empirical data points against the fitted stopping distance curve.
    """
    speeds = [d[0] for d in data]
    distances = [d[1] for d in data]

    v_plot = np.linspace(0, 3.5, 100)
    d_plot = [stopping_distance(v, a0, k) for v in v_plot]

    # Also plot the constant a=1.0 conservative curve for comparison
    d_const_1 = [stopping_distance(v, 1.0, 0.0) for v in v_plot]

    plt.figure(figsize=(10, 6))
    plt.scatter(speeds, distances, color='red', label='Empirical Data', zorder=5)
    plt.plot(v_plot, d_plot, color='blue', linewidth=2, label=f'Linear Drag Fit: a(v) = {a0:.2f} + {k:.2f}v')
    plt.plot(v_plot, d_const_1, color='gray', linestyle='--', label='Old Constant Fit: a = 1.0')

    plt.title('Braking Distance vs. Initial Speed')
    plt.xlabel('Initial Speed (m/s)')
    plt.ylabel('Braking Distance (m)')
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.legend()

    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    print(f"Plot saved to {save_path}")

def main():
    print("Fitting deceleration model to empirical spatial distances...")
    best_a0, best_k, mse = fit_model(DATA)

    print("\n=== Best Fit Parameters ===")
    print(f"decelIntercept (a0) = {best_a0:.3f} m/s²  (Rolling Friction)")
    print(f"decelSlope (k)      = {best_k:.3f} 1/s   (Back-EMF Drag)")
    print(f"MSE                 = {mse:.4f}")

    print("\n=== Prediction vs Reality ===")
    print(f"{'Speed (m/s)':<15} {'Actual (m)':<15} {'Predicted (m)':<15} {'Error (m)':<15}")
    print("-" * 60)
    for v, d_actual, _ in sorted(DATA):
        d_pred = stopping_distance(v, best_a0, best_k)
        print(f"{v:<15.2f} {d_actual:<15.2f} {d_pred:<15.2f} {d_pred - d_actual:<15.2f}")

    plot_results(DATA, best_a0, best_k, save_path="decel_fit.png")

if __name__ == "__main__":
    main()
