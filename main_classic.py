"""
3D Car Racing Simulator
=======================
Tech stack:
    - Pygame   : window creation, input events, main-loop timing, font raster.
    - PyOpenGL : all 3D rendering (fixed-function pipeline for simplicity).

No external assets are required — every shape is built from OpenGL
primitives and colored with plain RGB values.

Features:
    - Three selectable cars inspired by real Toyotas — COROLLA GT (balanced
      sedan), SUPRA RZ (fast coupe with a rear wing), YARIS LE (nimble
      hatchback with a black roof) — each with its own body shape and stats.
    - Car customization: 8 paint colors, previewed on a rotating showroom car.
    - Three maps with different layouts and scenery themes: Meadow Circuit
      (classic), Sunset Speedway (wide desert flat-out), Alpine Run (narrow
      snowy technical track).
    - Detailed car bodies built from tapered "frustum" panels and true
      cylindrical wheels that spin with speed and steer with input.
    - Solid collisions: barrier walls keep cars on the track and cars push
      each other apart on contact.
    - AI opponents that follow the racing line and brake for corners.
    - Single-player, two-player split-screen, and free play modes.
    - Directional lighting, distance fog, blob shadows, start-line gantry,
      and a HUD with speed / lap / race position.

Controls:
    Menus       : 1/2/3 pick mode, LEFT/RIGHT + UP/DOWN browse,
                  ENTER confirm, ESC back
    Player 1    : arrow keys (UP accelerate, DOWN brake/reverse, steer)
    Player 2    : W/S/A/D (split-screen mode)
    In race     : R = restart, ESC = back to menu

-------------------------------------------------------------------------
A quick primer on the two OpenGL matrices used here
-------------------------------------------------------------------------
OpenGL (fixed-function) transforms every vertex through two matrix stacks:

1.  PROJECTION matrix
    The *lens* of the camera: how 3D view-space coordinates are squashed
    onto the 2D screen. Built with gluPerspective(fov, aspect, near, far),
    which creates a perspective frustum — distant objects appear smaller.
    In split-screen mode each viewport has a different aspect ratio, so
    the projection matrix is rebuilt per viewport every frame.

2.  MODELVIEW matrix
    A single matrix that combines:
      - VIEW  : where the camera is and what it looks at (gluLookAt).
      - MODEL : where each object sits in the world (glTranslate/glRotate).
    Every frame we reset it (glLoadIdentity), apply the camera transform
    first, then push/pop object transforms around each draw call so that
    objects don't inherit each other's positions.

The rendering loop each frame is therefore, per viewport:
    set glViewport -> build PROJECTION -> reset MODELVIEW -> camera ->
    draw static world (a precompiled display list) -> draw cars.
Then the 2D HUD is drawn over everything with an orthographic projection,
and finally the double buffer is flipped so the image appears at once.
-------------------------------------------------------------------------
"""

import math
import random
import sys

import pygame
from OpenGL.GL import *
from OpenGL.GLU import *

# ------------------------------------------------------------------ config
WINDOW_W, WINDOW_H = 1280, 720
FOV_DEGREES = 68.0
NEAR_PLANE = 0.5           # pushed out a bit for better depth-buffer precision
FAR_PLANE = 900.0
FPS = 60
TOTAL_LAPS = 3

# Graphics quality presets, cycled with G on the main menu.
#   shader  : per-pixel GLSL lighting on/off
#   scenery : density multiplier for trees/buildings
#   fog     : multiplier on the map's fog distances (higher = see farther)
QUALITY_PRESETS = [
    ("LOW", {"shader": False, "scenery": 0.4, "fog": 0.6}),
    ("MEDIUM", {"shader": True, "scenery": 1.0, "fog": 1.0}),
    ("HIGH", {"shader": True, "scenery": 1.6, "fog": 1.3}),
]


# ----------------------------------------------------------------- shaders
# GLSL replaces fixed-function lighting with *per-pixel* shading: the
# fixed pipeline computes light once per vertex and interpolates the
# result, while this fragment shader recomputes diffuse + specular for
# every pixel — smooth highlights on car paint and softly graded walls
# instead of flat facets. It is written against the GLSL 1.20
# compatibility profile so it can keep reading the classic OpenGL state
# this game already sets: matrices (ftransform), glColor, glLightfv
# (gl_LightSource[0]) and glFog (gl_Fog), which is what lets display
# lists and immediate-mode geometry flow through it unchanged.
VERTEX_SHADER = """
#version 120
varying vec3 vNormal;    // surface normal, eye space
varying vec3 vEyePos;    // fragment position, eye space
void main() {
    gl_Position = ftransform();                      // proj * modelview * vertex
    vNormal = gl_NormalMatrix * gl_Normal;
    vEyePos = vec3(gl_ModelViewMatrix * gl_Vertex);
    gl_FrontColor = gl_Color;                        // pass the material color
}
"""

FRAGMENT_SHADER = """
#version 120
varying vec3 vNormal;
varying vec3 vEyePos;
void main() {
    vec3 N = normalize(vNormal);
    // Directional light: glLightfv position with w=0, already eye space.
    vec3 L = normalize(gl_LightSource[0].position.xyz);
    float diff = max(dot(N, L), 0.0);

    // Blinn-Phong specular: half-vector between light and view direction.
    vec3 V = normalize(-vEyePos);
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(N, H), 0.0), 42.0) * 0.30 * step(0.01, diff);

    vec4 base = gl_Color;
    vec3 col = base.rgb * (0.42 + 0.72 * diff) + vec3(spec);

    // Linear fog from the classic glFog state, but per pixel.
    float dist = length(vEyePos);
    float fogF = clamp((gl_Fog.end - dist) * gl_Fog.scale, 0.0, 1.0);
    col = mix(gl_Fog.color.rgb, col, fogF);

    gl_FragColor = vec4(col, base.a);
}
"""


# ---------------------------------------------------------------- utilities
def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def lerp(a, b, t):
    return a + (b - a) * t


def wrap_angle(a):
    """Wrap an angle to [-pi, pi] so 'turn left or right?' math works."""
    return (a + math.pi) % (2.0 * math.pi) - math.pi


def catmull_rom(points, samples_per_seg):
    """Sample a closed Catmull-Rom spline through the given control points."""
    n = len(points)
    out = []
    for i in range(n):
        p0 = points[(i - 1) % n]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            z = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, z))
    return out


# ----------------------------------------------------------- draw primitives
def _quad(v0, v1, v2, v3):
    """
    Emit one quad with a normal computed from its actual corner positions
    (cross product of two edges). This is what makes sloped body panels —
    hoods, windshields, fastbacks — shade correctly under GL_LIGHTING
    instead of looking like flat-lit boxes.
    Must be called inside glBegin(GL_QUADS).
    """
    ax, ay, az = v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]
    bx, by, bz = v3[0] - v0[0], v3[1] - v0[1], v3[2] - v0[2]
    nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    glNormal3f(nx / length, ny / length, nz / length)
    for v in (v0, v1, v2, v3):
        glVertex3f(*v)


def frustum(bottom, top, y0, y1, color):
    """
    A tapered box ("loft") between two axis-aligned rectangles at different
    heights. `bottom`/`top` are (x0, x1, z0, z1). With different rects this
    produces the slanted panels that make the cars look like cars; with
    identical rects it degenerates to a plain box.
    """
    bx0, bx1, bz0, bz1 = bottom
    tx0, tx1, tz0, tz1 = top
    a = (bx0, y0, bz0); b = (bx1, y0, bz0)
    c = (bx1, y0, bz1); d = (bx0, y0, bz1)
    e = (tx0, y1, tz0); f = (tx1, y1, tz0)
    g = (tx1, y1, tz1); h = (tx0, y1, tz1)
    glColor3f(*color)
    glBegin(GL_QUADS)
    _quad(e, h, g, f)      # top    (+Y)
    _quad(a, b, c, d)      # bottom (-Y)
    _quad(b, a, e, f)      # front  (-Z)
    _quad(d, c, g, h)      # rear   (+Z)
    _quad(a, d, h, e)      # left   (-X)
    _quad(c, b, f, g)      # right  (+X)
    glEnd()


def box_at(cx, cy, cz, w, h, l, color):
    """Convenience: a plain box centered at (cx, cy, cz)."""
    r = (cx - w / 2, cx + w / 2, cz - l / 2, cz + l / 2)
    frustum(r, r, cy - h / 2, cy + h / 2, color)


_wheel_lists = {}


def _wheel_list(radius, width):
    """
    Build (once) and cache a display list for a wheel: a true cylinder
    tire with silver hub-cap discs — no more blocky square wheels.
    Cylinder axis runs along X (the axle direction).
    """
    key = (round(radius, 3), round(width, 3))
    if key in _wheel_lists:
        return _wheel_lists[key]
    lst = glGenLists(1)
    glNewList(lst, GL_COMPILE)
    seg = 16
    hw = width / 2.0
    # Tire tread: a quad strip around the circumference.
    glColor3f(0.05, 0.05, 0.06)
    glBegin(GL_QUAD_STRIP)
    for i in range(seg + 1):
        ang = 2.0 * math.pi * i / seg
        cy, sz = math.cos(ang), math.sin(ang)
        glNormal3f(0.0, cy, sz)
        glVertex3f(-hw, cy * radius, sz * radius)
        glVertex3f(hw, cy * radius, sz * radius)
    glEnd()
    # Side walls + silver hub caps.
    for side in (-1.0, 1.0):
        glColor3f(0.05, 0.05, 0.06)
        glNormal3f(side, 0.0, 0.0)
        glBegin(GL_TRIANGLE_FAN)
        glVertex3f(side * hw, 0.0, 0.0)
        for i in range(seg + 1):
            ang = 2.0 * math.pi * i / seg
            glVertex3f(side * hw, math.cos(ang) * radius, math.sin(ang) * radius)
        glEnd()
        glColor3f(0.72, 0.73, 0.76)
        glBegin(GL_TRIANGLE_FAN)
        glVertex3f(side * (hw + 0.012), 0.0, 0.0)
        for i in range(seg + 1):
            ang = 2.0 * math.pi * i / seg
            glVertex3f(side * (hw + 0.012),
                       math.cos(ang) * radius * 0.55,
                       math.sin(ang) * radius * 0.55)
        glEnd()
    glEndList()
    _wheel_lists[key] = lst
    return lst


