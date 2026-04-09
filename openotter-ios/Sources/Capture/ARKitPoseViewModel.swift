import Foundation
import ARKit
import simd
import CoreVideo

// MARK: - Data Models

struct PoseEntry: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval

    // Robot Coordinates
    let x: Float // Forward
    let y: Float // Up
    let z: Float // Right
    let yaw: Float // Rotation about Y-axis (Up), gimbal-safe

    /// Tracking confidence: 0 = unknown/limited, 0.5 = limited with LiDAR, 1.0 = normal with LiDAR.
    let confidence: Float
}

/// Metadata for a saved ARWorldMap.
struct WorldMapEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let date: Date
    let anchorCount: Int
    /// Filename on disk (without directory).
    let filename: String
}

// MARK: - Yaw Extraction (gimbal-safe)

/// Extract yaw (rotation about gravity/Y-axis) from a 4×4 transform using atan2.
/// This avoids the ±π discontinuities and gimbal lock of Euler angles.
///
/// Derivation: For ARKit `.gravity` alignment, a pure Y-rotation by angle θ gives
/// `columns.2 = (sin(θ), 0, cos(θ))` (the camera's backward/+Z axis in world space).
/// Therefore `atan2(columns.2.x, columns.2.z) = atan2(sin(θ), cos(θ)) = θ`,
/// matching `eulerAngles.y` without gimbal lock at extreme pitch.
func extractGimbalSafeYaw(from transform: simd_float4x4) -> Float {
    // Use camera's +Z (backward) axis projected onto the XZ plane.
    // This directly recovers the Y-rotation angle θ.
    return atan2(transform.columns.2.x, transform.columns.2.z)
}

// MARK: - ViewModel

