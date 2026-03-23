# Metalbot Development Milestone: ARKit 6D Pose Estimation (2026-03-22)

## Summary
Successfully implemented and visualized the 6D pose estimation using ARKit's Visual-Inertial Odometry (VIO). We pivoted from pure IMU-based velocity/position tracking to ARKit for localization and Bluetooth ESC telemetry for velocity. 

### Achievements
1.  **Home Page Redesign**: Reorganized `HomeView.swift` to act as the primary landing page, categorizing features into Perception, Estimation, and Diagnostics.
2.  **ARKit Pose ViewModel**: Implemented `ARKitPoseViewModel` to manage the `ARSession`.
    -   Configured for `.gravity` alignment to establish a consistent Robot Coordinate Frame (+X Forward, +Y Up, +Z Right).
    -   Enabled advanced accuracy features: `.sceneDepth` (LiDAR), `.mesh` scene reconstruction, and horizontal/vertical plane detection to minimize drift.
    -   Exposed internal `ARCamera.TrackingState` to ensure data is only recorded when VIO is fully initialized.
3.  **Landscape Visualization (`ARKitPoseView`)**:
    -   Built a robust, forced-landscape UI using `GeometryReader`, bypassing iOS system orientation locks, with fixed safe areas for the iPhone 13 Pro Max.
    -   Implemented a 2D canvas plotting the X-Z trajectory with continuous real-time rendering.
    -   Added auto-zooming, gesture-based pan/zoom, and a time-based Jet colormap gradient that renders the historical path when tracking is stopped.

## Current State
- **Perception**: LiDAR point cloud and RGB debug view operational.
- **Estimation**: 6D Pose (Position + Orientation) actively tracking with high accuracy via ARKit.
- **Control**: End-to-end path from iPhone to Arduino verified.

## Prompt Context for Next Session
"In the last session, we completed the ARKit 6D Pose estimation module on iOS. We have a highly accurate, drift-minimized trajectory visualization running in a forced-landscape view. We also established the 'HomeView' to tie the app together. The next major step is to tackle the other half of our new estimation strategy: implementing the Bluetooth LE connection on the Raspberry Pi to pull real-time velocity telemetry directly from the ESC, and forwarding that data back to the iPhone."
