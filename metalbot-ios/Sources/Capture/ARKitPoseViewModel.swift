import Foundation
import ARKit
import simd

struct PoseEntry: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    
    // Robot Coordinates
    let x: Float // Forward
    let y: Float // Up
    let z: Float // Right
    let yaw: Float // Rotation about Y-axis (Up)
}

final class ARKitPoseViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isTracking = false
    @Published var poses: [PoseEntry] = []
    @Published var currentPose: PoseEntry?
    @Published var errorMsg: String?
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var trackingReason: String = ""
    @Published var isUsingSceneDepth: Bool = false
    
    private let arSession = ARSession()
    private var lastRecordedTime: TimeInterval = 0
    private let recordInterval: TimeInterval = 0.1 // 10 Hz recording interval for smooth visualization
    
    override init() {
        super.init()
        arSession.delegate = self
    }
    
    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMsg = "ARWorldTracking is not supported on this device."
            return
        }
        
        let config = ARWorldTrackingConfiguration()
        // Align to gravity only (Y up, -Z is initial camera forward)
        config.worldAlignment = .gravity
        
        // --- Accuracy Enhancements ---
        // 1. Explicitly enable LiDAR Scene Depth.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        // 2. Enable Scene Reconstruction for persistent meshing and loop closure.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // 3. Enable Plane Detection (Horizontal AND Vertical).
        // Finding walls and floors gives ARKit massive continuous anchors to lock pitch/roll/yaw against.
        config.planeDetection = [.horizontal, .vertical]
        
        // 4. Environment Texturing.
        // Forces ARKit to build a comprehensive world map for lighting, strengthening the underlying VIO feature map.
        config.environmentTexturing = .automatic
        
        // 5. Use the highest resolution video format available.
        // More pixels = more distinct visual features for the odometry algorithm.
        if let highResFormat = ARWorldTrackingConfiguration.supportedVideoFormats.max(by: { $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height }) {
            config.videoFormat = highResFormat
        }
        
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        DispatchQueue.main.async {
            self.isTracking = true
            self.poses.removeAll()
            self.lastRecordedTime = 0
            self.errorMsg = nil
            self.trackingState = .notAvailable
            self.trackingReason = "Initializing..."
            self.isUsingSceneDepth = false
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
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let timestamp = frame.timestamp
        let state = frame.camera.trackingState
        let hasDepth = frame.sceneDepth != nil
        
        // Map ARKit coordinates to Robot Frame:
        // ARKit: -Z is Initial Forward, +X is Right, +Y is Up
        // Robot: +X is Forward, +Z is Right, +Y is Up
        let robotX = -transform.columns.3.z
        let robotY = transform.columns.3.y
        let robotZ = transform.columns.3.x
        let robotYaw = frame.camera.eulerAngles.y
        
        let entry = PoseEntry(timestamp: timestamp, x: robotX, y: robotY, z: robotZ, yaw: robotYaw)
        
        DispatchQueue.main.async {
            self.currentPose = entry
            self.trackingState = state
            self.isUsingSceneDepth = hasDepth
            
            switch state {
            case .notAvailable:
                self.trackingReason = "Not Available"
            case .limited(let reason):
                switch reason {
                case .initializing: self.trackingReason = "Initializing..."
                case .relocalizing: self.trackingReason = "Relocalizing..."
                case .excessiveMotion: self.trackingReason = "Excessive Motion"
                case .insufficientFeatures: self.trackingReason = "Insufficient Features"
                @unknown default: self.trackingReason = "Limited"
                }
            case .normal:
                self.trackingReason = "Normal"
            }
            
            // Record trajectory at 10Hz, but ideally only if tracking is Normal
            // To prevent massive drift spikes during initialization.
            if state == .normal {
                if timestamp - self.lastRecordedTime >= self.recordInterval {
                    self.poses.append(entry)
                    self.lastRecordedTime = timestamp
                }
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMsg = error.localizedDescription
            self.isTracking = false
        }
    }
}
