# Deceleration Model Fitter

This directory contains the prototype code for calibrating the OpenOtter RC car's speed-dependent deceleration model.

## Background

When the OpenOtter RC car triggers an emergency brake, it relies on motor back-EMF and rolling friction to coast to a stop (there are no active friction brakes). Because back-EMF is proportional to motor speed, the car decelerates much faster at high speeds than at low speeds.

The empirical braking distance under this model follows the ODE:
$$ v \frac{dv}{dx} = -(a_0 + k v) $$

Integrating this gives the exact spatial stopping distance:
$$ d_{stop} = \frac{v_0}{k} - \frac{a_0}{k^2} \ln\left(1 + \frac{k v_0}{a_0}\right) $$

Where:
*   $a_0$ is the rolling friction component (constant, $m/s^2$)
*   $k$ is the back-EMF drag coefficient (proportional to speed, $1/s$)

## Usage

1.  Record new braking test data using the iOS app (make sure to capture both trigger speed and actual braking distance from the telemetry).
2.  Update the `DATA` list in `fit_decel.py` with your new empirical points.
3.  Activate the virtual environment and run the script:

```bash
# From the project root
source .venv/bin/activate
cd prototypes/decel_fit
python3 fit_decel.py
```

## Output

The script performs a fine-grained grid search to find the $a_0$ and $k$ values that minimize the Mean Squared Error (MSE) between the model's predicted stopping distance and the empirical spatial stopping distance.

It will output:
1.  The optimal parameters ($a_0$ and $k$).
2.  A side-by-side table comparing the actual stopping distance with the model's prediction.
3.  A plot (`decel_fit.png`) visualizing the linear drag curve compared against the empirical data points and the old constant-deceleration model.

Once new parameters are found, update `SafetySupervisorConfig` in the iOS project:
```swift
var decelIntercept: Float = <new_a0>
var decelSlope: Float = <new_k>
```
