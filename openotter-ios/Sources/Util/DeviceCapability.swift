import AVFoundation

enum DeviceCapability {
    /// Returns the LiDAR depth camera device if available on this hardware.
    static func lidarDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .depthData, position: .back)
    }

    static var isLiDARAvailable: Bool {
        lidarDevice() != nil
    }

    static var cameraAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
