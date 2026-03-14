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

### 2026-03-14 - Capture pipeline refactor for robustness and testability

- **Context:** LiDAR capture/render stack was functional but had avoidable crash-risk patterns and limited unit-test coverage for projection math.
- **What we built/tested:** Extracted depth back-projection into `DepthPointProjector`, added unit tests for projection invariants, added renderer init error handling, and introduced frame-coalescing in `CaptureViewModel` to prevent unbounded per-frame main-thread task buildup.
- **Issue observed:** Potential one-off crashes and memory pressure from force-unwrapped Metal setup and per-frame asynchronous UI update fan-out under load.
- **Root cause:** (1) renderer initialization used `fatalError`/force unwrap paths, (2) frame delivery created one main-thread task per AR frame with no coalescing, and (3) projection logic lived inside session callbacks with no isolated test seam.
- **Resolution:** Made renderer initialization throwable with user-visible error propagation, moved projection math into a dedicated module, added explicit frame mailbox/coalescing behavior guarded by lock, and added `autoreleasepool` around camera image conversion/frame processing.
- **Validation:** Build succeeds after refactor; new tests validate camera-model equations, intrinsics scaling, and confidence filtering behavior.
- **Follow-up:** Run on-device with Memory Graph/Instruments to confirm stable allocations over long sessions and to tune point count/performance for planner integration.

### 2026-03-14 - Release optimization profile documented and validated

- **Context:** Need deterministic CLI commands for debug vs optimized release deployment on physical device.
- **What we built/tested:** Added explicit `Debug`/`Release` optimization settings in `project.yml` and updated `README.md` with command arguments for both profiles.
- **Issue observed:** Build profile behavior was implicit and command guidance did not clearly separate development and performance runs.
- **Root cause:** Optimization settings and release deployment workflow were not documented as first-class build profiles.
- **Resolution:** Set `Debug` to `-Onone` + `singlefile` and `Release` to `-O` + `wholemodule`; documented `./build.sh deploy` and `./build.sh --release deploy` with manual `xcodebuild` equivalents.
- **Validation:** Verified settings via `xcodebuild -showBuildSettings` and confirmed successful `Release` build and deploy on device.
- **Follow-up:** Add quantitative frame-time benchmarks (Debug vs Release) after planner features increase CPU load.
