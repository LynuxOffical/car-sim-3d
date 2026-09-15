# car-sim-3d

A true 3D third-person car driving simulator written in Python with
**Pygame** (window / input) and **PyOpenGL** (rendering). No 3D model
files or textures required — everything is drawn from OpenGL primitives.

## Setup

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```powershell
python main.py
```

## Controls

| Key | Action |
| --- | --- |
| Up arrow | Accelerate |
| Down arrow | Brake, then reverse |
| Left / Right arrows | Steer (turning radius depends on speed) |
| Esc | Quit |

## What's inside

Everything lives in a single `main.py`, organized into classes:

- `Car` — rectangular-prism body plus arcade physics: acceleration,
  braking, reverse, rolling friction, quadratic drag, and speed-dependent
  steering.
- `ChaseCamera` — third-person camera that exponentially smooths toward a
  point behind and above the car (`gluLookAt` builds the view matrix).
- `World` — a snapping "infinite" ground grid and randomly scattered
  obstacle cubes (fixed seed, so the world is the same every run).
- `Game` — window creation, the projection matrix (`gluPerspective`),
  event handling, and the main loop.

The comments in `main.py` explain how the OpenGL **PROJECTION** and
**MODELVIEW** matrices are used in the render loop.