GLASS = (0.10, 0.12, 0.16)
TRIM = (0.13, 0.13, 0.15)


# ------------------------------------------------------------- car bodies
# Local car frame: origin on the ground under the car's center,
# -Z is forward, +Z is rear, X is left/right. Each body function emits the
# painted shell; wheels are drawn separately so they can steer and spin.

def body_corolla(color):
    """Balanced 4-door sedan: distinct hood, cabin and trunk volumes."""
    frustum((-0.82, 0.82, -1.95, 1.95), (-0.95, 0.95, -2.20, 2.20), 0.18, 0.45, TRIM)
    frustum((-0.95, 0.95, -2.20, 2.20), (-0.90, 0.90, -2.12, 2.12), 0.45, 0.92, color)
    # Cabin glasshouse: raked windshield (front) and rear window.
    frustum((-0.82, 0.82, -0.95, 1.55), (-0.68, 0.68, -0.25, 1.30), 0.92, 1.42, GLASS)
    frustum((-0.68, 0.68, -0.25, 1.30), (-0.66, 0.66, -0.22, 1.27), 1.42, 1.47, color)
    # Bumpers, grille, lights.
    frustum((-0.97, 0.97, -2.30, -2.05), (-0.93, 0.93, -2.28, -2.05), 0.28, 0.58, TRIM)
    frustum((-0.97, 0.97, 2.05, 2.30), (-0.93, 0.93, 2.05, 2.28), 0.28, 0.58, TRIM)
    box_at(0.0, 0.66, -2.17, 0.85, 0.16, 0.10, (0.08, 0.08, 0.09))
    for sx in (-0.56, 0.56):
        box_at(sx, 0.80, -2.16, 0.36, 0.11, 0.10, (0.95, 0.95, 0.82))
        box_at(sx, 0.80, 2.16, 0.36, 0.11, 0.10, (0.80, 0.08, 0.08))


def body_supra(color):
    """Low, wide sports coupe: long hood, fastback glass, big rear wing."""
    frustum((-0.86, 0.86, -2.00, 2.00), (-1.00, 1.00, -2.25, 2.25), 0.16, 0.42, TRIM)
    frustum((-1.00, 1.00, -2.25, 2.25), (-0.95, 0.95, -2.18, 2.18), 0.42, 0.84, color)
    # Fastback cabin: the top rectangle ends far ahead of the bottom one,
    # producing the long sloped rear glass.
    frustum((-0.87, 0.87, -0.55, 1.80), (-0.70, 0.70, 0.05, 1.05), 0.84, 1.26, GLASS)
    frustum((-0.70, 0.70, 0.05, 1.05), (-0.68, 0.68, 0.08, 1.02), 1.26, 1.30, color)
    # Rear wing on two posts.
    for sx in (-0.62, 0.62):
        box_at(sx, 0.95, 2.02, 0.12, 0.26, 0.12, TRIM)
    box_at(0.0, 1.12, 2.06, 1.92, 0.09, 0.50, color)
    # Bumpers, slim lights.
    frustum((-1.02, 1.02, -2.34, -2.08), (-0.97, 0.97, -2.32, -2.08), 0.26, 0.55, TRIM)
    frustum((-1.02, 1.02, 2.08, 2.34), (-0.97, 0.97, 2.08, 2.32), 0.26, 0.55, TRIM)
    for sx in (-0.58, 0.58):
        box_at(sx, 0.74, -2.20, 0.42, 0.08, 0.10, (0.95, 0.95, 0.82))
        box_at(sx, 0.74, 2.20, 0.42, 0.08, 0.10, (0.80, 0.08, 0.08))


def body_yaris(color):
    """Short, tall hatchback. The LE trim gets a black roof + roof spoiler."""
    frustum((-0.78, 0.78, -1.55, 1.55), (-0.90, 0.90, -1.80, 1.80), 0.18, 0.46, TRIM)
    frustum((-0.90, 0.90, -1.80, 1.80), (-0.86, 0.86, -1.74, 1.72), 0.46, 0.95, color)
    # Tall cabin with a steep hatch at the rear.
    frustum((-0.80, 0.80, -0.75, 1.62), (-0.66, 0.66, -0.05, 1.42), 0.95, 1.50, GLASS)
    # Signature LE black roof.
    frustum((-0.66, 0.66, -0.05, 1.42), (-0.63, 0.63, 0.00, 1.40), 1.50, 1.56, (0.06, 0.06, 0.07))
    box_at(0.0, 1.52, 1.52, 1.28, 0.10, 0.26, (0.06, 0.06, 0.07))   # roof spoiler
    # Bumpers and lights.
    frustum((-0.92, 0.92, -1.90, -1.66), (-0.88, 0.88, -1.88, -1.66), 0.28, 0.56, TRIM)
    frustum((-0.92, 0.92, 1.66, 1.90), (-0.88, 0.88, 1.66, 1.88), 0.28, 0.56, TRIM)
    for sx in (-0.50, 0.50):
        box_at(sx, 0.82, -1.78, 0.34, 0.12, 0.10, (0.95, 0.95, 0.82))
        box_at(sx, 0.82, 1.78, 0.34, 0.12, 0.10, (0.80, 0.08, 0.08))


CAR_MODELS = [
    {
        "id": "corolla", "name": "COROLLA GT", "tag": "balanced sedan",
        "body": body_corolla,
        "wheels": [(-0.88, -1.40, True), (0.88, -1.40, True),
                   (-0.88, 1.40, False), (0.88, 1.40, False)],
        "wheel_radius": 0.34, "wheel_width": 0.26, "shadow": (2.15, 4.55),
        "stats": {"max_speed": 30.0, "accel": 22.0, "brake": 38.0, "steer": 2.45},
    },
    {
        "id": "supra", "name": "SUPRA RZ", "tag": "rear-wing rocket",
        "body": body_supra,
        "wheels": [(-0.92, -1.45, True), (0.92, -1.45, True),
                   (-0.92, 1.50, False), (0.92, 1.50, False)],
        "wheel_radius": 0.37, "wheel_width": 0.30, "shadow": (2.25, 4.70),
        "stats": {"max_speed": 36.0, "accel": 26.0, "brake": 40.0, "steer": 2.05},
    },
    {
        "id": "yaris", "name": "YARIS LE", "tag": "limited edition pocket rocket",
        "body": body_yaris,
        "wheels": [(-0.82, -1.15, True), (0.82, -1.15, True),
                   (-0.82, 1.20, False), (0.82, 1.20, False)],
        "wheel_radius": 0.32, "wheel_width": 0.24, "shadow": (2.00, 3.80),
        "stats": {"max_speed": 27.5, "accel": 25.0, "brake": 38.0, "steer": 2.90},
    },
]

PAINT_COLORS = [
    ("RACING RED", (0.82, 0.10, 0.10)),
    ("PEARL WHITE", (0.92, 0.92, 0.94)),
    ("MIDNIGHT BLACK", (0.10, 0.10, 0.12)),
    ("STREET BLUE", (0.15, 0.35, 0.88)),
    ("SUNBURST YELLOW", (0.95, 0.80, 0.12)),
    ("BLAZE ORANGE", (0.93, 0.48, 0.10)),
    ("RALLY GREEN", (0.10, 0.45, 0.20)),
    ("TITAN SILVER", (0.68, 0.70, 0.74)),
]

_body_lists = {}


def draw_car_model(model, color, steer=0.0, roll_deg=0.0):
    """
    Draw a complete car (body shell + 4 wheels) at the local origin.
    The painted shell is compiled into a display list per (model, color);
    wheels stay dynamic so the front pair can steer and all four can spin.
    """
    key = (model["id"], color)
    if key not in _body_lists:
        lst = glGenLists(1)
        glNewList(lst, GL_COMPILE)
        model["body"](color)
        glEndList()
        _body_lists[key] = lst
    glCallList(_body_lists[key])

    wl = _wheel_list(model["wheel_radius"], model["wheel_width"])
    for wx, wz, steered in model["wheels"]:
        glPushMatrix()
        glTranslatef(wx, model["wheel_radius"], wz)
        if steered:
            glRotatef(steer * 22.0, 0.0, 1.0, 0.0)
        # Forward motion is -Z; a negative rotation about X rolls the top
        # of the wheel toward -Z, i.e. the tire visibly rolls forward.
        glRotatef(-roll_deg, 1.0, 0.0, 0.0)
        glCallList(wl)
        glPopMatrix()


