# LiDAR Point-Cloud Capture - Design/Implementation Note

This document reflects the implemented MVP1 step-1 stack (not the earlier depth-map visualization draft).

## Goal

Capture LiDAR data on iPhone and render an orientation-correct raw point cloud, aligned with a simultaneous RGB camera view for debugging and validation.

## Implemented Data Contracts

```swift
struct PointCloud {
    let timestamp: TimeInterval
    let points: [PackedPoint]      // world-space XYZ + color
}

struct CaptureFrame {
    let pointCloud: PointCloud
    let cameraTransform: simd_float4x4
    let viewMatrix: simd_float4x4  // orientation-aware via ARKit
    let verticalFov: Float
    let cameraImage: CVPixelBuffer
    let orientation: UIInterfaceOrientation
    let depthResolution: (w: Int, h: Int)
    let imageResolution: (w: Int, h: Int)
}
```

## Runtime Pipeline

1. `ARSession` with `ARWorldTrackingConfiguration` + `.sceneDepth`.
2. Read `depthMap` + `confidenceMap` + `capturedImage`.
3. Scale intrinsics from camera image resolution to depth resolution.
4. Back-project `(u, v, depth)` into ARKit camera space.
5. Transform camera-space points into world space via `cameraTransform`.
6. Render points in Metal with:
   - camera POV mode (`viewMatrix(for: orientation)`)
   - orbit mode (gesture debug)
7. Render RGB image in parallel; use split layout for side-by-side validation.

## Coordinate Assumptions

- ARKit camera: `+X` right, `+Y` up, `-Z` forward.
- Back-projection:
  - `x_cam = (u - cx) * d / fx`
  - `y_cam = -(v - cy) * d / fy`
  - `z_cam = -d`
- Orientation handling must use `frame.camera.viewMatrix(for: orientation)` for display alignment.

See `.ai-context/coordinate-systems.md` for detailed reference.

## Known Resolved Issues

- Incorrect CLI signing/provisioning flow.
- Device auto-detection parsing failure.
- Point cloud rotated/misaligned vs RGB due to orientation matrix usage.
- App icon not packaged due to asset catalog build-phase generation gap.

## Evidence

- Main capture/display result:
  - `assets/achievements/mvp1/2026-03-14_lidar-pointcloud-rgb-capture-display.png`
