import XCTest
@testable import openotter

final class LQRMathTests: XCTestCase {

    func testDLQRGainIsFiniteForFigureEightModel() {
        let model = LQRTrackModel.discrete(dt: 0.1, speedMps: 0.2, effectiveWheelbaseM: 0.35)
        let result = LQRMath.dlqr(
            a: model.a,
            b: model.b,
            q: Matrix.diagonal([3.0, 0.2, 2.5, 0.2, 0.8]),
            r: Matrix.diagonal([1.0, 2.0])
        )

        guard case .success(let gain) = result else {
            XCTFail("Expected finite LQR gain, got \(result)")
            return
        }

        XCTAssertEqual(gain.rows, 2)
        XCTAssertEqual(gain.columns, 5)
        for value in gain.values {
            XCTAssertTrue(value.isFinite)
        }
    }

    func testMatrixInverseRejectsSingularMatrix() {
        let singular = Matrix(rows: 2, columns: 2, values: [
            1, 2,
            2, 4
        ])

        XCTAssertNil(singular.inverted())
    }
}