# ---------------------------------------------------------------- 2D overlay
class TextRenderer:
    """
    Rasterizes text with pygame.font and blits it with glDrawPixels.
    glWindowPos2i positions the raster in *window* coordinates (origin at
    the bottom-left), independent of the 3D matrices — perfect for a HUD.
    Rendered strings are cached because font rasterization is slow.
    """

    def __init__(self):
        pygame.font.init()
        self._fonts = {}
        self._cache = {}

    def _font(self, size):
        if size not in self._fonts:
            self._fonts[size] = pygame.font.Font(None, size)
        return self._fonts[size]

    def _surface(self, text, size, color):
        key = (text, size, color)
        if key not in self._cache:
            surf = self._font(size).render(text, True, color)
            # flipped=True because OpenGL's y axis points up.
            data = pygame.image.tobytes(surf, "RGBA", True)
            if len(self._cache) > 400:   # bound the cache (speeds change often)
                self._cache.pop(next(iter(self._cache)))
            self._cache[key] = (surf.get_width(), surf.get_height(), data)
        return self._cache[key]

    def width(self, text, size):
        return self._surface(text, size, (255, 255, 255))[0]

    def draw(self, text, x, y, size=28, color=(255, 255, 255)):
        w, h, data = self._surface(text, size, color)
        glWindowPos2i(int(x), int(y))
        glDrawPixels(w, h, GL_RGBA, GL_UNSIGNED_BYTE, data)

    def draw_centered(self, text, cx, y, size=28, color=(255, 255, 255)):
        self.draw(text, cx - self.width(text, size) / 2, y, size, color)


def begin_2d():
    """Switch to an orthographic 'screen space' projection for HUD drawing."""
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_LIGHTING)
    glDisable(GL_FOG)
    glMatrixMode(GL_PROJECTION)
    glPushMatrix()
    glLoadIdentity()
    glOrtho(0, WINDOW_W, 0, WINDOW_H, -1, 1)
    glMatrixMode(GL_MODELVIEW)
    glPushMatrix()
    glLoadIdentity()


def end_2d():
    """Restore the 3D projection saved by begin_2d."""
    glMatrixMode(GL_PROJECTION)
    glPopMatrix()
    glMatrixMode(GL_MODELVIEW)
    glPopMatrix()
    glEnable(GL_DEPTH_TEST)
    glEnable(GL_FOG)


def draw_rect_2d(x, y, w, h, color, alpha=1.0):
    glColor4f(color[0], color[1], color[2], alpha)
    glBegin(GL_QUADS)
    glVertex2f(x, y); glVertex2f(x + w, y)
    glVertex2f(x + w, y + h); glVertex2f(x, y + h)
    glEnd()


# -------------------------------------------------------------------- maps
MAPS = [
    {
        "name": "MEADOW CIRCUIT", "tag": "classic  -  flowing corners",
        "width": 16.0, "samples": 14,
        "points": [
            (0, -85), (45, -88), (85, -70), (100, -30), (85, 5),
            (60, 25), (55, 55), (80, 80), (55, 105), (10, 95),
            (-30, 80), (-65, 95), (-100, 75), (-105, 35), (-85, 5),
            (-100, -35), (-75, -70), (-35, -80),
        ],
        "theme": {
            "sky": (0.66, 0.80, 0.95), "sky_top": (0.20, 0.44, 0.85),
            "fog": (150.0, 420.0),
            "ground": ((0.30, 0.52, 0.24), (0.27, 0.47, 0.21)),
            "road": (0.20, 0.20, 0.22),
            "stripe_a": (0.85, 0.15, 0.15), "stripe_b": (0.92, 0.92, 0.92),
            "scenery": "pine",
        },
    },
    {
        "name": "SUNSET SPEEDWAY", "tag": "desert  -  flat out",
        "width": 18.0, "samples": 18,
        "points": [
            (0, -100), (60, -95), (110, -60), (125, 0), (110, 60),
            (60, 95), (0, 100), (-60, 95), (-110, 60), (-125, 0),
            (-110, -60), (-60, -95),
        ],
        "theme": {
            "sky": (0.96, 0.74, 0.50), "sky_top": (0.42, 0.42, 0.68),
            "fog": (160.0, 460.0),
            "ground": ((0.80, 0.70, 0.46), (0.76, 0.66, 0.42)),
            "road": (0.25, 0.23, 0.22),
            "stripe_a": (0.80, 0.25, 0.10), "stripe_b": (0.95, 0.90, 0.80),
            "scenery": "desert",
        },
    },
    {
        "name": "ALPINE RUN", "tag": "snow  -  narrow and technical",
        "width": 14.0, "samples": 14,
        "points": [
            (0, -70), (40, -75), (70, -50), (60, -15), (90, 10),
            (85, 50), (45, 65), (10, 45), (-25, 60), (-30, 95),
            (-70, 90), (-95, 55), (-75, 20), (-95, -15), (-70, -50),
            (-30, -45),
        ],
        "theme": {
            "sky": (0.72, 0.78, 0.90), "sky_top": (0.30, 0.42, 0.68),
            "fog": (120.0, 380.0),
            "ground": ((0.88, 0.90, 0.94), (0.82, 0.85, 0.90)),
            "road": (0.15, 0.15, 0.18),
            "stripe_a": (0.20, 0.35, 0.70), "stripe_b": (0.92, 0.92, 0.95),
            "scenery": "snow_pine",
        },
    },
]


