# metalbot Walkthrough (Development Log)

This file is for implementation-time learning, not upfront planning.

Add entries only after real coding, integration, or testing work reveals valuable issues or decisions.

## Logging Rules

- Log concrete events: implemented feature, observed bug, measured behavior, resolved issue.
- Avoid speculative design notes that belong in `plan.md`.
- Keep each entry short and technical.
- Include reproducible evidence when possible (logs, metrics, trace IDs, test names).

## Entry Template

### YYYY-MM-DD - Short Title

- **Context:** What subsystem and scenario were involved.
- **What we built/tested:** Concrete implementation action.
- **Issue observed:** Actual failure mode or limitation.
- **Root cause:** Confirmed cause, not guesswork.
- **Resolution:** Code/config/protocol change made.
- **Validation:** How we proved the fix works.
- **Follow-up:** Remaining risk or next step.

## Entries

### 2026-03-14 - MVP1 Step 1: LiDAR capture + RGB debug display

- **Context:** iPhone 13 Pro/Pro Max app bring-up for MVP1 perception foundation.
- **What we built/tested:** Implemented ARKit `sceneDepth` capture, depth-to-point-cloud back-projection, Metal point rendering, RGB camera preview, adaptive split layout, diagnostics HUD, and CLI build/deploy workflow.
- **Issue observed:** (1) CLI deploy failed from signing/provisioning mismatch. (2) Auto device detection failed in script parsing. (3) Point cloud appeared rotated/misaligned vs RGB. (4) App icon did not appear correctly on device.
- **Root cause:** (1) Wrong team identifier usage and missing provisioning update flag. (2) Device parser assumed leading whitespace. (3) Projection/view math mixed orientation assumptions; view matrix must be interface-orientation aware and intrinsics must be scaled to depth resolution. (4) `Assets.xcassets` was not being compiled into `Assets.car`, and previous icon source had low contrast/alpha issues.
- **Resolution:** Added `-allowProvisioningUpdates`, fixed team setup, corrected device UUID extraction, switched to orientation-aware `viewMatrix(for:)`, fixed intrinsics scaling and axis signs, enabled rich diagnostics, moved icon to asset catalog pipeline, and ensured `Assets.car` is compiled in builds.
- **Validation:** `./build.sh deploy` succeeds; app installs and launches on device; RGB + point-cloud debug screen runs at ~30 FPS with live points and camera image.
- **Follow-up:** Next step is to convert live point cloud into planner-ready obstacle features and integrate with speed/stop planning.

#### Visual Evidence

![MVP1 LiDAR point-cloud + RGB debug view](../assets/achievements/mvp1/2026-03-14_lidar-pointcloud-rgb-capture-display.png)
