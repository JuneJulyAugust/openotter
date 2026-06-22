from typing import Optional


Matrix = list[list[float]]


def zeros(rows: int, columns: int) -> Matrix:
    return [[0.0 for _ in range(columns)] for _ in range(rows)]


def identity(size: int) -> Matrix:
    matrix = zeros(size, size)
    for index in range(size):
        matrix[index][index] = 1.0
    return matrix


def diagonal(values: list[float]) -> Matrix:
    matrix = zeros(len(values), len(values))
    for index, value in enumerate(values):
        matrix[index][index] = value
    return matrix


def transpose(matrix: Matrix) -> Matrix:
    return [list(column) for column in zip(*matrix)]


def add(a: Matrix, b: Matrix) -> Matrix:
    return [[left + right for left, right in zip(row_a, row_b)] for row_a, row_b in zip(a, b)]


def subtract(a: Matrix, b: Matrix) -> Matrix:
    return [[left - right for left, right in zip(row_a, row_b)] for row_a, row_b in zip(a, b)]


def multiply(a: Matrix, b: Matrix) -> Matrix:
    rows = len(a)
    columns = len(b[0])
    inner = len(b)
    out = zeros(rows, columns)
    for row in range(rows):
        for column in range(columns):
            out[row][column] = sum(a[row][k] * b[k][column] for k in range(inner))
    return out


def multiply_vector(a: Matrix, x: list[float]) -> list[float]:
    return [sum(row[column] * x[column] for column in range(len(x))) for row in a]


def inverse(matrix: Matrix, epsilon: float = 1e-10) -> Optional[Matrix]:
    size = len(matrix)
    left = [row[:] for row in matrix]
    right = identity(size)

    for pivot_index in range(size):
        pivot_row = max(range(pivot_index, size), key=lambda row: abs(left[row][pivot_index]))
        if abs(left[pivot_row][pivot_index]) <= epsilon:
            return None
        if pivot_row != pivot_index:
            left[pivot_index], left[pivot_row] = left[pivot_row], left[pivot_index]
            right[pivot_index], right[pivot_row] = right[pivot_row], right[pivot_index]

        pivot = left[pivot_index][pivot_index]
        for column in range(size):
            left[pivot_index][column] /= pivot
            right[pivot_index][column] /= pivot

        for row in range(size):
            if row == pivot_index:
                continue
            factor = left[row][pivot_index]
            for column in range(size):
                left[row][column] -= factor * left[pivot_index][column]
                right[row][column] -= factor * right[pivot_index][column]

    return right


def dlqr(a: Matrix, b: Matrix, q: Matrix, r: Matrix, max_iterations: int = 150) -> Matrix:
    p = [row[:] for row in q]
    at = transpose(a)
    bt = transpose(b)
    for _ in range(max_iterations):
        s = add(r, multiply(multiply(bt, p), b))
        inv_s = inverse(s)
        if inv_s is None:
            raise ValueError("singular LQR solve")
        p_next = add(
            subtract(
                multiply(multiply(at, p), a),
                multiply(multiply(multiply(multiply(multiply(at, p), b), inv_s), bt), multiply(p, a)),
            ),
            q,
        )
        delta = max(abs(p_next[row][col] - p[row][col]) for row in range(len(p)) for col in range(len(p[0])))
        p = p_next
        if delta < 0.01:
            break
    inv_s = inverse(add(r, multiply(multiply(bt, p), b)))
    if inv_s is None:
        raise ValueError("singular LQR gain")
    return multiply(multiply(multiply(inv_s, bt), p), a)


def model_matrices(dt: float, speed_mps: float, wheelbase_m: float) -> tuple[Matrix, Matrix]:
    v = max(0.05, speed_mps)
    wheelbase = max(0.05, wheelbase_m)
    a = zeros(5, 5)
    a[0][0] = 1.0
    a[0][1] = dt
    a[1][2] = v
    a[2][2] = 1.0
    a[2][3] = dt
    a[4][4] = 1.0
    b = zeros(5, 2)
    b[3][0] = v / wheelbase
    b[4][1] = dt
    return a, b