# ------------------------------------------------------------------- track
class Track:
    """
    One race circuit, built from a map spec (layout points, width, theme).

    For every waypoint we precompute the forward direction and the left
    normal. Those give a local coordinate frame used for:
      - building the road / curb / wall geometry,
      - collision (signed lateral distance from the center line),
      - AI steering targets and lap/progress tracking.
    """

    def __init__(self, spec, scenery_count=90):
        self.spec = spec
        self.theme = spec["theme"]
        self.scenery_count = scenery_count
        self.wps = catmull_rom(spec["points"], spec["samples"])
        self.n = len(self.wps)
        self.half_width = spec["width"] / 2.0

        self.dirs, self.normals = [], []
        for i in range(self.n):
            x0, z0 = self.wps[i]
            x1, z1 = self.wps[(i + 1) % self.n]
            dx, dz = x1 - x0, z1 - z0
            d = math.hypot(dx, dz) or 1.0
            self.dirs.append((dx / d, dz / d))
            self.normals.append((-dz / d, dx / d))

        xs = [p[0] for p in self.wps]
        zs = [p[1] for p in self.wps]
        self.bounds = (min(xs), max(xs), min(zs), max(zs))
        self._plant_scenery()

    def _plant_scenery(self):
        """
        Scatter scenery on the ground, away from the asphalt. Spots close
        to the track get plants (trees/cacti); spots with more clearance
        can also get buildings, which are bigger.
        """
        rng = random.Random(7)
        x0, x1, z0, z1 = self.bounds
        plant_clear = (self.half_width + 10.0) ** 2
        build_clear = (self.half_width + 20.0) ** 2
        self.scenery = []
        while len(self.scenery) < self.scenery_count:
            x = rng.uniform(x0 - 110, x1 + 110)
            z = rng.uniform(z0 - 110, z1 + 110)
            d2 = min((x - wx) ** 2 + (z - wz) ** 2 for wx, wz in self.wps)
            if d2 <= plant_clear:
                continue
            r = rng.random()
            kind = "building" if (d2 > build_clear and r < 0.30) else "plant"
            self.scenery.append((x, z, rng.uniform(0.85, 1.40), r, kind))

    # ------------------------------------------------------------ queries
    def nearest_index(self, x, z, hint=None):
        """
        Index of the waypoint closest to (x, z). With a hint (last frame's
        index) only a small window is searched, keeping this O(1) per car.
        """
        if hint is None:
            candidates = range(self.n)
        else:
            candidates = [(hint + k) % self.n for k in range(-8, 24)]
        return min(candidates,
                   key=lambda i: (x - self.wps[i][0]) ** 2 + (z - self.wps[i][1]) ** 2)

    def heading_at(self, i):
        """World heading (radians) of the track direction at waypoint i."""
        dx, dz = self.dirs[i]
        return math.atan2(-dx, -dz)

    def clamp_to_walls(self, car):
        """
        Barrier collision. Decompose the car position into (longitudinal,
        lateral) components of the local waypoint frame; if the lateral
        part exceeds the track half-width, push the car back inside and
        scrub some speed. Returns True if the car touched a wall.
        """
        i = car.wp_idx
        wx, wz = self.wps[i]
        dx, dz = self.dirs[i]
        nx, nz = self.normals[i]
        rx, rz = car.x - wx, car.z - wz
        lat = rx * nx + rz * nz
        lon = rx * dx + rz * dz
        max_lat = self.half_width - 1.1     # keep the car body off the wall
        if abs(lat) > max_lat:
            lat = max_lat if lat > 0 else -max_lat
            car.x = wx + dx * lon + nx * lat
            car.z = wz + dz * lon + nz * lat
            car.speed *= 0.94               # scraping the wall costs speed
            return True
        return False

    # ---------------------------------------------------------- rendering
    def build_display_list(self):
        """
        Compile all static geometry (ground, road, curbs, walls, start line,
        gantry, scenery) into one display list. The GPU replays it with a
        single glCallList per viewport per frame — far faster than
        re-issuing thousands of immediate-mode calls, which matters in
        split screen.
        """
        lst = glGenLists(1)
        glNewList(lst, GL_COMPILE)
        # Flat ground/road geometry gets an explicit up normal so the
        # per-pixel shader lights it correctly.
        glNormal3f(0.0, 1.0, 0.0)
        self._emit_ground()
        self._emit_road()
        self._emit_markings()
        glEnable(GL_LIGHTING)      # walls, gantry, stand & scenery are lit
        self._emit_walls()
        self._emit_gantry()
        self._emit_grandstand()
        self._emit_scenery()
        glDisable(GL_LIGHTING)
        glEndList()
        return lst

    def _emit_ground(self):
        """Two-tone checkered ground: gives a motion reference off-track."""
        c1, c2 = self.theme["ground"]
        tile = 40.0
        x0, x1, z0, z1 = self.bounds
        gx0 = int(math.floor((x0 - 200) / tile))
        gx1 = int(math.ceil((x1 + 200) / tile))
        gz0 = int(math.floor((z0 - 200) / tile))
        gz1 = int(math.ceil((z1 + 200) / tile))
        for gx in range(gx0, gx1):
            for gz in range(gz0, gz1):
                glColor3f(*(c1 if (gx + gz) % 2 == 0 else c2))
                x, z = gx * tile, gz * tile
                glBegin(GL_QUADS)
                glVertex3f(x, 0.0, z); glVertex3f(x + tile, 0.0, z)
                glVertex3f(x + tile, 0.0, z + tile); glVertex3f(x, 0.0, z + tile)
                glEnd()

    def _emit_road(self):
        """Asphalt ribbon + colored curbs along both edges."""
        hw = self.half_width
        glColor3f(*self.theme["road"])
        glBegin(GL_QUAD_STRIP)
        for i in list(range(self.n)) + [0]:      # + [0] closes the loop
            (wx, wz), (nx, nz) = self.wps[i], self.normals[i]
            glVertex3f(wx + nx * hw, 0.02, wz + nz * hw)
            glVertex3f(wx - nx * hw, 0.02, wz - nz * hw)
        glEnd()

        sa, sb = self.theme["stripe_a"], self.theme["stripe_b"]
        for side in (1.0, -1.0):
            for i in range(self.n):
                j = (i + 1) % self.n
                glColor3f(*(sa if (i // 3) % 2 == 0 else sb))
                (ax, az), (anx, anz) = self.wps[i], self.normals[i]
                (bx, bz), (bnx, bnz) = self.wps[j], self.normals[j]
                glBegin(GL_QUADS)
                glVertex3f(ax + anx * side * (hw - 1.3), 0.03, az + anz * side * (hw - 1.3))
                glVertex3f(ax + anx * side * hw, 0.03, az + anz * side * hw)
                glVertex3f(bx + bnx * side * hw, 0.03, bz + bnz * side * hw)
                glVertex3f(bx + bnx * side * (hw - 1.3), 0.03, bz + bnz * side * (hw - 1.3))
                glEnd()

    def _emit_markings(self):
        """Dashed center line + checkered start/finish line at waypoint 0."""
        glColor3f(0.9, 0.9, 0.9)
        for i in range(0, self.n, 6):
            (wx, wz), (dx, dz), (nx, nz) = self.wps[i], self.dirs[i], self.normals[i]
            glBegin(GL_QUADS)
            for sx, sz in ((-0.18, 0.0), (0.18, 0.0), (0.18, 2.2), (-0.18, 2.2)):
                glVertex3f(wx + nx * sx + dx * sz, 0.04, wz + nz * sx + dz * sz)
            glEnd()

        (wx, wz), (dx, dz), (nx, nz) = self.wps[0], self.dirs[0], self.normals[0]
        cols, cw = 8, (self.half_width - 1.3) * 2 / 8
        for row in range(2):
            for col in range(cols):
                c = 0.95 if (row + col) % 2 == 0 else 0.05
                glColor3f(c, c, c)
                l0 = -(self.half_width - 1.3) + col * cw
                f0 = row * 1.1
                glBegin(GL_QUADS)
                for sx, sz in ((l0, f0), (l0 + cw, f0), (l0 + cw, f0 + 1.1), (l0, f0 + 1.1)):
                    glVertex3f(wx + nx * sx + dx * sz, 0.05, wz + nz * sx + dz * sz)
                glEnd()

    def _emit_walls(self):
        """Striped barrier walls just outside the curbs, on both sides."""
        hw, h = self.half_width, 1.1
        inner, outer = hw + 0.9, hw + 1.7
        sa, sb = self.theme["stripe_a"], self.theme["stripe_b"]
        for side in (1.0, -1.0):
            for i in range(self.n):
                j = (i + 1) % self.n
                glColor3f(*(sa if (i // 4) % 2 == 0 else sb))
                (ax, az), (anx, anz) = self.wps[i], self.normals[i]
                (bx, bz), (bnx, bnz) = self.wps[j], self.normals[j]
                a_in = (ax + anx * side * inner, az + anz * side * inner)
                b_in = (bx + bnx * side * inner, bz + bnz * side * inner)
                a_out = (ax + anx * side * outer, az + anz * side * outer)
                b_out = (bx + bnx * side * outer, bz + bnz * side * outer)
                glBegin(GL_QUADS)
                glNormal3f(-side * anx, 0.0, -side * anz)     # inner face
                glVertex3f(a_in[0], 0, a_in[1]); glVertex3f(b_in[0], 0, b_in[1])
                glVertex3f(b_in[0], h, b_in[1]); glVertex3f(a_in[0], h, a_in[1])
                glNormal3f(side * anx, 0.0, side * anz)       # outer face
                glVertex3f(a_out[0], 0, a_out[1]); glVertex3f(a_out[0], h, a_out[1])
                glVertex3f(b_out[0], h, b_out[1]); glVertex3f(b_out[0], 0, b_out[1])
                glNormal3f(0, 1, 0)                           # top
                glVertex3f(a_in[0], h, a_in[1]); glVertex3f(b_in[0], h, b_in[1])
                glVertex3f(b_out[0], h, b_out[1]); glVertex3f(a_out[0], h, a_out[1])
                glEnd()

    def _emit_gantry(self):
        """Overhead start/finish gantry: two posts and a beam across."""
        (wx, wz) = self.wps[0]
        glPushMatrix()
        glTranslatef(wx, 0.0, wz)
        glRotatef(math.degrees(self.heading_at(0)), 0.0, 1.0, 0.0)
        span = self.half_width + 2.2
        for sx in (-span, span):
            box_at(sx, 3.1, 0.0, 0.45, 6.2, 0.45, (0.25, 0.25, 0.28))
        box_at(0.0, 6.55, 0.0, span * 2 + 0.45, 0.75, 0.75, self.theme["stripe_a"])
        glPopMatrix()

    def _emit_grandstand(self):
        """Spectator grandstand along the outside of the start straight:
        stepped rows of colored seats, a back wall, and a roof on posts."""
        (wx, wz) = self.wps[0]
        glPushMatrix()
        glTranslatef(wx, 0.0, wz)
        glRotatef(math.degrees(self.heading_at(0)), 0.0, 1.0, 0.0)
        off = self.half_width + 6.0
        seat_colors = [(0.75, 0.15, 0.15), (0.15, 0.35, 0.75),
                       (0.85, 0.70, 0.15), (0.20, 0.55, 0.25),
                       (0.60, 0.60, 0.65)]
        box_at(off + 2.9, 0.35, 0.0, 6.6, 0.7, 26.0, (0.35, 0.35, 0.38))
        for i, color in enumerate(seat_colors):
            box_at(off + 0.9 + i * 1.05, 0.78 + i * 0.52, 0.0,
                   1.05, 0.55, 26.0, color)
        box_at(off + 6.1, 2.3, 0.0, 0.4, 4.6, 26.0, (0.30, 0.30, 0.33))
        for sz in (-12.5, 12.5):
            for sx in (off + 0.7, off + 5.7):
                box_at(sx, 2.4, sz, 0.30, 4.8, 0.30, (0.22, 0.22, 0.25))
        box_at(off + 3.2, 4.85, 0.0, 7.2, 0.28, 27.0, self.theme["stripe_a"])
        glPopMatrix()

    def _emit_scenery(self):
        kind = self.theme["scenery"]
        for x, z, s, r, sort in self.scenery:
            glPushMatrix()
            glTranslatef(x, 0.0, z)
            glScalef(s, s, s)
            if sort == "building":
                glRotatef(r * 360.0, 0.0, 1.0, 0.0)
                self._building(kind, r)
            elif kind == "pine":
                self._pine((0.10, 0.38, 0.12), (0.12, 0.44, 0.14), (0.15, 0.50, 0.17))
            elif kind == "snow_pine":
                self._pine((0.22, 0.38, 0.30), (0.45, 0.58, 0.52), (0.85, 0.90, 0.92))
            elif r < 0.6:                                   # desert: cactus
                box_at(0.0, 1.3, 0.0, 0.55, 2.6, 0.55, (0.22, 0.52, 0.24))
                box_at(-0.62, 1.75, 0.0, 0.34, 0.95, 0.34, (0.24, 0.55, 0.26))
                box_at(0.62, 1.45, 0.0, 0.34, 0.95, 0.34, (0.24, 0.55, 0.26))
            else:                                           # desert: rock
                box_at(0.0, 0.5, 0.0, 2.2, 1.0, 1.7, (0.55, 0.52, 0.48))
                box_at(0.4, 1.1, 0.2, 1.1, 0.6, 0.9, (0.60, 0.57, 0.53))
            glPopMatrix()

    @staticmethod
    def _building(theme_kind, r):
        """A themed building: cottage / adobe block / alpine chalet.
        The gabled roofs use frustum() with a zero-width top rectangle,
        which lofts the walls up to a ridge line."""
        if theme_kind == "pine":                      # meadow cottage
            walls = [(0.86, 0.80, 0.68), (0.80, 0.72, 0.60),
                     (0.74, 0.78, 0.82)][int(r * 3) % 3]
            frustum((-2.8, 2.8, -2.3, 2.3), (-2.8, 2.8, -2.3, 2.3), 0.0, 2.8, walls)
            frustum((-3.1, 3.1, -2.6, 2.6), (0.0, 0.0, -2.6, 2.6), 2.8, 4.7, (0.58, 0.30, 0.20))
            box_at(0.0, 0.95, -2.35, 0.95, 1.9, 0.12, (0.35, 0.24, 0.15))   # door
            for sx in (-1.7, 1.7):
                box_at(sx, 1.8, -2.35, 0.95, 0.85, 0.12, GLASS)             # windows
        elif theme_kind == "desert":                  # adobe block
            frustum((-2.6, 2.6, -2.1, 2.1), (-2.5, 2.5, -2.0, 2.0), 0.0, 3.0, (0.83, 0.70, 0.52))
            frustum((-1.4, 1.4, -1.2, 1.2), (-1.3, 1.3, -1.1, 1.1), 3.0, 4.4, (0.80, 0.66, 0.48))
            box_at(0.0, 1.0, -2.12, 0.95, 2.0, 0.12, (0.30, 0.22, 0.15))    # doorway
            for sx in (-1.5, 1.5):
                box_at(sx, 2.1, -2.12, 0.75, 0.75, 0.12, (0.12, 0.10, 0.08))
        else:                                         # alpine chalet
            frustum((-2.7, 2.7, -2.3, 2.3), (-2.7, 2.7, -2.3, 2.3), 0.0, 3.0, (0.45, 0.32, 0.20))
            frustum((-3.2, 3.2, -2.7, 2.7), (0.0, 0.0, -2.7, 2.7), 3.0, 5.6, (0.92, 0.94, 0.97))
            box_at(0.0, 1.0, -2.35, 1.0, 2.0, 0.12, (0.30, 0.20, 0.12))     # door
            for sx in (-1.7, 1.7):
                # Warm glowing windows against the snow.
                box_at(sx, 1.9, -2.35, 0.9, 0.85, 0.12, (0.95, 0.82, 0.45))

    @staticmethod
    def _pine(c1, c2, c3):
        """Trunk + three foliage tiers (colors vary with the theme)."""
        box_at(0.0, 1.1, 0.0, 0.6, 2.2, 0.6, (0.42, 0.28, 0.14))
        box_at(0.0, 2.6, 0.0, 3.2, 1.6, 3.2, c1)
        box_at(0.0, 3.8, 0.0, 2.4, 1.4, 2.4, c2)
        box_at(0.0, 4.9, 0.0, 1.4, 1.2, 1.4, c3)


# --------------------------------------------------------------------- car
class Car:
    """
    A vehicle (player or AI): detailed body + arcade physics. Performance
    stats come from the chosen car model, so a SUPRA RZ genuinely out-drags
    a YARIS LE while the Yaris out-turns it.

    State:
        x, z     : position on the ground plane
        heading  : facing direction in radians (0 = facing -Z)
        speed    : signed scalar velocity along the heading
        wp_idx   : nearest track waypoint (progress/collision bookkeeping)
        lap      : completed start-line crossings
    """

    REVERSE_ACCEL = 11.0
    MAX_REVERSE_SPEED = -13.0
    ROLL_DECAY = 0.30         # rolling resistance (exponential decay per second)
    DRAG = 0.012              # aerodynamic drag ~ speed^2, per second

    def __init__(self, display_name, model, color):
        self.display_name = display_name
        self.model = model
        self.color = color
        stats = model["stats"]
        self.max_speed = stats["max_speed"]
        self.accel = stats["accel"]
        self.brake = stats["brake"]
        self.steer_rate = stats["steer"]

        self.x = self.z = 0.0
        self.heading = 0.0
        self.speed = 0.0
        self.wp_idx = 0
        self.lap = 0
        self.race_pos = 1
        self.visual_steer = 0.0   # smoothed steer angle for the front wheels
        self.wheel_roll = 0.0     # accumulated wheel rotation (radians)

    def place(self, x, z, heading, wp_idx):
        self.x, self.z, self.heading = x, z, heading
        self.speed = 0.0
        self.wp_idx = wp_idx
        self.lap = 0

    # -------------------------------------------------- physics update
    def update(self, dt, throttle, steer):
        """throttle and steer are in [-1, 1] (from a human or AI controller)."""

        # --- longitudinal: accelerate / brake / reverse ---
        if throttle > 0.0:
            self.speed += self.accel * throttle * dt
        elif throttle < 0.0:
            if self.speed > 0.5:
                self.speed += self.brake * throttle * dt      # braking
            else:
                self.speed += self.REVERSE_ACCEL * throttle * dt  # reversing

        # --- passive slowdown: rolling friction + quadratic drag ---
        # Both scale with dt so the physics are frame-rate independent.
        # Tuning note: thrust vs. these losses puts terminal velocity just
        # above max_speed, so the clamp below is what actually caps speed.
        self.speed *= math.exp(-self.ROLL_DECAY * dt)
        self.speed -= self.DRAG * self.speed * abs(self.speed) * dt
        if abs(self.speed) < 0.02 and throttle == 0.0:
            self.speed = 0.0
        self.speed = clamp(self.speed, self.MAX_REVERSE_SPEED, self.max_speed)

        # --- steering: yaw rate depends on current speed ---
        # No rotation when stationary; effect peaks mid-speed and the
        # turning radius widens again at top speed.
        if steer != 0.0 and abs(self.speed) > 0.1:
            ratio = min(abs(self.speed) / self.max_speed, 1.0)
            effect = math.sin(min(ratio * 2.0, 1.0) * math.pi / 2.0)
            effect *= (1.0 - 0.35 * ratio)
            direction = 1.0 if self.speed >= 0.0 else -1.0   # reverse flips steer
            self.heading += steer * self.steer_rate * effect * direction * dt
        self.visual_steer = lerp(self.visual_steer, steer, min(1.0, dt * 10.0))
        self.wheel_roll += self.speed * dt / self.model["wheel_radius"]

        # --- integrate position ---
        # heading 0 faces -Z, so the forward vector is (-sin h, 0, -cos h).
        self.x += -math.sin(self.heading) * self.speed * dt
        self.z += -math.cos(self.heading) * self.speed * dt

    # ------------------------------------------------------- rendering
    def draw(self):
        glPushMatrix()
        glTranslatef(self.x, 0.0, self.z)
        glRotatef(math.degrees(self.heading), 0.0, 1.0, 0.0)

        # Fake blob shadow: translucent dark quad just above the ground.
        sw, sl = self.model["shadow"]
        glDisable(GL_LIGHTING)
        glColor4f(0.0, 0.0, 0.0, 0.30)
        glBegin(GL_QUADS)
        glVertex3f(-sw / 2, 0.02, -sl / 2); glVertex3f(sw / 2, 0.02, -sl / 2)
        glVertex3f(sw / 2, 0.02, sl / 2); glVertex3f(-sw / 2, 0.02, sl / 2)
        glEnd()
        glEnable(GL_LIGHTING)

        draw_car_model(self.model, self.color,
                       self.visual_steer, math.degrees(self.wheel_roll))
        glPopMatrix()


# ------------------------------------------------------------- controllers
class HumanController:
    """Maps held keys to (throttle, steer). Key lists allow alternates."""

    def __init__(self, up, down, left, right):
        self.up, self.down, self.left, self.right = up, down, left, right

    def control(self, car, track, keys):
        throttle = 0.0
        if any(keys[k] for k in self.up):
            throttle = 1.0
        elif any(keys[k] for k in self.down):
            throttle = -1.0
        steer = 0.0
        if any(keys[k] for k in self.left):
            steer += 1.0
        if any(keys[k] for k in self.right):
            steer -= 1.0
        return throttle, steer


class AIController:
    """
    Waypoint-chasing driver:
      - Steers toward a waypoint ahead of the car; the lookahead distance
        grows with speed so the AI cuts smooth lines instead of zigzagging.
      - Sets a target speed from how much the track bends ahead (the angle
        between the current and a future track direction), braking before
        corners and flooring it on straights.
    `skill` scales the top speed so the field spreads out.
    """

    def __init__(self, skill):
        self.skill = skill

    def control(self, car, track, keys):
        look = 4 + int(abs(car.speed) * 0.35)
        tx, tz = track.wps[(car.wp_idx + look) % track.n]
        target_h = math.atan2(-(tx - car.x), -(tz - car.z))
        err = wrap_angle(target_h - car.heading)
        steer = clamp(err * 2.4, -1.0, 1.0)

        far = 10 + int(abs(car.speed) * 0.6)
        curve = abs(wrap_angle(track.heading_at((car.wp_idx + far) % track.n)
                               - track.heading_at(car.wp_idx)))
        desired = car.max_speed * self.skill * clamp(1.35 - curve * 0.85, 0.45, 1.0)
        if car.speed < desired - 1.0:
            throttle = 1.0
        elif car.speed > desired + 2.0:
            throttle = -1.0
        else:
            throttle = 0.0
        return throttle, steer


# ------------------------------------------------------------------ camera
class ChaseCamera:
    """
    Third-person chase camera. Each frame it computes a desired position
    behind/above its car and exponentially smooths toward it (frame-rate
    independent), so the view lags pleasantly through turns. The follow
    distance stretches slightly with speed for a sense of acceleration.
    """

    BASE_DIST = 11.0
    BASE_HEIGHT = 4.6
    STIFFNESS = 5.0

    def __init__(self, car):
        self.car = car
        self.snap()

    def snap(self):
        """Jump straight to the desired position (used at spawn/restart)."""
        d = self.BASE_DIST
        self.x = self.car.x + math.sin(self.car.heading) * d
        self.z = self.car.z + math.cos(self.car.heading) * d
        self.y = self.BASE_HEIGHT

    def update(self, dt):
        d = self.BASE_DIST + abs(self.car.speed) * 0.06
        target_x = self.car.x + math.sin(self.car.heading) * d
        target_z = self.car.z + math.cos(self.car.heading) * d
        target_y = self.BASE_HEIGHT + abs(self.car.speed) * 0.02
        t = 1.0 - math.exp(-self.STIFFNESS * dt)
        self.x = lerp(self.x, target_x, t)
        self.y = lerp(self.y, target_y, t)
        self.z = lerp(self.z, target_z, t)

    def apply_view(self):
        """
        Write the VIEW part of the MODELVIEW matrix. gluLookAt builds a
        matrix that moves the whole world so the camera sits at the origin
        looking down -Z. Must be applied before any model transforms.
        """
        gluLookAt(self.x, self.y, self.z,
                  self.car.x, 1.2, self.car.z,
                  0.0, 1.0, 0.0)


# -------------------------------------------------------------------- game
class Game:
    """Owns the window, OpenGL state, all menu/race states, and the loop."""

    def __init__(self):
        pygame.init()
        pygame.display.set_caption("3D Car Racing Simulator")
        # Ask for 4x multisample anti-aliasing (smooth polygon edges);
        # fall back to a plain context if the driver refuses.
        try:
            pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLEBUFFERS, 1)
            pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLESAMPLES, 4)
            pygame.display.set_mode((WINDOW_W, WINDOW_H),
                                    pygame.DOUBLEBUF | pygame.OPENGL)
        except pygame.error:
            pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLEBUFFERS, 0)
            pygame.display.gl_set_attribute(pygame.GL_MULTISAMPLESAMPLES, 0)
            pygame.display.set_mode((WINDOW_W, WINDOW_H),
                                    pygame.DOUBLEBUF | pygame.OPENGL)
        self._setup_opengl()
        self.shader = self._build_shader()

        self.text = TextRenderer()
        self.clock = pygame.time.Clock()

        self.quality_idx = 1               # default: MEDIUM
        self.map_idx = 0
        self.track = None
        self.world_list = None
        self.build_track(0)

        # States: menu -> car_select (-> car_select for P2) -> map_select -> race
        self.state = "menu"
        self.menu_time = 0.0
        self.running = True

        self.split = False
        self.free_play = False
        self.pending = (False, False)          # (split, free_play) being set up
        self.select_player = 0
        # Remembered picks per player: [P1, P2].
        self.selections = [{"model": 0, "color": 0}, {"model": 1, "color": 3}]

        self.cars = []
        self.controllers = []
        self.players = []                      # (car, camera) per human
        self.race_time = 0.0
        self.finish_order = []

    # ------------------------------------------------------------------
    def _setup_opengl(self):
        """One-time GL state. The PROJECTION matrix is set per viewport."""
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glEnable(GL_BLEND)                       # for shadows & HUD panels
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)    # tight rows for glDrawPixels
        # glScalef is used for scenery; renormalize normals so lighting
        # stays correct on scaled objects.
        glEnable(GL_NORMALIZE)
        try:
            glEnable(GL_MULTISAMPLE)             # honored if MSAA was granted
        except Exception:
            pass

        glEnable(GL_FOG)
        glFogi(GL_FOG_MODE, GL_LINEAR)

        # One directional light + color-material so glColor feeds lighting,
        # plus a mild specular highlight for a hint of paint gloss.
        glEnable(GL_LIGHT0)
        glLightfv(GL_LIGHT0, GL_AMBIENT, (0.45, 0.45, 0.45, 1.0))
        glLightfv(GL_LIGHT0, GL_DIFFUSE, (0.75, 0.75, 0.72, 1.0))
        glEnable(GL_COLOR_MATERIAL)
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE)
        glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, (0.35, 0.35, 0.35, 1.0))
        glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 24.0)

    @staticmethod
    def _build_shader():
        """
        Compile the per-pixel lighting shader. If the GPU/driver can't
        handle it, return None and the game falls back to the classic
        fixed-function lighting path.
        """
        try:
            from OpenGL.GL import shaders as glsl
            vs = glsl.compileShader(VERTEX_SHADER, GL_VERTEX_SHADER)
            fs = glsl.compileShader(FRAGMENT_SHADER, GL_FRAGMENT_SHADER)
            return glsl.compileProgram(vs, fs, validate=False)
        except Exception as exc:
            print(f"Shaders unavailable ({exc}); using fixed-function lighting.")
            return None

    @property
    def quality(self):
        return QUALITY_PRESETS[self.quality_idx][1]

    def _shader_on(self):
        if self.shader and self.quality["shader"]:
            glUseProgram(self.shader)

    def _shader_off(self):
        if self.shader and self.quality["shader"]:
            glUseProgram(0)

    def _draw_sky(self):
        """
        Gradient sky: a screen-space quad blending the horizon color into
        a deeper zenith color, drawn before the 3D world with the depth
        test off so everything renders over it. (The horizon color equals
        the fog color, so distant geometry melts into the sky.)
        """
        theme = self.track.theme
        begin_2d()
        glBegin(GL_QUADS)
        glColor3f(*theme["sky"])
        glVertex2f(0, 0); glVertex2f(WINDOW_W, 0)
        glColor3f(*theme["sky_top"])
        glVertex2f(WINDOW_W, WINDOW_H); glVertex2f(0, WINDOW_H)
        glEnd()
        end_2d()

    def _apply_projection(self, vp_w, vp_h):
        """
        Build the PROJECTION matrix for a viewport. Done per viewport per
        frame because split-screen halves have a different aspect ratio.
        """
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        gluPerspective(FOV_DEGREES, vp_w / vp_h, NEAR_PLANE, FAR_PLANE)
        glMatrixMode(GL_MODELVIEW)

    def build_track(self, idx):
        """Create the Track for a map, recompile its geometry, apply theme
        and quality (scenery density, fog distance), and precompute the
        minimap outline."""
        self.map_idx = idx
        if self.world_list is not None:
            glDeleteLists(self.world_list, 1)
        q = self.quality
        self.track = Track(MAPS[idx], scenery_count=int(90 * q["scenery"]))
        self.world_list = self.track.build_display_list()
        theme = self.track.theme
        r, g, b = theme["sky"]
        glClearColor(r, g, b, 1.0)
        glFogfv(GL_FOG_COLOR, (r, g, b, 1.0))
        glFogf(GL_FOG_START, theme["fog"][0] * q["fog"])
        glFogf(GL_FOG_END, theme["fog"][1] * q["fog"])

        # Minimap: scale the track outline into a small square, keeping
        # the aspect ratio. world (x, z) -> map pixels via _map_point().
        size = 140.0
        x0, x1, z0, z1 = self.track.bounds
        span = max(x1 - x0, z1 - z0) or 1.0
        self._mm_size = size
        self._mm_scale = size / span
        self._mm_off = ((size - (x1 - x0) * self._mm_scale) / 2,
                        (size - (z1 - z0) * self._mm_scale) / 2)
        self._mm_origin = (x0, z1)   # z flipped so north is up on screen
        self.minimap_pts = [self._map_point(x, z) for x, z in self.track.wps]

    def _map_point(self, x, z):
        """World (x, z) -> minimap-local (px, py), y up."""
        return ((x - self._mm_origin[0]) * self._mm_scale + self._mm_off[0],
                (self._mm_origin[1] - z) * self._mm_scale + self._mm_off[1])

    # ------------------------------------------------------------ race set-up
    def start_race(self, split, free_play=False):
        self.split = split
        self.free_play = free_play
        self.state = "race"
        # Free play skips the countdown entirely; races count down 3.. 2.. 1.
        self.race_time = 1.0 if free_play else -3.0
        self.finish_order = []
        self.cars, self.controllers, self.players = [], [], []

        if not free_play:
            skills = [0.97, 0.92, 0.88]
            if split:
                skills = skills[:2]          # 2 humans + 2 AI = 4 cars
            for i, skill in enumerate(skills):
                model = random.choice(CAR_MODELS)
                color = random.choice(PAINT_COLORS)[1]
                car = Car(f"CPU {i + 1}", model, color)
                self.cars.append(car)
                self.controllers.append(AIController(skill))

        sel = self.selections[0]
        p1 = Car("P1", CAR_MODELS[sel["model"]], PAINT_COLORS[sel["color"]][1])
        self.cars.append(p1)
        if split:
            self.controllers.append(HumanController(
                [pygame.K_UP], [pygame.K_DOWN], [pygame.K_LEFT], [pygame.K_RIGHT]))
            sel2 = self.selections[1]
            p2 = Car("P2", CAR_MODELS[sel2["model"]], PAINT_COLORS[sel2["color"]][1])
            self.cars.append(p2)
            self.controllers.append(HumanController(
                [pygame.K_w], [pygame.K_s], [pygame.K_a], [pygame.K_d]))
            self.players = [(p1, ChaseCamera(p1)), (p2, ChaseCamera(p2))]
        else:
            # Single player / free play: arrows and WASD both drive P1.
            self.controllers.append(HumanController(
                [pygame.K_UP, pygame.K_w], [pygame.K_DOWN, pygame.K_s],
                [pygame.K_LEFT, pygame.K_a], [pygame.K_RIGHT, pygame.K_d]))
            self.players = [(p1, ChaseCamera(p1))]

        # Starting grid: two columns just behind the start line, AI at the
        # front rows, players at the back.
        n = self.track.n
        for slot, car in enumerate(self.cars):
            idx = (n - 8 - slot * 4) % n
            (wx, wz) = self.track.wps[idx]
            (nx, nz) = self.track.normals[idx]
            side = 3.0 if slot % 2 == 0 else -3.0
            car.place(wx + nx * side, wz + nz * side,
                      self.track.heading_at(idx), idx)
        for _, cam in self.players:
            cam.snap()

    # ------------------------------------------------------------ main loop
    def run(self):
        while self.running:
            dt = min(self.clock.tick(FPS) / 1000.0, 0.05)

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    self._handle_key(event.key)

            if self.state == "race":
                self._update_race(dt)
                self._render_race()
            else:
                self.menu_time += dt
                if self.state == "menu":
                    self._render_menu()
                elif self.state == "car_select":
                    self._render_car_select()
                elif self.state == "map_select":
                    self._render_map_select()

            pygame.display.flip()

        pygame.quit()
        sys.exit()

    # ------------------------------------------------------------ input
    def _handle_key(self, key):
        confirm = (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_SPACE)

        if self.state == "menu":
            if key == pygame.K_ESCAPE:
                self.running = False
            elif key in (pygame.K_1, pygame.K_KP1):
                self.pending = (False, False)
                self.state, self.select_player = "car_select", 0
            elif key in (pygame.K_2, pygame.K_KP2):
                self.pending = (True, False)
                self.state, self.select_player = "car_select", 0
            elif key in (pygame.K_3, pygame.K_KP3):
                self.pending = (False, True)
                self.state, self.select_player = "car_select", 0
            elif key == pygame.K_g:
                # Cycle graphics quality and rebuild the world so the new
                # scenery density / fog distances take effect immediately.
                self.quality_idx = (self.quality_idx + 1) % len(QUALITY_PRESETS)
                self.build_track(self.map_idx)

        elif self.state == "car_select":
            sel = self.selections[self.select_player]
            if key == pygame.K_LEFT:
                sel["model"] = (sel["model"] - 1) % len(CAR_MODELS)
            elif key == pygame.K_RIGHT:
                sel["model"] = (sel["model"] + 1) % len(CAR_MODELS)
            elif key == pygame.K_UP:
                sel["color"] = (sel["color"] - 1) % len(PAINT_COLORS)
            elif key == pygame.K_DOWN:
                sel["color"] = (sel["color"] + 1) % len(PAINT_COLORS)
            elif key in confirm:
                if self.pending[0] and self.select_player == 0:
                    self.select_player = 1       # P2 picks next
                else:
                    self.state = "map_select"
            elif key == pygame.K_ESCAPE:
                if self.select_player == 1:
                    self.select_player = 0
                else:
                    self.state = "menu"

        elif self.state == "map_select":
            if key == pygame.K_LEFT:
                self.build_track((self.map_idx - 1) % len(MAPS))
            elif key == pygame.K_RIGHT:
                self.build_track((self.map_idx + 1) % len(MAPS))
            elif key in confirm:
                self.start_race(*self.pending)
            elif key == pygame.K_ESCAPE:
                self.state = "car_select"
                self.select_player = 1 if self.pending[0] else 0

        else:  # race
            if key == pygame.K_ESCAPE:
                self.state = "menu"
            elif key == pygame.K_r:
                self.start_race(self.split, self.free_play)

    # ------------------------------------------------------------ simulation
    def _update_race(self, dt):
        self.race_time += dt
        keys = pygame.key.get_pressed()
        green = self.race_time >= 0.0    # cars are frozen during countdown

        for car, ctrl in zip(self.cars, self.controllers):
            throttle, steer = ctrl.control(car, self.track, keys) if green else (0.0, 0.0)
            car.update(dt, throttle, steer)

        self._resolve_car_collisions()

        n = self.track.n
        for car in self.cars:
            # Progress + lap counting: detect the wrap-around past waypoint 0.
            new_idx = self.track.nearest_index(car.x, car.z, car.wp_idx)
            if car.wp_idx > n * 0.8 and new_idx < n * 0.2:
                car.lap += 1
                if (not self.free_play and car.lap > TOTAL_LAPS
                        and car not in self.finish_order):
                    self.finish_order.append(car)
            elif new_idx > n * 0.8 and car.wp_idx < n * 0.2:
                car.lap -= 1             # crossed the line backwards
            car.wp_idx = new_idx
            self.track.clamp_to_walls(car)

        # Race positions: order by total progress along the circuit.
        order = sorted(self.cars, key=lambda c: -(c.lap * n + c.wp_idx))
        for pos, car in enumerate(order):
            car.race_pos = pos + 1

        for _, cam in self.players:
            cam.update(dt)

    def _resolve_car_collisions(self):
        """Circle-vs-circle collision between every pair of cars: overlap is
        split evenly and both cars lose a little speed, so cars can nudge
        and block each other but never phase through."""
        radius = 2.5
        for i in range(len(self.cars)):
            for j in range(i + 1, len(self.cars)):
                a, b = self.cars[i], self.cars[j]
                dx, dz = b.x - a.x, b.z - a.z
                d2 = dx * dx + dz * dz
                if d2 < radius * radius and d2 > 1e-9:
                    d = math.sqrt(d2)
                    push = (radius - d) / 2.0
                    ux, uz = dx / d, dz / d
                    a.x -= ux * push; a.z -= uz * push
                    b.x += ux * push; b.z += uz * push
                    a.speed *= 0.97
                    b.speed *= 0.97

    # ------------------------------------------------------------- rendering
    def _render_scene(self, camera, vx, vy, vw, vh):
        """
        Render the 3D world into one viewport:
        glViewport confines drawing to a window rectangle, PROJECTION is
        rebuilt for its aspect ratio, then MODELVIEW = camera + models.
        """
        glViewport(vx, vy, vw, vh)
        self._draw_sky()                 # gradient backdrop, depth test off
        self._apply_projection(vw, vh)

        glLoadIdentity()                 # fresh MODELVIEW every frame
        camera.apply_view()              # VIEW: world -> camera space
        # Directional light direction is specified in world space, so it is
        # set *after* the camera transform (w=0 makes it directional).
        glLightfv(GL_LIGHT0, GL_POSITION, (0.4, 1.0, 0.3, 0.0))

        self._shader_on()                # per-pixel lighting from here on
        glCallList(self.world_list)      # static world in one GPU call
        glEnable(GL_LIGHTING)            # fallback path only; shader ignores it
        for car in self.cars:
            car.draw()
        glDisable(GL_LIGHTING)
        self._shader_off()               # HUD/text always use the fixed path

    def _render_race(self):
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        if self.split:
            half = WINDOW_H // 2
            viewports = [(0, half, WINDOW_W, WINDOW_H - half),   # P1 top
                         (0, 0, WINDOW_W, half)]                 # P2 bottom
        else:
            viewports = [(0, 0, WINDOW_W, WINDOW_H)]

        for (car, cam), vp in zip(self.players, viewports):
            self._render_scene(cam, *vp)

        glViewport(0, 0, WINDOW_W, WINDOW_H)
        begin_2d()
        if self.split:
            draw_rect_2d(0, WINDOW_H // 2 - 2, WINDOW_W, 4, (0.02, 0.02, 0.02))
        for (car, cam), vp in zip(self.players, viewports):
            self._draw_hud(car, *vp)
        end_2d()

    def _draw_speedometer(self, car, cx, cy, r):
        """
        NFS-style circular speed gauge: dark dial, tick marks, a red
        needle, and the numeric speed. The dial sweeps 240 degrees from
        lower-left (0 km/h) to lower-right (dial max).
        """
        kmh = abs(car.speed) * 3.6
        dial_max = max(160.0, car.max_speed * 3.6 * 1.15)

        # Dial disc.
        glColor4f(0.0, 0.0, 0.0, 0.55)
        glBegin(GL_TRIANGLE_FAN)
        glVertex2f(cx, cy)
        for i in range(41):
            a = 2.0 * math.pi * i / 40
            glVertex2f(cx + math.cos(a) * r, cy + math.sin(a) * r)
        glEnd()

        # Tick marks every 20 km/h; major ticks every 40.
        glLineWidth(2.0)
        glBegin(GL_LINES)
        v = 0
        while v <= dial_max:
            f = v / dial_max
            a = math.radians(210.0 - 240.0 * f)
            r0 = r * (0.78 if v % 40 == 0 else 0.86)
            glColor4f(1.0, 1.0, 1.0, 0.85)
            glVertex2f(cx + math.cos(a) * r0, cy + math.sin(a) * r0)
            glVertex2f(cx + math.cos(a) * r * 0.94, cy + math.sin(a) * r * 0.94)
            v += 20
        glEnd()

        # Needle: a thin triangle from the hub to the current speed.
        f = clamp(kmh / dial_max, 0.0, 1.0)
        a = math.radians(210.0 - 240.0 * f)
        tip = (cx + math.cos(a) * r * 0.82, cy + math.sin(a) * r * 0.82)
        px, py = math.cos(a + math.pi / 2) * 3.0, math.sin(a + math.pi / 2) * 3.0
        glColor4f(0.95, 0.15, 0.15, 0.95)
        glBegin(GL_TRIANGLES)
        glVertex2f(cx + px, cy + py)
        glVertex2f(cx - px, cy - py)
        glVertex2f(*tip)
        glEnd()
        glBegin(GL_TRIANGLE_FAN)          # hub dot
        glVertex2f(cx, cy)
        for i in range(13):
            b = 2.0 * math.pi * i / 12
            glVertex2f(cx + math.cos(b) * 5.0, cy + math.sin(b) * 5.0)
        glEnd()

        self.text.draw_centered(f"{int(kmh)}", cx, cy - r * 0.62, 36, (255, 255, 255))
        self.text.draw_centered("km/h", cx, cy - r * 0.88, 22, (190, 190, 200))

    def _draw_minimap(self, vx, vy):
        """Track outline with a dot per car (players ringed in white)."""
        size = self._mm_size
        ox, oy = vx + 22, vy + 22
        draw_rect_2d(ox - 8, oy - 8, size + 16, size + 16, (0, 0, 0), 0.40)

        glLineWidth(3.0)
        glColor4f(0.92, 0.92, 0.95, 0.9)
        glBegin(GL_LINE_LOOP)
        for px, py in self.minimap_pts[::2]:
            glVertex2f(ox + px, oy + py)
        glEnd()

        player_cars = {car for car, _ in self.players}
        for car in self.cars:
            px, py = self._map_point(car.x, car.z)
            if car in player_cars:        # white ring highlights humans
                draw_rect_2d(ox + px - 5, oy + py - 5, 10, 10, (1.0, 1.0, 1.0))
            draw_rect_2d(ox + px - 3.5, oy + py - 3.5, 7, 7, car.color)

    def _draw_hud(self, car, vx, vy, vw, vh):
        self._draw_minimap(vx, vy)
        radius = 62 if self.split else 78
        self._draw_speedometer(car, vx + vw - radius - 24, vy + radius + 24, radius)

        draw_rect_2d(vx + 10, vy + vh - 54, 230, 44, (0, 0, 0), 0.40)
        if self.free_play:
            # Laps are unlimited in free play; just count them up.
            self.text.draw(f"LAP {max(car.lap, 1)}   FREE PLAY",
                           vx + 22, vy + vh - 42, 28, (255, 255, 255))
        else:
            lap = clamp(car.lap, 1, TOTAL_LAPS)
            self.text.draw(f"LAP {lap}/{TOTAL_LAPS}   POS {car.race_pos}/{len(self.cars)}",
                           vx + 22, vy + vh - 42, 28, (255, 255, 255))

        if self.split:
            label = f"{car.display_name} - {car.model['name']}"
            self.text.draw(label, vx + vw - 30 - self.text.width(label, 28),
                           vy + vh - 42, 28, (255, 220, 90))

        cx, cy = vx + vw / 2, vy + vh * 0.55
        if self.race_time < 0.0:
            self.text.draw_centered(str(math.ceil(-self.race_time)),
                                    cx, cy, 96, (255, 230, 80))
        elif self.race_time < 1.0:
            self.text.draw_centered("GO!", cx, cy, 96, (120, 255, 120))
        elif car in self.finish_order:
            place = self.finish_order.index(car) + 1
            self.text.draw_centered(f"FINISHED  -  P{place}",
                                    cx, cy, 64, (255, 230, 80))

    # -------------------------------------------------------- menu screens
    def _render_world_orbit(self):
        """Slow orbit camera around the current map (menu backdrop)."""
        theme = self.track.theme
        glClearColor(theme["sky"][0], theme["sky"][1], theme["sky"][2], 1.0)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glViewport(0, 0, WINDOW_W, WINDOW_H)
        self._draw_sky()
        self._apply_projection(WINDOW_W, WINDOW_H)
        glLoadIdentity()
        a = self.menu_time * 0.15
        x0, x1, z0, z1 = self.track.bounds
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        r = max(x1 - x0, z1 - z0) * 0.85
        gluLookAt(cx + math.sin(a) * r, r * 0.45, cz + math.cos(a) * r,
                  cx, 0.0, cz,
                  0.0, 1.0, 0.0)
        glLightfv(GL_LIGHT0, GL_POSITION, (0.4, 1.0, 0.3, 0.0))
        self._shader_on()
        glCallList(self.world_list)
        self._shader_off()

    def _render_menu(self):
        self._render_world_orbit()
        begin_2d()
        draw_rect_2d(0, 0, WINDOW_W, WINDOW_H, (0.0, 0.0, 0.05), 0.45)
        cx = WINDOW_W / 2
        self.text.draw_centered("3D CAR RACING", cx, WINDOW_H - 190, 96, (255, 255, 255))
        self.text.draw_centered(f"{TOTAL_LAPS} laps  -  first across the line wins",
                                cx, WINDOW_H - 240, 30, (200, 210, 230))
        self.text.draw_centered("1  -  SINGLE PLAYER", cx, 350, 44, (120, 255, 140))
        self.text.draw_centered("2  -  SPLIT SCREEN", cx, 300, 44, (120, 200, 255))
        self.text.draw_centered("3  -  FREE PLAY", cx, 250, 44, (255, 200, 120))
        self.text.draw_centered(f"G  -  GRAPHICS: {QUALITY_PRESETS[self.quality_idx][0]}",
                                cx, 205, 36, (220, 160, 255))
        self.text.draw_centered("then pick your car, paint and track", cx, 160, 28, (200, 200, 200))
        self.text.draw_centered("P1: arrows    P2: W/S/A/D    R: restart    ESC: back",
                                cx, 132, 28, (200, 200, 200))
        end_2d()

    def _render_car_select(self):
        """Showroom: rotating car on a podium + stats and paint picker."""
        glClearColor(0.07, 0.08, 0.11, 1.0)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        glViewport(0, 0, WINDOW_W, WINDOW_H)
        self._apply_projection(WINDOW_W, WINDOW_H)
        glLoadIdentity()
        gluLookAt(4.6, 2.6, 6.4, 0.0, 0.7, 0.0, 0.0, 1.0, 0.0)
        glLightfv(GL_LIGHT0, GL_POSITION, (0.4, 1.0, 0.3, 0.0))

        # Showroom floor + podium disc.
        self._shader_on()
        glNormal3f(0.0, 1.0, 0.0)
        glColor3f(0.10, 0.11, 0.14)
        glBegin(GL_QUADS)
        glVertex3f(-60, 0, -60); glVertex3f(60, 0, -60)
        glVertex3f(60, 0, 60); glVertex3f(-60, 0, 60)
        glEnd()
        glColor3f(0.20, 0.21, 0.25)
        glBegin(GL_TRIANGLE_FAN)
        glVertex3f(0.0, 0.02, 0.0)
        for i in range(33):
            ang = 2.0 * math.pi * i / 32
            glVertex3f(math.cos(ang) * 3.4, 0.02, math.sin(ang) * 3.4)
        glEnd()

        sel = self.selections[self.select_player]
        model = CAR_MODELS[sel["model"]]
        paint_name, paint = PAINT_COLORS[sel["color"]]
        glEnable(GL_LIGHTING)
        glPushMatrix()
        glRotatef(self.menu_time * 40.0, 0.0, 1.0, 0.0)
        draw_car_model(model, paint)
        glPopMatrix()
        glDisable(GL_LIGHTING)
        self._shader_off()

        # ---- overlay ----
        begin_2d()
        cx = WINDOW_W / 2
        who = "P1" if self.select_player == 0 else "P2"
        who_color = (255, 120, 120) if self.select_player == 0 else (255, 190, 110)
        self.text.draw_centered(f"{who}  -  CHOOSE YOUR CAR", cx, WINDOW_H - 70, 52, who_color)
        self.text.draw_centered(f"<   {model['name']}   >", cx, WINDOW_H - 130, 56, (255, 255, 255))
        self.text.draw_centered(model["tag"], cx, WINDOW_H - 168, 28, (190, 200, 215))

        # Stat bars.
        stats = model["stats"]
        bars = [("SPEED", stats["max_speed"] / 36.0),
                ("ACCEL", stats["accel"] / 26.0),
                ("GRIP", stats["steer"] / 2.9)]
        for i, (label, frac) in enumerate(bars):
            y = 210 - i * 44
            self.text.draw(label, 60, y + 4, 28, (200, 200, 200))
            draw_rect_2d(150, y, 240, 24, (0.25, 0.25, 0.30), 0.9)
            draw_rect_2d(150, y, 240 * clamp(frac, 0.0, 1.0), 24, (0.30, 0.75, 0.35))

        # Paint swatches.
        self.text.draw_centered(paint_name, cx, 120, 30, (230, 230, 230))
        total_w = len(PAINT_COLORS) * 52
        for i, (_, rgb) in enumerate(PAINT_COLORS):
            x = cx - total_w / 2 + i * 52
            if i == sel["color"]:
                draw_rect_2d(x - 4, 62, 48, 48, (1.0, 1.0, 1.0))
            draw_rect_2d(x, 66, 40, 40, rgb)
        self.text.draw_centered(
            "LEFT/RIGHT car    UP/DOWN paint    ENTER confirm    ESC back",
            cx, 26, 26, (170, 175, 190))
        end_2d()

    def _render_map_select(self):
        self._render_world_orbit()
        begin_2d()
        draw_rect_2d(0, 0, WINDOW_W, 130, (0.0, 0.0, 0.05), 0.55)
        draw_rect_2d(0, WINDOW_H - 150, WINDOW_W, 150, (0.0, 0.0, 0.05), 0.55)
        cx = WINDOW_W / 2
        spec = MAPS[self.map_idx]
        self.text.draw_centered("CHOOSE TRACK", cx, WINDOW_H - 66, 48, (255, 255, 255))
        self.text.draw_centered(f"<   {spec['name']}   >", cx, WINDOW_H - 122, 52, (255, 230, 120))
        self.text.draw_centered(spec["tag"], cx, 86, 30, (210, 215, 230))
        self.text.draw_centered("LEFT/RIGHT browse    ENTER start race    ESC back",
                                cx, 40, 26, (170, 175, 190))
        end_2d()


if __name__ == "__main__":
    Game().run()
