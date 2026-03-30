import Foundation

extension Float {
    /// Wrap angle to the range (-π, π].
    func wrapToPi() -> Float {
        var a = self
        while a > .pi  { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}
