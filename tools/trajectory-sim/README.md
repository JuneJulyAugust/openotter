# OpenOtter Trajectory Simulator

Local Python prototype package for figure-eight path following controllers.
It mirrors the iOS controller names:

```text
TangentTrack  baseline tangent/cross-track controller
LQRTrack      experimental LQR speed-and-steering controller
```

Optional editable install:

```bash
cd tools/trajectory-sim
python3 -m pip install -e .
```

Run tests without installing anything:

```bash
cd tools/trajectory-sim
PYTHONPATH=src python3 -m unittest discover tests
```

Generate an SVG comparison plot:

```bash
cd tools/trajectory-sim
PYTHONPATH=src python3 -m openotter_sim.cli --controller both --output figure8-sim.svg
```

The CLI prints final progress index and max cross-track error for each
controller, then writes an SVG with the translucent red reference path and
controller traces.

The plot uses the same app-map convention as the iOS app:

```text
screen up    = local +X forward
screen right = local +Z right
length       = 3.2 m along +Z/-Z
width        = 1.6 m along +X/-X
```
