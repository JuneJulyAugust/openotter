# Coordinate Systems Reference

## Vehicle Robot Frame (openotter)
Based on physical mounting:
- **Mounting**: Phone is in Landscape Left orientation (top of phone points left). Back camera is on the left side, facing forward.
- **+X**: Forward
- **+Y**: Up (opposite gravity)
- **+Z**: Right
- **Origin**: Starting position of the robot.

## ARKit World Space (.gravity alignment)
Used for tracking robot pose. Independent of compass.
- **-Z**: Initial Forward direction (camera facing)
- **+X**: Initial Right direction
- **+Y**: Up (gravity opposite)

**Mapping ARKit to Robot Frame**:
- `Robot.X (Forward) = -ARKit.Z`
- `Robot.Y (Up) = ARKit.Y`
- `Robot.Z (Right) = ARKit.X`

## ARKit Camera Space (right-handed)
- **+X**: Right (from camera's perspective)
- **+Y**: Up
- **-Z**: Forward (looking direction, INTO the scene)
- `frame.camera.transform` maps camera-space → world-space

BLE control changes do not alter these frame conventions.

## LiDAR Depth Map Pixel Space
- **(u, v)**: column, row of depth buffer
- **u**: increases rightward (camera's +X)
- **v**: increases downward (camera's -Y)
- Resolution: 256x192 (landscape-right native orientation)
- `frame.camera.intrinsics` are for `frame.camera.imageResolution` (e.g. 1920x1440)
- Must scale intrinsics by `(depthW/imageW, depthH/imageH)` before back-projecting

## Back-projection: pixel → camera space
Given scaled intrinsics (fx, fy, cx, cy) and depth d at pixel (u, v):
```
x_cam =  (u - cx) * d / fx     // u→right matches +X
y_cam = -(v - cy) * d / fy     // v→down, negate for +Y up
z_cam = -d                      // depth forward, negate for -Z forward
```
Then: `world_point = cameraTransform * [x_cam, y_cam, z_cam, 1]`

## Bugs fixed from v0
1. Intrinsics were NOT scaled from image resolution to depth resolution
2. Y was not negated (pixel y↓ but camera y↑)
3. Z was positive instead of negative (depth forward but camera -Z forward)
