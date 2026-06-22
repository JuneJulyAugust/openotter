import Foundation

struct Matrix: Equatable, CustomStringConvertible {
    let rows: Int
    let columns: Int
    var values: [Double]

    init(rows: Int, columns: Int, values: [Double]) {
        precondition(rows > 0 && columns > 0)
        precondition(values.count == rows * columns)
        self.rows = rows
        self.columns = columns
        self.values = values
    }

    static func zeros(rows: Int, columns: Int) -> Matrix {
        Matrix(rows: rows, columns: columns, values: Array(repeating: 0, count: rows * columns))
    }

    static func identity(_ size: Int) -> Matrix {
        var matrix = zeros(rows: size, columns: size)
        for index in 0..<size {
            matrix[index, index] = 1
        }
        return matrix
    }

    static func diagonal(_ diagonal: [Double]) -> Matrix {
        var matrix = zeros(rows: diagonal.count, columns: diagonal.count)
        for (index, value) in diagonal.enumerated() {
            matrix[index, index] = value
        }
        return matrix
    }

    subscript(row: Int, column: Int) -> Double {
        get { values[row * columns + column] }
        set { values[row * columns + column] = newValue }
    }

    var description: String {
        "Matrix(\(rows)x\(columns), \(values))"
    }

    var transposed: Matrix {
        var result = Matrix.zeros(rows: columns, columns: rows)
        for row in 0..<rows {
            for column in 0..<columns {
                result[column, row] = self[row, column]
            }
        }
        return result
    }

    var maxAbs: Double {
        values.map { abs($0) }.max() ?? 0
    }

    var isFinite: Bool {
        values.allSatisfy { $0.isFinite }
    }

    func inverted(epsilon: Double = 1e-10) -> Matrix? {
        guard rows == columns else { return nil }

        var left = self
        var right = Matrix.identity(rows)

        for pivotIndex in 0..<rows {
            var pivotRow = pivotIndex
            var pivotAbs = abs(left[pivotRow, pivotIndex])
            for row in (pivotIndex + 1)..<rows {
                let candidate = abs(left[row, pivotIndex])
                if candidate > pivotAbs {
                    pivotAbs = candidate
                    pivotRow = row
                }
            }

            guard pivotAbs > epsilon else { return nil }

            if pivotRow != pivotIndex {
                left.swapRows(pivotIndex, pivotRow)
                right.swapRows(pivotIndex, pivotRow)
            }

            let pivot = left[pivotIndex, pivotIndex]
            for column in 0..<rows {
                left[pivotIndex, column] /= pivot
                right[pivotIndex, column] /= pivot
            }

            for row in 0..<rows where row != pivotIndex {
                let factor = left[row, pivotIndex]
                guard factor != 0 else { continue }
                for column in 0..<rows {
                    left[row, column] -= factor * left[pivotIndex, column]
                    right[row, column] -= factor * right[pivotIndex, column]
                }
            }
        }

        return right.isFinite ? right : nil
    }

    private mutating func swapRows(_ first: Int, _ second: Int) {
        for column in 0..<columns {
            let firstIndex = first * columns + column
            let secondIndex = second * columns + column
            values.swapAt(firstIndex, secondIndex)
        }
    }
}

func + (lhs: Matrix, rhs: Matrix) -> Matrix {
    precondition(lhs.rows == rhs.rows && lhs.columns == rhs.columns)
    return Matrix(
        rows: lhs.rows,
        columns: lhs.columns,
        values: zip(lhs.values, rhs.values).map(+)
    )
}

func - (lhs: Matrix, rhs: Matrix) -> Matrix {
    precondition(lhs.rows == rhs.rows && lhs.columns == rhs.columns)
    return Matrix(
        rows: lhs.rows,
        columns: lhs.columns,
        values: zip(lhs.values, rhs.values).map(-)
    )
}

func * (lhs: Matrix, rhs: Matrix) -> Matrix {
    precondition(lhs.columns == rhs.rows)
    var result = Matrix.zeros(rows: lhs.rows, columns: rhs.columns)
    for row in 0..<lhs.rows {
        for column in 0..<rhs.columns {
            var sum = 0.0
            for k in 0..<lhs.columns {
                sum += lhs[row, k] * rhs[k, column]
            }
            result[row, column] = sum
        }
    }
    return result
}

func * (lhs: Matrix, rhs: [Double]) -> [Double] {
    precondition(lhs.columns == rhs.count)
    return (0..<lhs.rows).map { row in
        var sum = 0.0
        for column in 0..<lhs.columns {
            sum += lhs[row, column] * rhs[column]
        }
        return sum
    }
}

enum LQRResult: CustomStringConvertible {
    case success(Matrix)
    case singular
    case nonFinite

    var description: String {
        switch self {
        case .success(let matrix): return "success(\(matrix))"
        case .singular: return "singular"
        case .nonFinite: return "nonFinite"
        }
    }
}

enum LQRMath {
    static func dlqr(a: Matrix,
                     b: Matrix,
                     q: Matrix,
                     r: Matrix,
                     maxIterations: Int = 150,
                     epsilon: Double = 0.01) -> LQRResult {
        guard a.isFinite, b.isFinite, q.isFinite, r.isFinite else { return .nonFinite }
        var p = q
        let at = a.transposed
        let bt = b.transposed

        for _ in 0..<maxIterations {
            let s = r + bt * p * b
            guard let invS = s.inverted() else { return .singular }
            let next = at * p * a - at * p * b * invS * bt * p * a + q
            guard next.isFinite else { return .nonFinite }
            if (next - p).maxAbs < epsilon {
                p = next
                break
            }
            p = next
        }

        let s = r + bt * p * b
        guard let invS = s.inverted() else { return .singular }
        let gain = invS * bt * p * a
        guard gain.isFinite else { return .nonFinite }
        return .success(gain)
    }
}

enum LQRTrackModel {
    static func discrete(dt: Double,
                         speedMps: Double,
                         effectiveWheelbaseM: Double) -> (a: Matrix, b: Matrix) {
        let v = max(0.05, speedMps)
        let wheelbase = max(0.05, effectiveWheelbaseM)
        var a = Matrix.zeros(rows: 5, columns: 5)
        a[0, 0] = 1
        a[0, 1] = dt
        a[1, 2] = v
        a[2, 2] = 1
        a[2, 3] = dt
        a[4, 4] = 1

        var b = Matrix.zeros(rows: 5, columns: 2)
        b[3, 0] = v / wheelbase
        b[4, 1] = dt
        return (a, b)
    }
}
