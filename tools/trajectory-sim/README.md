# OpenOtter Trajectory Simulator

Local Python prototype package for figure-eight path following controllers.
It mirrors the iOS controller names:

```text
TangentTrack  baseline tangent/cross-track controller
LQRTrack      experimental LQR speed-and-steering controller
```

Editable install:

```bash
cd tools/trajectory-sim
python3 -m pip install -e .
```

Run tests from an environment with matplotlib installed:

```bash
cd tools/trajectory-sim
PYTHONPATH=src python3 -m unittest discover tests
```

Generate a PNG comparison plot:

```bash
cd tools/trajectory-sim
PYTHONPATH=src python3 -m openotter_sim.cli --controller both --output figure8-sim.png
```

The CLI prints final progress index and max cross-track error for each
controller, then writes a PNG with separate subplots for `TangentTrack` and
`LQRTrack`. Each subplot shows the same translucent red reference path and one
controller trace, which makes the comparison easier to read than overlaying
both traces on one axes.

Generate one-controller PNGs when you want separate files:

```bash
PYTHONPATH=src python3 -m openotter_sim.cli --controller tangent --output tangent-track.png
PYTHONPATH=src python3 -m openotter_sim.cli --controller lqr --output lqr-track.png
```

The plot uses the same app-map convention as the iOS app:

```text
screen up    = local +X forward
screen right = local +Z right
length       = 3.2 m along +Z/-Z
width        = 1.6 m along +X/-X
```
