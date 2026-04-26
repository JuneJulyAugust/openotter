import Foundation

/// Shared PWM pulse-width mapping for steering and throttle.
///
/// Mirrors the constants in firmware `pwm_control.h` so iOS and the
/// STM32 agree on what "neutral" / "full reverse" / "full forward" mean
/// on the wire.
///
/// All callers that build a steering/throttle command should route through
/// this type rather than re-deriving `1500 + clamped * 500` inline. Keeps
/// the magic numbers in exactly one place.
public enum PwmMapping {

    /// Pulse width µs sent for "neutral" (servo center, ESC coast).
    public static let neutralUs: Int16 = 1500

    /// Pulse width µs at the lower bound (full reverse / steering left).
    public static let minUs: Int16 = 1000

    /// Pulse width µs at the upper bound (full forward / steering right).
    public static let maxUs: Int16 = 2000

    /// Map a normalized command in `[-1.0, +1.0]` to a clamped PWM pulse
    /// width in microseconds.
    ///
    /// - `0.0` → `neutralUs` (1500 µs)
    /// - `+1.0` → `maxUs` (2000 µs)
    /// - `-1.0` → `minUs` (1000 µs)
    /// - Out-of-range inputs are clamped to `[-1.0, +1.0]` first.
    /// - NaN and ±Infinity collapse to neutral so we never emit a
    ///   command that the firmware would clip silently.
    public static func toPulseWidth(_ normalized: Float) -> Int16 {
        guard normalized.isFinite else { return neutralUs }
        let clamped = max(-1.0, min(1.0, normalized))
        return Int16(Float(neutralUs) + clamped * 500.0)
    }

    /// Clamp a raw pulse width to `[minUs, maxUs]`. Mirrors
    /// `PwmControl_ClampPulse` in the firmware so a clipped value on
    /// either side stays consistent.
    public static func clampPulse(_ pulseUs: Int16) -> Int16 {
        if pulseUs < minUs { return minUs }
        if pulseUs > maxUs { return maxUs }
        return pulseUs
    }
}