final class ARKitPoseViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isTracking = false
    @Published var poses: [PoseEntry] = []
    @Published var currentPose: PoseEntry?
    @Published var errorMsg: String?
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var trackingReason: String = ""
    @Published var isUsingSceneDepth: Bool = false
    @Published var worldMappingStatus: ARFrame.WorldMappingStatus = .notAvailable

    /// Center-pixel LiDAR depth in meters (nil if depth unavailable).
    @Published var forwardDepth: Float?

    /// Ground-plane speed estimated from ARKit pose differentiation (m/s).
    @Published var arkitSpeedMps: Double = 0

    /// Whether the session was interrupted (app backgrounded, camera lost, etc.).
    @Published var isInterrupted: Bool = false

    /// Whether relocalization is in progress after an interruption.
    @Published var isRelocalizing: Bool = false

    // MARK: - World Map Management

    /// All saved world maps.
    @Published var savedMaps: [WorldMapEntry] = []

    /// Currently selected map ID to load on next start. nil = no map.
    @Published var selectedMapID: UUID? = nil

    /// Whether a map was loaded for the current session.
    @Published var activeMapName: String? = nil

    /// Whether a map save operation is in progress.
    @Published var isSavingMap: Bool = false

    /// Whether the map management sheet is presented.
    @Published var showMapManager: Bool = false

    /// Measured rate of valid ARKit pose deliveries. Updated every frame.
    @Published var poseHz: Double = 0

    private let arSession = ARSession()
    private var lastRecordedTime: TimeInterval = 0
    private let recordInterval: TimeInterval = 0.1 // 10 Hz trajectory history

    /// Rolling window of frame timestamps used to compute poseHz.
    /// Accessed only on frameQueue — no lock needed.
    private var frameTimestamps: [TimeInterval] = []
    private let freqWindowSize = 30  // ~0.5 s at 60 Hz

    /// Velocity estimator — differentiates consecutive poses.
    private var velocityEstimator = ARKitVelocityEstimator()

    /// Dedicated high-priority queue for ARSession delegate callbacks.
    private let frameQueue = DispatchQueue(label: "com.openotter.arkit.pose", qos: .userInteractive)

    /// High-priority callback fired directly on the ARKit frame queue.
    /// Use this for control loops to avoid main-thread latency.
    var onFrameUpdate: ((PoseEntry, Float?, Double?) -> Void)?

    /// Directory for storing world maps.
    private var mapsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("worldmaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Index file for map metadata.
    private var indexURL: URL {
        mapsDirectory.appendingPathComponent("map_index.json")
    }

    override init() {
        super.init()
        arSession.delegate = self
        arSession.delegateQueue = frameQueue
        loadMapIndex()
    }

    // MARK: - Session Lifecycle

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMsg = "ARWorldTracking is not supported on this device."
            return
        }

        let config = makeTrackingConfiguration()

        // Load selected world map if one is chosen.
        if let mapID = selectedMapID,
           let entry = savedMaps.first(where: { $0.id == mapID }),
           let savedMap = loadWorldMap(filename: entry.filename) {
            config.initialWorldMap = savedMap
            arSession.run(config, options: [.resetTracking])
            DispatchQueue.main.async {
                self.activeMapName = entry.name
            }
        } else {
            arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
            DispatchQueue.main.async {
                self.activeMapName = nil
            }
        }

        DispatchQueue.main.async {
            self.isTracking = true
            self.poses.removeAll()
            self.lastRecordedTime = 0
            self.errorMsg = nil
            self.trackingState = .notAvailable
            self.trackingReason = "Initializing..."
            self.isUsingSceneDepth = false
            self.isInterrupted = false
            self.isRelocalizing = false
            self.velocityEstimator.reset()
            self.arkitSpeedMps = 0
        }
    }

    func stop() {
        arSession.pause()
        DispatchQueue.main.async {
            self.isTracking = false
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.poses.removeAll()
            self.currentPose = nil
        }
    }

    // MARK: - World Map Persistence

    /// Save the current world map with a given name.
    func saveWorldMap(name: String) {
        DispatchQueue.main.async { self.isSavingMap = true }

        arSession.getCurrentWorldMap { [weak self] worldMap, error in
            guard let self else { return }

            defer {
                DispatchQueue.main.async { self.isSavingMap = false }
            }

            guard let worldMap else {
                DispatchQueue.main.async {
                    self.errorMsg = error?.localizedDescription ?? "Failed to capture world map"
                }
                return
            }

            do {
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: worldMap,
                    requiringSecureCoding: true
                )
                let id = UUID()
                let filename = "\(id.uuidString).arexperience"
                let fileURL = self.mapsDirectory.appendingPathComponent(filename)
                try data.write(to: fileURL, options: .atomic)

                let entry = WorldMapEntry(
                    id: id,
                    name: name,
                    date: Date(),
                    anchorCount: worldMap.anchors.count,
                    filename: filename
                )

                DispatchQueue.main.async {
                    self.savedMaps.append(entry)
                    self.selectedMapID = id
                    self.saveMapIndex()
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMsg = "Map save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Delete a saved world map by ID.
    func deleteMap(id: UUID) {
        guard let index = savedMaps.firstIndex(where: { $0.id == id }) else { return }
        let entry = savedMaps[index]
        let fileURL = mapsDirectory.appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: fileURL)
        savedMaps.remove(at: index)
        if selectedMapID == id {
            selectedMapID = nil
            activeMapName = nil
        }
        saveMapIndex()
    }

    /// Delete all saved maps.
    func deleteAllMaps() {
        for entry in savedMaps {
            let fileURL = mapsDirectory.appendingPathComponent(entry.filename)
            try? FileManager.default.removeItem(at: fileURL)
        }
        savedMaps.removeAll()
        selectedMapID = nil
        activeMapName = nil
        saveMapIndex()
    }

    /// Deselect the current map (start next session without a map).
    func deselectMap() {
        selectedMapID = nil
        saveMapIndex()
    }

    /// Select a map and save it as default.
    func selectMap(id: UUID?) {
        selectedMapID = id
        saveMapIndex()
    }

    /// Reload the AR session to use the newly selected map as the active map.
    func applySelectedMap() {
        if isTracking {
            start()
        }
    }

    private func loadWorldMap(filename: String) -> ARWorldMap? {
        let fileURL = mapsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
        } catch {
            print("ARWorldMap load failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Map Index Persistence

    private func loadMapIndex() {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoded = try JSONDecoder().decode(MapIndex.self, from: data)
            savedMaps = decoded.maps
            selectedMapID = decoded.selectedID
        } catch {
            print("Map index load failed: \(error.localizedDescription)")
        }
    }

    private func saveMapIndex() {
        let index = MapIndex(maps: savedMaps, selectedID: selectedMapID)
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("Map index save failed: \(error.localizedDescription)")
        }
    }

    /// Migrate legacy single-file map if it exists.
    func migrateLegacyMap() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacy = docs.appendingPathComponent("openotter_worldmap.arexperience")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }

        let id = UUID()
        let filename = "\(id.uuidString).arexperience"
        let dest = mapsDirectory.appendingPathComponent(filename)
        do {
            try FileManager.default.moveItem(at: legacy, to: dest)
            let entry = WorldMapEntry(id: id, name: "Legacy Map", date: Date(), anchorCount: 0, filename: filename)
            savedMaps.append(entry)
            selectedMapID = id
            saveMapIndex()
        } catch {
            print("Legacy map migration failed: \(error.localizedDescription)")
        }
    }

    private struct MapIndex: Codable {
        let maps: [WorldMapEntry]
        let selectedID: UUID?
    }

    // MARK: - Configuration

    private func makeTrackingConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if let highResFormat = ARWorldTrackingConfiguration.supportedVideoFormats.max(by: {
            $0.imageResolution.width * $0.imageResolution.height <
            $1.imageResolution.width * $1.imageResolution.height
        }) {
            config.videoFormat = highResFormat
        }

        if let referenceImages = ARReferenceImage.referenceImages(
            inGroupNamed: "ARReferenceImages",
            bundle: nil
        ), !referenceImages.isEmpty {
            config.detectionImages = referenceImages
        }

        return config
    }

    // MARK: - Tracking Confidence

    private func computeConfidence(state: ARCamera.TrackingState, hasDepth: Bool) -> Float {
        switch state {
        case .notAvailable:
            return 0.0
        case .limited(let reason):
            let base: Float
            switch reason {
            case .initializing:     base = 0.1
            case .relocalizing:     base = 0.2
            case .excessiveMotion:  base = 0.3
            case .insufficientFeatures: base = 0.25
            @unknown default:       base = 0.2
            }
            return hasDepth ? min(base + 0.2, 0.6) : base
        case .normal:
            return hasDepth ? 1.0 : 0.8
        }
    }

    // MARK: - Depth Helpers

    /// Half-size of the square depth patch sampled around the center pixel.
    /// A value of 1 gives a 3×3 patch (9 samples). Increase for more robustness at the cost of spatial precision.
    private static let depthPatchHalfSize = 1

    /// Sample a square patch around the center pixel and return the median depth (meters).
    /// Median is robust against sparse LiDAR dropouts and noise spikes.
    private static func extractCenterDepth(from depthMap: CVPixelBuffer?) -> Float? {
        guard let depthMap else { return nil }
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float>.size
        let ptr = base.assumingMemoryBound(to: Float.self)

        let cx = w / 2
        let cy = h / 2
        let r = depthPatchHalfSize

        var samples: [Float] = []
        samples.reserveCapacity((2 * r + 1) * (2 * r + 1))
        for dy in -r...r {
            for dx in -r...r {
                let px = cx + dx
                let py = cy + dy
                guard px >= 0, px < w, py >= 0, py < h else { continue }
                let d = ptr[py * stride + px]
                if d > 0, d.isFinite { samples.append(d) }
            }
        }

        guard !samples.isEmpty else { return nil }
        return median(of: &samples)
    }

    private static func median(of values: inout [Float]) -> Float {
        values.sort()
        let mid = values.count / 2
        return values.count % 2 == 0
            ? (values[mid - 1] + values[mid]) / 2
            : values[mid]
    }

    // MARK: - ARSessionDelegate — Frame Updates

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let timestamp = frame.timestamp
        let state = frame.camera.trackingState
        let hasDepth = frame.sceneDepth != nil

        let robotX = -transform.columns.3.z
        let robotY = transform.columns.3.y
        let robotZ = transform.columns.3.x
        let robotYaw = extractGimbalSafeYaw(from: transform)
        let confidence = computeConfidence(state: state, hasDepth: hasDepth)

        let entry = PoseEntry(
            timestamp: timestamp,
            x: robotX, y: robotY, z: robotZ,
            yaw: robotYaw,
            confidence: confidence
        )

        // Extract center-pixel depth for safety supervisor.
        let centerDepth = Self.extractCenterDepth(from: frame.sceneDepth?.depthMap)

        // Compute rolling-window frequency (on frameQueue — serial, no lock needed).
        frameTimestamps.append(timestamp)
        if frameTimestamps.count > freqWindowSize { frameTimestamps.removeFirst() }
        let hz: Double
        if frameTimestamps.count >= 2 {
            let span = frameTimestamps.last! - frameTimestamps.first!
            hz = span > 0 ? Double(frameTimestamps.count - 1) / span : 0
        } else {
            hz = 0
        }

        let speed = self.velocityEstimator.update(x: robotX, z: robotZ, timestamp: timestamp)
        
        let mappingStatus = frame.worldMappingStatus
        
        onFrameUpdate?(entry, centerDepth, speed)

        DispatchQueue.main.async {
            self.currentPose = entry
            self.poseHz = hz
            self.trackingState = state
            self.worldMappingStatus = mappingStatus
            self.isUsingSceneDepth = hasDepth
            self.forwardDepth = centerDepth
            if let speed = speed {
                self.arkitSpeedMps = speed
            }

            switch state {
            case .notAvailable:
                self.trackingReason = "Not Available"
                self.isRelocalizing = false
            case .limited(let reason):
                switch reason {
                case .initializing:        self.trackingReason = "Initializing..."
                case .relocalizing:
                    self.trackingReason = "Relocalizing..."
                    self.isRelocalizing = true
                case .excessiveMotion:     self.trackingReason = "Excessive Motion"
                case .insufficientFeatures: self.trackingReason = "Insufficient Features"
                @unknown default:          self.trackingReason = "Limited"
                }
            case .normal:
                self.trackingReason = "Normal"
                self.isRelocalizing = false
            }

            if state == .normal {
                if timestamp - self.lastRecordedTime >= self.recordInterval {
                    self.poses.append(entry)
                    self.lastRecordedTime = timestamp
                }
            }
        }
    }

    // MARK: - ARSessionDelegate — Session Interruption

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.isInterrupted = true
            self.trackingReason = "Session Interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            self.isInterrupted = false
            self.isRelocalizing = true
            self.trackingReason = "Relocalizing..."
        }
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }

    // MARK: - ARSessionDelegate — Error Handling

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMsg = error.localizedDescription
            self.isTracking = false
        }
    }

    // MARK: - ARSessionDelegate — Anchor Detection

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let imageAnchor = anchor as? ARImageAnchor {
                let name = imageAnchor.referenceImage.name ?? "unknown"
                print("Reference marker detected: \(name) — position tightened")
            }
        }
    }
}
