"""
3D Car Racing Simulator — Panda3D edition, NFS Most Wanted style
================================================================
Engine: Panda3D (https://www.panda3d.org) — a full open-source 3D game
engine (used in commercial titles).

Rendering features:
    - Real 3D car models (CC0 "Car Kit" by Kenney, kenney.nl) with
      palette-recolored body paint, steering and spinning wheels
    - NFS Most Wanted 2005 post-process shader: olive/sepia color grade,
      crushed contrast, desaturation and a heavy vignette
    - Weather system: CLEAR / RAIN / STORM / SNOW with falling
      precipitation, lightning flashes, thunder + rain audio
      (procedurally synthesized), wet reflective asphalt and reduced grip
    - Real-time shadow mapping, per-pixel lighting via the shader
      generator, procedural textures, gradient sky dome, fog, 4x MSAA

Game features:
    - Cars: COROLLA GT / SUPRA RZ / YARIS LE with distinct stats
    - 8 paint colors chosen in a rotating showroom
    - 3 themed maps (meadow / desert / alpine) with buildings & grandstand
    - Solid wall + car-vs-car collisions, waypoint AI opponents
    - Single player, two-player split screen, and free play
    - NFS-style HUD: speedometer gauge, minimap, lap/position panel
    - Graphics quality presets: LOW / MEDIUM / HIGH (G on the menu)

Controls:
    Menus       : 1/2/3 pick mode, arrows browse, ENTER confirm, ESC back
    Menu extras : G graphics, T weather, L laps, O opponents,
                  P police (free play), F free-play split
    In race     : C cycle camera (chase / hood / top-down),
                  R restart, ESC back to menu
    Player 1    : arrow keys (WASD also works in single player)
    Player 2    : W/S/A/D (split screen)
    Mobile      : on-screen joystick + buttons (auto on Android, or --mobile)
    Online      : 4 from the menu, then host/join a Firebase room and chat
    Gun mode    : 5 gun combat, or U to arm any race / online session
                  CTRL or FIRE to shoot (P2: Q)

The classic pure-OpenGL version is preserved in main_classic.py.
"""

import colorsys
import math
import os
import random
import struct
import sys
import time
import wave

import firebase_mp

from panda3d.core import loadPrcFileData

WINDOW_W, WINDOW_H = 1280, 720


def detect_android():
    return (sys.platform == "android"
            or "ANDROID_ROOT" in os.environ
            or "ANDROID_ARGUMENT" in os.environ)


def detect_touch_default():
    return (detect_android()
            or "--mobile" in sys.argv
            or bool(os.environ.get("CARSIM_MOBILE")))


ANDROID = detect_android()
TOUCH_DEFAULT = detect_touch_default()
USE_GLES = ANDROID

# Engine configuration must be loaded before the window is opened.
# The display/audio plugins are named explicitly because a frozen
# (PyInstaller) build cannot auto-locate Panda3D's etc/*.prc files.
if USE_GLES:
    # Android only has OpenGL ES.
    loadPrcFileData("", "load-display pandagles2")
    loadPrcFileData("", "aux-display pandagles")
else:
    loadPrcFileData("", "load-display pandagl")
loadPrcFileData("", "audio-library-name p3openal_audio")
if not ANDROID:
    loadPrcFileData("", f"win-size {WINDOW_W} {WINDOW_H}")
loadPrcFileData("", "window-title 3D Car Racing Simulator")
loadPrcFileData("", "color-bits 24")
loadPrcFileData("", "red-bits 8")
loadPrcFileData("", "green-bits 8")
loadPrcFileData("", "blue-bits 8")
loadPrcFileData("", "alpha-bits 8")
loadPrcFileData("", "depth-bits 24")
if USE_GLES:
    loadPrcFileData("", "framebuffer-multisample 0")
else:
    loadPrcFileData("", "framebuffer-multisample 1")
    loadPrcFileData("", "multisamples 4")
loadPrcFileData("", "textures-power-2 none")
loadPrcFileData("", "sync-video true")
# GLSL shader generator (not NVIDIA Cg). Avoids missing-Cg / compile errors.
loadPrcFileData("", "basic-shaders-only true")
if os.environ.get("CARSIM_OFFSCREEN"):
    loadPrcFileData("", "window-type offscreen")   # used by automated tests
    loadPrcFileData("", "audio-library-name null")
    loadPrcFileData("", "framebuffer-multisample 0")
    loadPrcFileData("", "multisamples 0")

import gltf   # panda3d-gltf: load .glb via gltf.load_model / GltfLoader
from direct.filter.FilterManager import FilterManager
from direct.gui.OnscreenText import OnscreenText
from direct.showbase.ShowBase import ShowBase
from panda3d.core import (AmbientLight, AntialiasAttrib, BitMask32,
                          CardMaker, Camera, ClockObject, CullFaceAttrib,
                          DepthOffsetAttrib,
                          DirectionalLight, Filename, Fog, FrameBufferProperties,
                          Geom, GeomNode, GeomTriangles, GeomVertexData,
                          GeomVertexFormat, GeomVertexReader, GeomVertexWriter,
                          InternalName, LineSegs, LoaderFileTypeRegistry,
                          Material, MouseButton,
                          NodePath, PNMImage, PerspectiveLens, RenderState,
                          Shader, TextNode, Texture, TextureStage,
                          TransparencyAttrib, Vec3)

# ------------------------------------------------------------------ config
FOV_DEGREES = 68.0
FPS = 60
DEFAULT_LAPS = 3
ASPECT = WINDOW_W / WINDOW_H
MAX_DIAL_KMH = 500.0          # speedometer top mark
STAT_TOP = {"max_speed": 139.0, "accel": 38.0, "steer": 2.90}  # stat-bar scale
LAP_OPTIONS = [1, 3, 5, 7]
OPPONENT_OPTIONS = [1, 2, 3, 4, 5]
CHECKPOINT_COUNT = 4
CAMERA_MODES = ["CHASE", "HOOD", "TOP"]
HP_MAX = 100
GUN_DAMAGE = 24
GUN_COOLDOWN = 0.20
BULLET_SPEED = 92.0
BULLET_LIFE = 1.35
WRECK_TIME = 3.2

# Graphics quality presets, cycled with G on the main menu.
QUALITY_PRESETS = [
    ("LOW", {"shadow": 0, "scenery": 0.4, "fog": 0.6}),
    ("MEDIUM", {"shadow": 1024, "scenery": 1.0, "fog": 1.0}),
    ("HIGH", {"shadow": 2048, "scenery": 1.6, "fog": 1.3}),
]

# Weather presets, cycled with T on the main menu.
#   gloom     0..1 blend of the map's sky toward storm grey
#   sun/amb   light dimming, fog_mult tightens visibility
#   precip    overlay type, grip scales acceleration & steering
WEATHERS = [
    ("CLEAR", {"gloom": 0.00, "sun": 1.00, "amb": 1.00, "fog_mult": 1.00,
               "precip": None, "fall": 0.0, "lightning": False,
               "grip": 1.00, "wet": False, "rain_vol": 0.0}),
    ("RAIN", {"gloom": 0.55, "sun": 0.62, "amb": 1.00, "fog_mult": 0.70,
              "precip": "rain", "fall": 2.1, "lightning": False,
              "grip": 0.85, "wet": True, "rain_vol": 0.5}),
    ("STORM", {"gloom": 0.85, "sun": 0.50, "amb": 0.92, "fog_mult": 0.58,
               "precip": "rain", "fall": 3.0, "lightning": True,
               "grip": 0.78, "wet": True, "rain_vol": 0.8}),
    ("SNOW", {"gloom": 0.45, "sun": 0.72, "amb": 1.10, "fog_mult": 0.60,
              "precip": "snow", "fall": 0.55, "lightning": False,
              "grip": 0.72, "wet": False, "rain_vol": 0.0}),
]

STORM_SKY = (0.30, 0.32, 0.36)
STORM_SKY_TOP = (0.16, 0.17, 0.21)

# --- NFS Most Wanted 2005 look: full-screen post-process color grade ---
# The scene is rendered into a texture, then this shader applies the
# signature olive/sepia tint, partial desaturation, a filmic S-curve
# contrast boost and a heavy corner vignette. `flash` is driven by the
# lightning system to white out the frame during strikes.
GRADE_VERT = """
#version 120
uniform mat4 p3d_ModelViewProjectionMatrix;
attribute vec4 p3d_Vertex;
attribute vec2 p3d_MultiTexCoord0;
varying vec2 uv;
void main() {
    gl_Position = p3d_ModelViewProjectionMatrix * p3d_Vertex;
    uv = p3d_MultiTexCoord0;
}
"""

GRADE_FRAG = """
#version 120
uniform sampler2D tex;
uniform float flash;
varying vec2 uv;
void main() {
    vec3 c = texture2D(tex, uv).rgb;
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(luma), 0.18);                 // desaturate
    c *= vec3(1.08, 1.04, 0.86);                  // olive / sepia tint
    c = mix(c, c * c * (3.0 - 2.0 * c), 0.18);    // filmic S-curve
    c = (c - 0.5) * 1.06 + 0.52;                  // mild contrast, keep shadows
    vec2 d = uv - vec2(0.5, 0.5);
    c *= 1.0 - dot(d, d) * 0.58;                  // vignette
    c += vec3(flash);                             // lightning white-out
    gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

GRADE_VERT_ES = """
#version 100
uniform mat4 p3d_ModelViewProjectionMatrix;
attribute vec4 p3d_Vertex;
attribute vec2 p3d_MultiTexCoord0;
varying vec2 uv;
void main() {
    gl_Position = p3d_ModelViewProjectionMatrix * p3d_Vertex;
    uv = p3d_MultiTexCoord0;
}
"""

GRADE_FRAG_ES = """
#version 100
precision mediump float;
uniform sampler2D tex;
uniform float flash;
varying vec2 uv;
void main() {
    vec3 c = texture2D(tex, uv).rgb;
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(luma), 0.18);
    c *= vec3(1.08, 1.04, 0.86);
    c = mix(c, c * c * (3.0 - 2.0 * c), 0.18);
    c = (c - 0.5) * 1.06 + 0.52;
    vec2 d = uv - vec2(0.5, 0.5);
    c *= 1.0 - dot(d, d) * 0.58;
    c += vec3(flash);
    gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

# Draw-mask bits: rain rigs are hidden from the other player's camera
# and from the sun's shadow camera (falling rain must not cast shadows).
MASK_CAM1 = BitMask32.bit(1)
MASK_CAM2 = BitMask32.bit(2)
MASK_SHADOW = BitMask32.bit(3)

GLASS = (0.10, 0.12, 0.16, 1.0)
TRIM = (0.13, 0.13, 0.15, 1.0)

# World frame: Panda3D is Z-up, +Y forward. The ground is the X/Y plane.


# ---------------------------------------------------------------- utilities
def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def lerp(a, b, t):
    return a + (b - a) * t


def wrap_angle(a):
    return (a + math.pi) % (2.0 * math.pi) - math.pi


def catmull_rom(points, samples_per_seg):
    """Sample a closed Catmull-Rom spline through the given control points."""
    n = len(points)
    out = []
    for i in range(n):
        p0, p1 = points[(i - 1) % n], points[i]
        p2, p3 = points[(i + 1) % n], points[(i + 2) % n]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out


# ------------------------------------------------------------ mesh building
class MeshBuilder:
    """
    Accumulates quads/triangles into a single Panda3D Geom. Every vertex
    carries position, normal, color and UV, so one mesh can mix textured
    and vertex-colored surfaces and everything works with the engine's
    per-pixel shader generator and shadow mapping.
    """

    def __init__(self, name):
        self.name = name
        self.fmt = GeomVertexFormat.get_v3n3c4t2()
        self.vdata = GeomVertexData(name, self.fmt, Geom.UHStatic)
        self.vw = GeomVertexWriter(self.vdata, "vertex")
        self.nw = GeomVertexWriter(self.vdata, "normal")
        self.cw = GeomVertexWriter(self.vdata, "color")
        self.tw = GeomVertexWriter(self.vdata, "texcoord")
        self.prim = GeomTriangles(Geom.UHStatic)
        self.count = 0

    def _vertex(self, p, n, color, uv):
        self.vw.addData3(*p)
        self.nw.addData3(*n)
        self.cw.addData4(*color)
        self.tw.addData2(*uv)
        self.count += 1
        return self.count - 1

    def quad(self, v0, v1, v2, v3, color, uvs=None, normal=None):
        """One quad; the normal is computed from the corners unless given."""
        if normal is None:
            e1 = Vec3(*v1) - Vec3(*v0)
            e2 = Vec3(*v3) - Vec3(*v0)
            n = e1.cross(e2)
            if n.lengthSquared() < 1e-12:
                n = Vec3(0, 0, 1)
            n.normalize()
            normal = (n.x, n.y, n.z)
        if uvs is None:
            uvs = ((0, 0), (1, 0), (1, 1), (0, 1))
        if len(color) == 3:
            color = (*color, 1.0)
        idx = [self._vertex(v, normal, color, uv)
               for v, uv in zip((v0, v1, v2, v3), uvs)]
        self.prim.addVertices(idx[0], idx[1], idx[2])
        self.prim.addVertices(idx[0], idx[2], idx[3])

    def tri(self, v0, v1, v2, color, normal):
        if len(color) == 3:
            color = (*color, 1.0)
        idx = [self._vertex(v, normal, color, (0, 0)) for v in (v0, v1, v2)]
        self.prim.addVertices(*idx)

    def frustum(self, bottom, top, z0, z1, color):
        """
        Tapered box between two footprint rectangles (x0, x1, y0, y1) at
        heights z0/z1 — the building block for sloped car panels & roofs.
        """
        bx0, bx1, by0, by1 = bottom
        tx0, tx1, ty0, ty1 = top
        a, b = (bx0, by0, z0), (bx1, by0, z0)
        c, d = (bx1, by1, z0), (bx0, by1, z0)
        e, f = (tx0, ty0, z1), (tx1, ty0, z1)
        g, h = (tx1, ty1, z1), (tx0, ty1, z1)
        self.quad(e, f, g, h, color)      # top    (+Z)
        self.quad(a, d, c, b, color)      # bottom (-Z)
        self.quad(a, b, f, e, color)      # front  (-Y)
        self.quad(c, d, h, g, color)      # rear   (+Y)
        self.quad(d, a, e, h, color)      # left   (-X)
        self.quad(b, c, g, f, color)      # right  (+X)

    def box(self, cx, cy, cz, w, l, h, color):
        r = (cx - w / 2, cx + w / 2, cy - l / 2, cy + l / 2)
        self.frustum(r, r, cz - h / 2, cz + h / 2, color)

    def cylinder_x(self, cx, cy, cz, radius, width, color, segments=18):
        """Cylinder along the X axis (an axle) with end caps."""
        hw = width / 2.0
        ring = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            ring.append((math.cos(a) * radius, math.sin(a) * radius))
        for i in range(segments):
            y0, z0 = ring[i]
            y1, z1 = ring[(i + 1) % segments]
            n0 = (0, y0 / radius, z0 / radius)
            n1 = (0, y1 / radius, z1 / radius)
            i0 = self._vertex((cx - hw, cy + y0, cz + z0), n0, (*color, 1.0), (0, 0))
            i1 = self._vertex((cx + hw, cy + y0, cz + z0), n0, (*color, 1.0), (1, 0))
            i2 = self._vertex((cx + hw, cy + y1, cz + z1), n1, (*color, 1.0), (1, 1))
            i3 = self._vertex((cx - hw, cy + y1, cz + z1), n1, (*color, 1.0), (0, 1))
            self.prim.addVertices(i0, i1, i2)
            self.prim.addVertices(i0, i2, i3)
        for side, nx in ((-hw, -1.0), (hw, 1.0)):
            for i in range(segments):
                y0, z0 = ring[i]
                y1, z1 = ring[(i + 1) % segments]
                self.tri((cx + side, cy, cz),
                         (cx + side, cy + y0, cz + z0),
                         (cx + side, cy + y1, cz + z1), color, (nx, 0, 0))

    def disc_x(self, cx, cy, cz, radius, color, segments=14):
        """Flat disc facing +/-X (wheel hub cap)."""
        for i in range(segments):
            a0 = 2.0 * math.pi * i / segments
            a1 = 2.0 * math.pi * (i + 1) / segments
            nx = 1.0 if cx >= 0 else -1.0
            self.tri((cx, cy, cz),
                     (cx, cy + math.cos(a0) * radius, cz + math.sin(a0) * radius),
                     (cx, cy + math.cos(a1) * radius, cz + math.sin(a1) * radius),
                     color, (nx, 0, 0))

    def build(self):
        geom = Geom(self.vdata)
        geom.addPrimitive(self.prim)
        node = GeomNode(self.name)
        node.addGeom(geom)
        return NodePath(node)


# -------------------------------------------------------- procedural textures
def make_noise_texture(name, base, variation=0.05, size=256, checker=0.0,
                       speckle=0.0, speckle_color=(1.0, 1.0, 1.0)):
    """
    Generate a tileable noise texture entirely in code (no image files).
    `checker` darkens alternating halves for a subtle tile pattern;
    `speckle` sprinkles brighter/darker flecks (asphalt aggregate).
    """
    rng = random.Random(hash(name) & 0xFFFF)
    img = PNMImage(size, size)
    half = size // 2
    for y in range(size):
        for x in range(size):
            f = 1.0 + rng.uniform(-variation, variation)
            if checker and ((x // half) + (y // half)) % 2 == 0:
                f *= (1.0 - checker)
            r = clamp(base[0] * f, 0.0, 1.0)
            g = clamp(base[1] * f, 0.0, 1.0)
            b = clamp(base[2] * f, 0.0, 1.0)
            if speckle and rng.random() < speckle:
                m = rng.uniform(0.4, 1.0)
                r = lerp(r, speckle_color[0], m)
                g = lerp(g, speckle_color[1], m)
                b = lerp(b, speckle_color[2], m)
            img.setXel(x, y, r, g, b)
    tex = Texture(name)
    tex.load(img)
    tex.setWrapU(Texture.WM_repeat)
    tex.setWrapV(Texture.WM_repeat)
    tex.setMinfilter(Texture.FT_linear_mipmap_linear)
    tex.setMagfilter(Texture.FT_linear)
    tex.setAnisotropicDegree(8)
    return tex


def make_precip_texture(kind):
    """Tileable RGBA texture of rain streaks or snow flakes on alpha 0."""
    size = 128
    img = PNMImage(size, size, 4)
    img.fill(0.75, 0.80, 0.92)
    img.alphaFill(0.0)
    rng = random.Random(11 if kind == "rain" else 12)
    if kind == "rain":
        for _ in range(46):
            x = rng.randrange(size)
            y0 = rng.randrange(size)
            length = rng.randint(18, 42)
            a = rng.uniform(0.16, 0.38)
            for k in range(length):
                img.setAlpha(x, (y0 + k) % size, a * (1.0 - k / length * 0.4))
    else:
        for _ in range(70):
            x = rng.randrange(size)
            y = rng.randrange(size)
            a = rng.uniform(0.5, 0.95)
            r = rng.choice((0, 1))
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    img.setAlpha((x + dx) % size, (y + dy) % size, a)
            img.setXel(x, y, 0.95, 0.96, 1.0)
    tex = Texture(f"precip-{kind}")
    tex.load(img)
    tex.setWrapU(Texture.WM_repeat)
    tex.setWrapV(Texture.WM_repeat)
    tex.setMinfilter(Texture.FT_linear)
    tex.setMagfilter(Texture.FT_linear)
    return tex


class PrecipRig:
    """
    Camera-following precipitation: three concentric open cylinders with
    a scrolling rain/snow texture, giving cheap parallax layers of
    falling drops the way PS2-era racers did it.
    """

    LAYERS = [   # radius, height, texture repeats around, scroll factor
        # One texture tile spans ~4 world units so streaks stay thin.
        (10.0, 15.0, 16.0, 1.00),
        (19.0, 24.0, 30.0, 0.72),
        (32.0, 36.0, 50.0, 0.50),
    ]

    def __init__(self, parent, kind, fall_speed, hide_mask):
        self.root = parent.attachNewNode("precip")
        self.fall = fall_speed
        self.layers = []
        tex = make_precip_texture(kind)
        for radius, height, repeats, factor in self.LAYERS:
            mb = MeshBuilder("precip-layer")
            seg = 24
            for i in range(seg):
                a0 = 2 * math.pi * i / seg
                a1 = 2 * math.pi * (i + 1) / seg
                u0 = repeats * i / seg
                u1 = repeats * (i + 1) / seg
                x0, y0 = math.cos(a0) * radius, math.sin(a0) * radius
                x1, y1 = math.cos(a1) * radius, math.sin(a1) * radius
                vrep = height / 6.0     # ~6 world units per vertical tile
                mb.quad((x0, y0, -height * 0.35), (x1, y1, -height * 0.35),
                        (x1, y1, height * 0.65), (x0, y0, height * 0.65),
                        (1, 1, 1, 1),
                        uvs=((u0, 0), (u1, 0), (u1, vrep), (u0, vrep)),
                        normal=(0, 0, 1))
            layer = mb.build()
            layer.reparentTo(self.root)
            layer.setTexture(tex)
            layer.setTwoSided(True)
            layer.setTransparency(TransparencyAttrib.MAlpha)
            layer.setDepthWrite(False)
            layer.setBin("transparent", 30)
            layer.setLightOff(1)
            layer.setFogOff(1)
            self.layers.append([layer, factor, 0.0])
        self.root.hide(hide_mask)

    def update(self, dt, campos):
        self.root.setPos(campos)
        for entry in self.layers:
            layer, factor, off = entry
            off = (off + self.fall * factor * dt) % 1.0
            entry[2] = off
            layer.setTexOffset(TextureStage.getDefault(), off * 0.13, off)

    def destroy(self):
        self.root.removeNode()


# --------------------------------------------------- procedural audio (SFX)
def synth_weather_sounds():
    """
    Synthesize rain-loop and thunder WAV files in the temp folder (once)
    so the game needs no bundled audio assets. Returns (rain, thunder)
    paths.
    """
    import tempfile
    out_dir = os.path.join(tempfile.gettempdir(), "carsim3d_sfx")
    os.makedirs(out_dir, exist_ok=True)
    rain_path = os.path.join(out_dir, "rain_loop.wav")
    thunder_path = os.path.join(out_dir, "thunder.wav")
    sr = 22050
    rng = random.Random(99)

    def write_wav(path, samples):
        with wave.open(path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sr)
            wf.writeframes(b"".join(
                struct.pack("<h", int(clamp(s, -1.0, 1.0) * 32000))
                for s in samples))

    if not os.path.exists(rain_path):
        # Rain: lowpassed white noise, gently amplitude-modulated.
        n = sr * 3
        samples = []
        lp = 0.0
        for i in range(n):
            lp += (rng.uniform(-1, 1) - lp) * 0.24
            mod = 0.8 + 0.2 * math.sin(2 * math.pi * i / sr * 0.7)
            samples.append(lp * 0.75 * mod)
        write_wav(rain_path, samples)

    if not os.path.exists(thunder_path):
        # Thunder: a deep rumble (heavily lowpassed noise) with a sharp
        # crack at the start and a long exponential decay.
        n = int(sr * 3.2)
        samples = []
        lp = lp2 = 0.0
        for i in range(n):
            t = i / sr
            lp += (rng.uniform(-1, 1) - lp) * 0.045
            lp2 += (lp - lp2) * 0.5
            env = math.exp(-t * 1.6) * (1.0 + 1.6 * math.exp(-t * 18.0))
            samples.append(lp2 * 5.0 * env)
        write_wav(thunder_path, samples)

    gun_path = os.path.join(out_dir, "gun.wav")
    if not os.path.exists(gun_path):
        n = int(sr * 0.08)
        samples = []
        for i in range(n):
            t = i / sr
            env = math.exp(-t * 58.0)
            samples.append(rng.uniform(-1, 1) * env)
        write_wav(gun_path, samples)
    return rain_path, thunder_path, gun_path


# ------------------------------------------------------------- car models
# Real 3D models: CC0 "Car Kit" by Kenney (kenney.nl), GLB format.
# Local car frame after import: origin on the ground under the center,
# +Y forward, Z up. Wheels are separate sub-nodes so they steer and spin.

def asset_path(rel):
    """Resolve an asset path from source, a PyInstaller exe, or a packed APK."""
    rel = rel.replace("\\", "/")
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, rel.replace("/", os.sep))
    here = os.path.dirname(os.path.abspath(__file__))
    candidate = os.path.join(here, rel.replace("/", os.sep))
    if os.path.isfile(candidate):
        return candidate
    return rel


def register_gltf_loader():
    """
    panda3d-gltf normally hooks .glb via setuptools entry points. Frozen
    PyInstaller builds do not expose those, so Panda's loader reports
    'Could not load model file(s)' even when the GLB is on disk.
    """
    from gltf._loader import GltfLoader
    registry = LoaderFileTypeRegistry.getGlobalPtr()
    if registry.getTypeFromExtension("glb") is None:
        registry.registerType(GltfLoader)


def load_glb(path):
    """Load a .glb with a native OS path so Python's open() can read it."""
    os_path = os.path.abspath(path)
    if not os.path.isfile(os_path):
        raise FileNotFoundError(f"car model missing: {os_path}")
    # Legacy (non-PBR) materials: the 1.10 shader generator cannot compile
    # metallic-roughness / M_selector stages and spam-renders errors.
    node = gltf.load_model(
        os_path, gltf_settings=gltf.GltfSettings(legacy_materials=True))
    if node is None:
        raise RuntimeError(f"failed to parse glTF: {os_path}")
    return node if isinstance(node, NodePath) else NodePath(node)


CAR_MODELS = [
    {
        "id": "corolla", "name": "COROLLA GT", "tag": "balanced sedan",
        "glb": "sedan.glb", "length": 4.5,
        "stats": {"max_speed": 115.0, "accel": 30.0, "brake": 50.0, "steer": 2.35},
    },
    {
        "id": "supra", "name": "SUPRA RZ", "tag": "rear-wing rocket",
        "glb": "sedan-sports.glb", "length": 4.6,
        "stats": {"max_speed": 139.0, "accel": 35.0, "brake": 52.0, "steer": 1.95},
    },
    {
        "id": "yaris", "name": "YARIS LE", "tag": "limited edition pocket rocket",
        "glb": "hatchback-sports.glb", "length": 3.9,
        "stats": {"max_speed": 105.0, "accel": 33.0, "brake": 48.0, "steer": 2.75},
    },
    {
        "id": "velocity", "name": "VELOCITY GT", "tag": "track-day missile",
        "glb": "race.glb", "length": 4.2,
        "stats": {"max_speed": 139.0, "accel": 38.0, "brake": 48.0, "steer": 1.85},
    },
    {
        "id": "cruiser", "name": "CRUISER XL", "tag": "heavy street SUV",
        "glb": "suv.glb", "length": 4.8,
        "stats": {"max_speed": 108.0, "accel": 26.0, "brake": 55.0, "steer": 2.15},
    },
    {
        "id": "cab", "name": "CITY CAB", "tag": "durable daily driver",
        "glb": "taxi.glb", "length": 4.4,
        "stats": {"max_speed": 112.0, "accel": 28.0, "brake": 50.0, "steer": 2.40},
    },
    {
        "id": "vanish", "name": "VANISH V6", "tag": "getaway van",
        "glb": "van.glb", "length": 5.2,
        "stats": {"max_speed": 98.0, "accel": 24.0, "brake": 52.0, "steer": 2.50},
    },
    {
        "id": "phantom", "name": "PHANTOM R", "tag": "future prototype",
        "glb": "race-future.glb", "length": 4.3,
        "stats": {"max_speed": 135.0, "accel": 36.0, "brake": 50.0, "steer": 1.90},
    },
    {
        "id": "luxe", "name": "LUXE SUV", "tag": "executive hauler",
        "glb": "suv-luxury.glb", "length": 5.0,
        "stats": {"max_speed": 118.0, "accel": 27.0, "brake": 54.0, "steer": 2.05},
    },
    {
        "id": "courier", "name": "COURIER", "tag": "express delivery",
        "glb": "delivery.glb", "length": 5.4,
        "stats": {"max_speed": 102.0, "accel": 25.0, "brake": 50.0, "steer": 2.20},
    },
    {
        "id": "interceptor", "name": "INTERCEPTOR", "tag": "stolen black-and-white",
        "glb": "police.glb", "length": 4.5,
        "stats": {"max_speed": 128.0, "accel": 34.0, "brake": 52.0, "steer": 2.25},
    },
]

# Police cruiser — spawned in free play on city maps, not selectable.
POLICE_MODEL = {
    "id": "police", "name": "PATROL", "tag": "law enforcement",
    "glb": "police.glb", "length": 4.5, "police": True,
    "stats": {"max_speed": 125.0, "accel": 32.0, "brake": 50.0, "steer": 2.30},
}

ALL_CAR_PROTOS = CAR_MODELS + [POLICE_MODEL]


def model_by_id(mid):
    for m in ALL_CAR_PROTOS:
        if m["id"] == mid:
            return m
    return CAR_MODELS[0]

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

CAR_MATERIAL = Material("car_paint")
CAR_MATERIAL.setAmbient((0.50, 0.50, 0.52, 1.0))
CAR_MATERIAL.setDiffuse((0.95, 0.95, 0.95, 1.0))
CAR_MATERIAL.setSpecular((0.35, 0.35, 0.35, 1.0))
CAR_MATERIAL.setShininess(40.0)
WORLD_MATERIAL = Material("world_matte")
WORLD_MATERIAL.setAmbient((0.55, 0.55, 0.55, 1.0))
WORLD_MATERIAL.setDiffuse((0.90, 0.90, 0.90, 1.0))
WORLD_MATERIAL.setSpecular((0.12, 0.12, 0.12, 1.0))
WORLD_MATERIAL.setShininess(10.0)
WET_MATERIAL = Material("wet_road")
WET_MATERIAL.setAmbient((0.40, 0.42, 0.48, 1.0))
WET_MATERIAL.setDiffuse((0.70, 0.72, 0.80, 1.0))
WET_MATERIAL.setSpecular((0.95, 0.97, 1.0, 1.0))
WET_MATERIAL.setShininess(110.0)


class CarAssets:
    """
    Loads the GLB car models and implements body-paint recoloring.

    All Kenney models share one 512x512 palette texture ("colormap").
    Each model's bodywork points at texels of one saturated hue, so to
    repaint a car we: (1) find the body hue by sampling the texture at
    the body mesh's UVs (area-weighted), (2) collect every palette pixel
    of that hue, and (3) for each requested paint color produce a texture
    variant with just those pixels re-hued, preserving shading.
    """

    def __init__(self, loader):
        self.loader = loader
        register_gltf_loader()
        self.palette = PNMImage()
        ok = self.palette.read(
            Filename.fromOsSpecific(asset_path("assets/cars/Textures/colormap.png")))
        if not ok:
            raise RuntimeError("colormap.png missing - run fetch_assets.py")
        self.pw, self.ph = self.palette.getXSize(), self.palette.getYSize()
        # One HSV pass over the palette, reused for every model.
        self.hsv_pixels = []
        for y in range(self.ph):
            for x in range(self.pw):
                c = self.palette.getXel(x, y)
                h, s, v = colorsys.rgb_to_hsv(c[0], c[1], c[2])
                if s > 0.30:
                    self.hsv_pixels.append((x, y, h, s, v))
        self.protos = {}       # model id -> (proto NodePath, scale)
        self.body_pixels = {}  # model id -> (pixel list, body value)
        self.tex_cache = {}    # (model id, paint idx) -> Texture
        for model in ALL_CAR_PROTOS:
            self._prepare(model)

    # ------------------------------------------------------------ loading
    def _prepare(self, model):
        path = asset_path(os.path.join("assets", "cars", model["glb"]))
        proto = load_glb(path)
        proto.setName(f"proto-{model['id']}")
        proto.setH(180)          # Kenney models face -Y; the game uses +Y

        # Re-hang each wheel on steer/spin pivots located at wheel center.
        wheels = proto.findAllMatches("**/wheel*")
        radius = 0.3
        for i, wheel in enumerate(wheels):
            lo, hi = wheel.getTightBounds(proto)
            center = (lo + hi) * 0.5
            radius = max(radius, (hi.z - lo.z) * 0.5)
            steered = "front" in wheel.getName()
            steer = proto.attachNewNode(
                f"pivot-steer-{i}" if steered else f"pivot-fixed-{i}")
            steer.setPos(center)
            spin = steer.attachNewNode(f"pivot-spin-{i}")
            wheel.wrtReparentTo(spin)

        lo, hi = proto.getTightBounds()
        scale = model["length"] / max(hi.y - lo.y, 0.01)
        self.protos[model["id"]] = (proto, scale)
        model["wheel_radius"] = radius * scale
        self._find_body_hue(model, proto)

    def _sample(self, u, v):
        """Sample the palette at a Panda-convention UV (v up)."""
        x = clamp(int(u % 1.0 * self.pw), 0, self.pw - 1)
        y = clamp(int((1.0 - v % 1.0) * self.ph), 0, self.ph - 1)
        c = self.palette.getXel(x, y)
        return (c[0], c[1], c[2])

    def _find_body_hue(self, model, proto):
        """Area-weighted UV sampling of the 'body' mesh -> dominant hue."""
        body = proto.find("**/body")
        if body.isEmpty():
            body = proto
        bins = {}
        for gnp in body.findAllMatches("**/+GeomNode"):
            gnode = gnp.node()
            for gi in range(gnode.getNumGeoms()):
                geom = gnode.getGeom(gi)
                vdata = geom.getVertexData()
                # glTF TEXCOORD_0 becomes "texcoord.0" in Panda3D.
                tc = InternalName.getTexcoordName("0")
                if not vdata.hasColumn(tc):
                    tc = InternalName.getTexcoord()
                if not vdata.hasColumn(tc):
                    continue
                vr = GeomVertexReader(vdata, "vertex")
                tr = GeomVertexReader(vdata, tc)
                verts, uvs = [], []
                while not vr.isAtEnd():
                    verts.append(vr.getData3())
                    uvs.append(tr.getData2())
                for pi in range(geom.getNumPrimitives()):
                    prim = geom.getPrimitive(pi).decompose()
                    for t in range(prim.getNumPrimitives()):
                        s = prim.getPrimitiveStart(t)
                        i0, i1, i2 = (prim.getVertex(s + k) for k in range(3))
                        area = ((verts[i1] - verts[i0]).cross(
                            verts[i2] - verts[i0])).length() * 0.5
                        u = (uvs[i0][0] + uvs[i1][0] + uvs[i2][0]) / 3.0
                        v = (uvs[i0][1] + uvs[i1][1] + uvs[i2][1]) / 3.0
                        r, g, b = self._sample(u, v)
                        h, s_, val = colorsys.rgb_to_hsv(r, g, b)
                        if s_ < 0.35:          # grey/black/glass: not paint
                            continue
                        key = round(h * 24) / 24.0
                        bins[key] = bins.get(key, 0.0) + area
        body_hue = max(bins, key=bins.get) if bins else 0.6

        # Collect all palette pixels belonging to that hue swatch.
        pixels = []
        vals = []
        for x, y, h, s, v in self.hsv_pixels:
            dh = min(abs(h - body_hue), 1.0 - abs(h - body_hue))
            if dh < 0.045:
                pixels.append((x, y, v, s))
                vals.append(v)
        body_v = sorted(vals)[len(vals) // 2] if vals else 0.7
        self.body_pixels[model["id"]] = (pixels, body_v)

    # ---------------------------------------------------------- recoloring
    def paint_texture(self, model, paint_idx):
        key = (model["id"], paint_idx)
        if key in self.tex_cache:
            return self.tex_cache[key]
        rgb = PAINT_COLORS[paint_idx][1]
        ph_, ps, pv = colorsys.rgb_to_hsv(*rgb)
        pixels, body_v = self.body_pixels[model["id"]]
        img = PNMImage(self.palette)
        for x, y, v, s in pixels:
            shade = clamp(v / body_v, 0.35, 1.45)   # keep baked shading
            r, g, b = colorsys.hsv_to_rgb(ph_, ps, clamp(pv * shade, 0.0, 1.0))
            img.setXel(x, y, r, g, b)
        tex = Texture(f"paint-{key}")
        tex.load(img)
        tex.setMinfilter(Texture.FT_linear_mipmap_linear)
        tex.setMagfilter(Texture.FT_linear)
        tex.setAnisotropicDegree(4)
        self.tex_cache[key] = tex
        return tex

    # ------------------------------------------------------------ building
    def build(self, model, paint_idx):
        """Instantiate a paintable car. Returns (root, steer, spin)."""
        proto, scale = self.protos[model["id"]]
        root = NodePath(f"car-{model['id']}")
        body = proto.copyTo(root)
        body.setScale(scale)
        steer = [np_ for np_ in body.findAllMatches("**/pivot-steer-*")]
        spin = [np_ for np_ in body.findAllMatches("**/pivot-spin-*")]
        if not model.get("police"):
            tex = self.paint_texture(model, paint_idx)
            stages = list(root.findAllTextureStages())
            if stages:
                for stage in stages:
                    root.setTexture(stage, tex, 1)
            else:
                root.setTexture(tex, 1)
        root.setMaterial(CAR_MATERIAL, 1)
        return root, steer, spin


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
            "fog": (220.0, 620.0),
            "ground": (0.29, 0.50, 0.23),
            "road": (0.55, 0.55, 0.58),
            "stripe_a": (0.85, 0.15, 0.15), "stripe_b": (0.92, 0.92, 0.92),
            "scenery": "pine",
            "sun": (0.95, 0.93, 0.88),
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
            "fog": (240.0, 680.0),
            "ground": (0.78, 0.68, 0.44),
            "road": (0.60, 0.56, 0.54),
            "stripe_a": (0.80, 0.25, 0.10), "stripe_b": (0.95, 0.90, 0.80),
            "scenery": "desert",
            "sun": (1.00, 0.82, 0.62),
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
            "fog": (170.0, 520.0),
            "ground": (0.86, 0.89, 0.93),
            "road": (0.42, 0.42, 0.48),
            "stripe_a": (0.20, 0.35, 0.70), "stripe_b": (0.92, 0.92, 0.95),
            "scenery": "snow_pine",
            "sun": (0.88, 0.90, 0.98),
        },
    },
    {
        "name": "ROCKPORT CITY", "tag": "urban  -  police chase free play",
        "width": 20.0, "samples": 12, "city": True,
        "points": [
            (0, -110), (55, -105), (105, -75), (115, -20), (105, 35),
            (70, 70), (25, 85), (-25, 85), (-70, 70), (-105, 35),
            (-115, -20), (-105, -75), (-55, -105),
        ],
        "theme": {
            "sky": (0.38, 0.40, 0.46), "sky_top": (0.14, 0.16, 0.22),
            "fog": (180.0, 480.0),
            "ground": (0.22, 0.23, 0.26),
            "road": (0.28, 0.28, 0.32),
            "stripe_a": (0.90, 0.90, 0.92), "stripe_b": (0.55, 0.55, 0.58),
            "scenery": "city",
            "sun": (0.72, 0.74, 0.80),
        },
    },
    {
        "name": "HARBOR DISTRICT", "tag": "coastal  -  long straights",
        "width": 17.0, "samples": 16,
        "points": [
            (0, -95), (70, -90), (120, -45), (115, 15), (80, 55),
            (30, 75), (-30, 70), (-80, 45), (-120, 0), (-115, -55),
            (-75, -90), (-20, -95),
        ],
        "theme": {
            "sky": (0.55, 0.68, 0.82), "sky_top": (0.22, 0.38, 0.62),
            "fog": (200.0, 560.0),
            "ground": (0.35, 0.42, 0.38),
            "road": (0.38, 0.38, 0.42),
            "stripe_a": (0.85, 0.75, 0.20), "stripe_b": (0.90, 0.90, 0.92),
            "scenery": "pine",
            "sun": (0.88, 0.86, 0.78),
        },
    },
    {
        "name": "CANYON PASS", "tag": "mountain  -  tight hairpins",
        "width": 15.0, "samples": 14,
        "points": [
            (0, -80), (35, -85), (75, -60), (90, -10), (75, 35),
            (40, 70), (0, 85), (-45, 75), (-80, 40), (-95, -5),
            (-80, -55), (-40, -78),
        ],
        "theme": {
            "sky": (0.62, 0.70, 0.82), "sky_top": (0.28, 0.36, 0.58),
            "fog": (160.0, 440.0),
            "ground": (0.48, 0.44, 0.36),
            "road": (0.40, 0.38, 0.36),
            "stripe_a": (0.78, 0.55, 0.18), "stripe_b": (0.88, 0.88, 0.90),
            "scenery": "desert",
            "sun": (0.95, 0.88, 0.72),
        },
    },
    {
        "name": "MIDNIGHT METRO", "tag": "night city  -  max bounty zone",
        "width": 19.0, "samples": 14, "city": True,
        "points": [
            (0, -100), (50, -95), (95, -60), (100, 0), (85, 55),
            (45, 90), (0, 100), (-45, 90), (-85, 55), (-100, 0),
            (-95, -60), (-50, -95),
        ],
        "theme": {
            "sky": (0.08, 0.09, 0.14), "sky_top": (0.04, 0.05, 0.10),
            "fog": (140.0, 400.0),
            "ground": (0.12, 0.13, 0.16),
            "road": (0.20, 0.20, 0.24),
            "stripe_a": (0.95, 0.85, 0.25), "stripe_b": (0.35, 0.35, 0.40),
            "scenery": "city",
            "sun": (0.45, 0.48, 0.65),
        },
    },
]


# ------------------------------------------------------------------- track
class Track:
    """
    Circuit data + procedural world geometry. Waypoints sampled from the
    map spline give a local frame (direction + left normal) per point,
    used for geometry, wall collision, AI targets and lap progress.
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
            x0, y0 = self.wps[i]
            x1, y1 = self.wps[(i + 1) % self.n]
            dx, dy = x1 - x0, y1 - y0
            d = math.hypot(dx, dy) or 1.0
            self.dirs.append((dx / d, dy / d))
            self.normals.append((-dy / d, dx / d))

        xs = [p[0] for p in self.wps]
        ys = [p[1] for p in self.wps]
        self.bounds = (min(xs), max(xs), min(ys), max(ys))
        self._plant_scenery()

    # ------------------------------------------------------------ queries
    def nearest_index(self, x, y, hint=None):
        if hint is None:
            candidates = range(self.n)
        else:
            candidates = [(hint + k) % self.n for k in range(-8, 24)]
        return min(candidates,
                   key=lambda i: (x - self.wps[i][0]) ** 2 + (y - self.wps[i][1]) ** 2)

    def heading_at(self, i):
        dx, dy = self.dirs[i]
        return math.atan2(-dx, dy)

    def clamp_to_walls(self, car):
        """Push the car back inside the barriers; costs speed on contact."""
        i = car.wp_idx
        wx, wy = self.wps[i]
        dx, dy = self.dirs[i]
        nx, ny = self.normals[i]
        rx, ry = car.x - wx, car.y - wy
        lat = rx * nx + ry * ny
        lon = rx * dx + ry * dy
        max_lat = self.half_width - 1.1
        if abs(lat) > max_lat:
            lat = max_lat if lat > 0 else -max_lat
            car.x = wx + dx * lon + nx * lat
            car.y = wy + dy * lon + ny * lat
            car.speed *= 0.94
            return True
        return False

    def _plant_scenery(self):
        rng = random.Random(7)
        x0, x1, y0, y1 = self.bounds
        plant_clear = (self.half_width + 10.0) ** 2
        build_clear = (self.half_width + 20.0) ** 2
        self.scenery = []
        while len(self.scenery) < self.scenery_count:
            x = rng.uniform(x0 - 110, x1 + 110)
            y = rng.uniform(y0 - 110, y1 + 110)
            d2 = min((x - wx) ** 2 + (y - wy) ** 2 for wx, wy in self.wps)
            if d2 <= plant_clear:
                continue
            r = rng.random()
            kind = "building" if (d2 > build_clear and r < 0.30) else "plant"
            self.scenery.append((x, y, rng.uniform(0.85, 1.40), r, kind))

    # ---------------------------------------------------------- geometry
    def build_world(self, parent):
        """Create the whole static world under `parent` and return it."""
        world = parent.attachNewNode("world")
        theme = self.theme

        # --- textured ground plane ---
        gmb = MeshBuilder("ground")
        x0, x1, y0, y1 = self.bounds
        gx0, gx1 = x0 - 260, x1 + 260
        gy0, gy1 = y0 - 260, y1 + 260
        uv_scale = 1.0 / 40.0          # texture tile = 40 world units
        gmb.quad((gx0, gy0, 0), (gx1, gy0, 0), (gx1, gy1, 0), (gx0, gy1, 0),
                 (1, 1, 1, 1),
                 uvs=((gx0 * uv_scale, gy0 * uv_scale), (gx1 * uv_scale, gy0 * uv_scale),
                      (gx1 * uv_scale, gy1 * uv_scale), (gx0 * uv_scale, gy1 * uv_scale)),
                 normal=(0, 0, 1))
        ground = gmb.build()
        ground.reparentTo(world)
        ground.setTexture(make_noise_texture("ground-" + theme["scenery"],
                                             theme["ground"], 0.07, 256, checker=0.06))
        ground.setMaterial(WORLD_MATERIAL, 1)

        # --- textured asphalt ribbon ---
        rmb = MeshBuilder("road")
        hw = self.half_width
        vdist = 0.0
        for i in range(self.n):
            j = (i + 1) % self.n
            (ax, ay), (anx, any_) = self.wps[i], self.normals[i]
            (bx, by), (bnx, bny) = self.wps[j], self.normals[j]
            seg = math.hypot(bx - ax, by - ay)
            v0, v1 = vdist / 7.0, (vdist + seg) / 7.0
            rmb.quad((ax + anx * hw, ay + any_ * hw, 0.02),
                     (ax - anx * hw, ay - any_ * hw, 0.02),
                     (bx - bnx * hw, by - bny * hw, 0.02),
                     (bx + bnx * hw, by + bny * hw, 0.02),
                     (*theme["road"], 1.0),
                     uvs=((0, v0), (1, v0), (1, v1), (0, v1)),
                     normal=(0, 0, 1))
            vdist += seg
        road = rmb.build()
        road.reparentTo(world)
        road.setTexture(make_noise_texture("asphalt", (0.32, 0.32, 0.34), 0.10,
                                           256, speckle=0.02,
                                           speckle_color=(0.55, 0.55, 0.58)))
        road.setMaterial(WORLD_MATERIAL, 1)
        self.road_np = road          # weather system swaps its material

        # --- untextured decoration mesh: curbs, markings, walls, stand ---
        dmb = MeshBuilder("deco")
        self._emit_curbs_markings(dmb)
        self._emit_walls(dmb)
        self._emit_gantry(dmb)
        self._emit_grandstand(dmb)
        self._emit_scenery(dmb)
        deco = dmb.build()
        deco.reparentTo(world)
        deco.setMaterial(WORLD_MATERIAL, 1)
        return world

    def _emit_curbs_markings(self, mb):
        hw = self.half_width
        sa = (*self.theme["stripe_a"], 1.0)
        sb = (*self.theme["stripe_b"], 1.0)
        up = (0, 0, 1)
        for side in (1.0, -1.0):
            for i in range(self.n):
                j = (i + 1) % self.n
                color = sa if (i // 3) % 2 == 0 else sb
                (ax, ay), (anx, any_) = self.wps[i], self.normals[i]
                (bx, by), (bnx, bny) = self.wps[j], self.normals[j]
                mb.quad((ax + anx * side * (hw - 1.3), ay + any_ * side * (hw - 1.3), 0.03),
                        (ax + anx * side * hw, ay + any_ * side * hw, 0.03),
                        (bx + bnx * side * hw, by + bny * side * hw, 0.03),
                        (bx + bnx * side * (hw - 1.3), by + bny * side * (hw - 1.3), 0.03),
                        color, normal=up)
        # Dashed center line.
        for i in range(0, self.n, 6):
            (wx, wy), (dx, dy), (nx, ny) = self.wps[i], self.dirs[i], self.normals[i]
            mb.quad((wx - nx * 0.18, wy - ny * 0.18, 0.04),
                    (wx + nx * 0.18, wy + ny * 0.18, 0.04),
                    (wx + nx * 0.18 + dx * 2.2, wy + ny * 0.18 + dy * 2.2, 0.04),
                    (wx - nx * 0.18 + dx * 2.2, wy - ny * 0.18 + dy * 2.2, 0.04),
                    (0.92, 0.92, 0.92, 1.0), normal=up)
        # Checkered start line.
        (wx, wy), (dx, dy), (nx, ny) = self.wps[0], self.dirs[0], self.normals[0]
        cols = 8
        cw = (self.half_width - 1.3) * 2 / cols
        for row in range(2):
            for col in range(cols):
                c = 0.95 if (row + col) % 2 == 0 else 0.05
                l0 = -(self.half_width - 1.3) + col * cw
                f0 = row * 1.1
                pts = []
                for sx, sy in ((l0, f0), (l0 + cw, f0), (l0 + cw, f0 + 1.1), (l0, f0 + 1.1)):
                    pts.append((wx + nx * sx + dx * sy, wy + ny * sx + dy * sy, 0.05))
                mb.quad(*pts, (c, c, c, 1.0), normal=up)

    def _emit_walls(self, mb):
        hw, h = self.half_width, 1.1
        inner, outer = hw + 0.9, hw + 1.7
        sa = (*self.theme["stripe_a"], 1.0)
        sb = (*self.theme["stripe_b"], 1.0)
        for side in (1.0, -1.0):
            for i in range(self.n):
                j = (i + 1) % self.n
                color = sa if (i // 4) % 2 == 0 else sb
                (ax, ay), (anx, any_) = self.wps[i], self.normals[i]
                (bx, by), (bnx, bny) = self.wps[j], self.normals[j]
                a_in = (ax + anx * side * inner, ay + any_ * side * inner)
                b_in = (bx + bnx * side * inner, by + bny * side * inner)
                a_out = (ax + anx * side * outer, ay + any_ * side * outer)
                b_out = (bx + bnx * side * outer, by + bny * side * outer)
                n_in = (-side * anx, -side * any_, 0)
                mb.quad((a_in[0], a_in[1], 0), (b_in[0], b_in[1], 0),
                        (b_in[0], b_in[1], h), (a_in[0], a_in[1], h),
                        color, normal=n_in)
                mb.quad((a_out[0], a_out[1], 0), (a_out[0], a_out[1], h),
                        (b_out[0], b_out[1], h), (b_out[0], b_out[1], 0),
                        color, normal=(side * anx, side * any_, 0))
                mb.quad((a_in[0], a_in[1], h), (b_in[0], b_in[1], h),
                        (b_out[0], b_out[1], h), (a_out[0], a_out[1], h),
                        color, normal=(0, 0, 1))

    def _local_frame_emit(self, mb, wp_index, emit):
        """Run `emit(to_world)` with a local frame at a waypoint: local
        +Y = track direction, +X = left normal."""
        (wx, wy) = self.wps[wp_index]
        (dx, dy) = self.dirs[wp_index]
        (nx, ny) = self.normals[wp_index]

        def to_world(lx, ly, lz):
            return (wx + nx * lx + dx * ly, wy + ny * lx + dy * ly, lz)

        emit(to_world)

    def _emit_gantry(self, mb):
        span = self.half_width + 2.2
        beam = (*self.theme["stripe_a"], 1.0)

        def emit(tw):
            for sx in (-span, span):
                self._emit_box_frame(mb, tw, sx, 0.0, 3.1, 0.45, 0.45, 6.2, (0.25, 0.25, 0.28, 1))
            self._emit_box_frame(mb, tw, 0.0, 0.0, 6.55, span * 2 + 0.45, 0.75, 0.75, beam)

        self._local_frame_emit(mb, 0, emit)

    def _emit_grandstand(self, mb):
        off = self.half_width + 6.0
        seat_colors = [(0.75, 0.15, 0.15, 1), (0.15, 0.35, 0.75, 1),
                       (0.85, 0.70, 0.15, 1), (0.20, 0.55, 0.25, 1),
                       (0.60, 0.60, 0.65, 1)]

        def emit(tw):
            self._emit_box_frame(mb, tw, off + 2.9, 0.0, 0.35, 6.6, 26.0, 0.7, (0.35, 0.35, 0.38, 1))
            for i, color in enumerate(seat_colors):
                self._emit_box_frame(mb, tw, off + 0.9 + i * 1.05, 0.0,
                                     0.78 + i * 0.52, 1.05, 26.0, 0.55, color)
            self._emit_box_frame(mb, tw, off + 6.1, 0.0, 2.3, 0.4, 26.0, 4.6, (0.30, 0.30, 0.33, 1))
            for sy in (-12.5, 12.5):
                for sx in (off + 0.7, off + 5.7):
                    self._emit_box_frame(mb, tw, sx, sy, 2.4, 0.30, 0.30, 4.8, (0.22, 0.22, 0.25, 1))
            self._emit_box_frame(mb, tw, off + 3.2, 0.0, 4.85, 7.2, 27.0, 0.28,
                                 (*self.theme["stripe_a"], 1))

        self._local_frame_emit(mb, 0, emit)

    @staticmethod
    def _emit_box_frame(mb, tw, cx, cy, cz, w, l, h, color):
        """Axis-aligned box in a local frame, transformed by tw()."""
        x0, x1 = cx - w / 2, cx + w / 2
        y0, y1 = cy - l / 2, cy + l / 2
        z0, z1 = cz - h / 2, cz + h / 2
        a, b = tw(x0, y0, z0), tw(x1, y0, z0)
        c, d = tw(x1, y1, z0), tw(x0, y1, z0)
        e, f = tw(x0, y0, z1), tw(x1, y0, z1)
        g, h_ = tw(x1, y1, z1), tw(x0, y1, z1)
        mb.quad(e, f, g, h_, color)
        mb.quad(a, d, c, b, color)
        mb.quad(a, b, f, e, color)
        mb.quad(c, d, h_, g, color)
        mb.quad(d, a, e, h_, color)
        mb.quad(b, c, g, f, color)

    def _emit_scenery(self, mb):
        kind = self.theme["scenery"]
        for x, y, s, r, sort in self.scenery:
            def tw(lx, ly, lz, _x=x, _y=y, _s=s, _r=r * 360.0, _b=(sort == "building")):
                if _b:  # buildings get a random rotation for variety
                    a = math.radians(_r)
                    lx, ly = lx * math.cos(a) - ly * math.sin(a), lx * math.sin(a) + ly * math.cos(a)
                return (_x + lx * _s, _y + ly * _s, lz * _s)

            if sort == "building":
                self._emit_building(mb, tw, kind, r)
            elif kind == "pine":
                self._emit_pine(mb, tw, (0.10, 0.38, 0.12, 1), (0.12, 0.44, 0.14, 1),
                                (0.15, 0.50, 0.17, 1))
            elif kind == "snow_pine":
                self._emit_pine(mb, tw, (0.22, 0.38, 0.30, 1), (0.45, 0.58, 0.52, 1),
                                (0.85, 0.90, 0.92, 1))
            elif r < 0.6:      # desert cactus
                self._emit_box_frame(mb, tw, 0.0, 0.0, 1.3, 0.55, 0.55, 2.6, (0.22, 0.52, 0.24, 1))
                self._emit_box_frame(mb, tw, -0.62, 0.0, 1.75, 0.34, 0.34, 0.95, (0.24, 0.55, 0.26, 1))
                self._emit_box_frame(mb, tw, 0.62, 0.0, 1.45, 0.34, 0.34, 0.95, (0.24, 0.55, 0.26, 1))
            else:              # desert rock
                self._emit_box_frame(mb, tw, 0.0, 0.0, 0.5, 2.2, 1.7, 1.0, (0.55, 0.52, 0.48, 1))
                self._emit_box_frame(mb, tw, 0.4, 0.2, 1.1, 1.1, 0.9, 0.6, (0.60, 0.57, 0.53, 1))

    def _emit_pine(self, mb, tw, c1, c2, c3):
        self._emit_box_frame(mb, tw, 0, 0, 1.1, 0.6, 0.6, 2.2, (0.42, 0.28, 0.14, 1))
        self._emit_box_frame(mb, tw, 0, 0, 2.6, 3.2, 3.2, 1.6, c1)
        self._emit_box_frame(mb, tw, 0, 0, 3.8, 2.4, 2.4, 1.4, c2)
        self._emit_box_frame(mb, tw, 0, 0, 4.9, 1.4, 1.4, 1.2, c3)

    def _emit_building(self, mb, tw, theme_kind, r):
        if theme_kind == "pine":
            walls = [(0.86, 0.80, 0.68, 1), (0.80, 0.72, 0.60, 1),
                     (0.74, 0.78, 0.82, 1)][int(r * 3) % 3]
            self._emit_box_frame(mb, tw, 0, 0, 1.4, 5.6, 4.6, 2.8, walls)
            self._emit_roof(mb, tw, 3.1, 2.6, 2.8, 4.7, (0.58, 0.30, 0.20, 1))
            self._emit_box_frame(mb, tw, 0, -2.35, 0.95, 0.95, 0.12, 1.9, (0.35, 0.24, 0.15, 1))
            for sx in (-1.7, 1.7):
                self._emit_box_frame(mb, tw, sx, -2.35, 1.8, 0.95, 0.12, 0.85, GLASS)
        elif theme_kind == "desert":
            self._emit_box_frame(mb, tw, 0, 0, 1.5, 5.1, 4.1, 3.0, (0.83, 0.70, 0.52, 1))
            self._emit_box_frame(mb, tw, 0.2, 0.2, 3.7, 2.7, 2.3, 1.4, (0.80, 0.66, 0.48, 1))
            self._emit_box_frame(mb, tw, 0, -2.12, 1.0, 0.95, 0.12, 2.0, (0.30, 0.22, 0.15, 1))
            for sx in (-1.5, 1.5):
                self._emit_box_frame(mb, tw, sx, -2.12, 2.1, 0.75, 0.12, 0.75, (0.12, 0.10, 0.08, 1))
        elif theme_kind == "city":
            h = 5.5 + (r % 1.0) * 14.0
            w = 5.0 + (int(r * 10) % 3) * 1.2
            walls = [(0.42, 0.44, 0.50, 1), (0.48, 0.46, 0.44, 1),
                     (0.36, 0.38, 0.42, 1)][int(r * 3) % 3]
            self._emit_box_frame(mb, tw, 0, 0, h / 2, w, w * 0.85, h, walls)
            rows = max(1, int(h / 2.2))
            for row in range(rows):
                for col in range(2):
                    z = 1.4 + row * 2.2
                    sx = -w * 0.22 + col * w * 0.44
                    lit = ((0.95, 0.88, 0.55, 1) if (row + col + int(r * 5)) % 3
                           else GLASS)
                    self._emit_box_frame(mb, tw, sx, -w * 0.38, z, 0.9, 0.08, 0.85, lit)
            self._emit_box_frame(mb, tw, 0, w * 0.48, 0.35, w * 0.7, 0.12, 0.7,
                                 (0.25, 0.25, 0.28, 1))
        else:
            self._emit_box_frame(mb, tw, 0, 0, 1.5, 5.4, 4.6, 3.0, (0.45, 0.32, 0.20, 1))
            self._emit_roof(mb, tw, 3.2, 2.7, 3.0, 5.6, (0.92, 0.94, 0.97, 1))
            self._emit_box_frame(mb, tw, 0, -2.35, 1.0, 1.0, 0.12, 2.0, (0.30, 0.20, 0.12, 1))
            for sx in (-1.7, 1.7):
                # Warm glowing windows against the snow.
                self._emit_box_frame(mb, tw, sx, -2.35, 1.9, 0.9, 0.12, 0.85, (0.95, 0.82, 0.45, 1))

    @staticmethod
    def _emit_roof(mb, tw, half_w, half_l, z0, z1, color):
        """Gabled roof: walls loft up to a ridge line along Y."""
        a, b = tw(-half_w, -half_l, z0), tw(half_w, -half_l, z0)
        c, d = tw(half_w, half_l, z0), tw(-half_w, half_l, z0)
        e, f = tw(0, -half_l, z1), tw(0, half_l, z1)
        mb.quad(a, b, e, e, color)         # front gable (triangle)
        mb.quad(c, d, f, f, color)         # rear gable
        mb.quad(b, c, f, e, color)         # right slope
        mb.quad(d, a, e, f, color)         # left slope


# --------------------------------------------------------------------- car
class Car:
    """Arcade vehicle physics; performance stats come from the car model."""

    REVERSE_ACCEL = 14.0
    MAX_REVERSE_SPEED = -18.0
    ROLL_DECAY = 0.22
    DRAG = 0.006

    def __init__(self, display_name, model, color):
        self.display_name = display_name
        self.model = model
        self.color = color
        stats = model["stats"]
        self.max_speed = stats["max_speed"]
        self.accel = stats["accel"]
        self.brake = stats["brake"]
        self.steer_rate = stats["steer"]

        self.x = self.y = 0.0
        self.heading = 0.0            # radians, 0 = facing +Y
        self.speed = 0.0
        self.grip = 1.0               # weather traction factor
        self.wp_idx = 0
        self.lap = 0
        self.race_pos = 1
        self.visual_steer = 0.0
        self.wheel_roll = 0.0         # radians

        self.node = None              # NodePath, attached by the game
        self.steer_pivots = []
        self.spin_pivots = []
        self.is_police = False
        self.checkpoint = 0           # next checkpoint index (0..CHECKPOINT_COUNT-1)
        self.checkpoints_hit = 0      # hits this lap
        self.hp = HP_MAX
        self.kills = 0
        self.wreck_t = 0.0
        self.fire_cd = 0.0
        self.hit_flash = 0.0
        self.killed_by = ""
        self.gun_node = None

    def place(self, x, y, heading, wp_idx):
        self.x, self.y, self.heading = x, y, heading
        self.speed = 0.0
        self.wp_idx = wp_idx
        self.lap = 0
        self.checkpoint = 0
        self.checkpoints_hit = 0

    def respawn_at(self, x, y, heading, wp_idx):
        self.x, self.y, self.heading = x, y, heading
        self.speed = 0.0
        self.wp_idx = wp_idx
        self.hp = HP_MAX
        self.wreck_t = 0.0
        self.hit_flash = 0.0
        self.killed_by = ""
        if self.node:
            self.node.clearColorScale()

    def update(self, dt, throttle, steer):
        if self.wreck_t > 0.0:
            throttle *= 0.12
            steer *= 0.35
        if self.fire_cd > 0.0:
            self.fire_cd = max(0.0, self.fire_cd - dt)
        if self.hit_flash > 0.0:
            self.hit_flash = max(0.0, self.hit_flash - dt)
        if throttle > 0.0:
            self.speed += self.accel * self.grip * throttle * dt
        elif throttle < 0.0:
            if self.speed > 0.5:
                self.speed += self.brake * self.grip * throttle * dt
            else:
                self.speed += self.REVERSE_ACCEL * throttle * dt

        self.speed *= math.exp(-self.ROLL_DECAY * dt)
        self.speed -= self.DRAG * self.speed * abs(self.speed) * dt
        if abs(self.speed) < 0.02 and throttle == 0.0:
            self.speed = 0.0
        self.speed = clamp(self.speed, self.MAX_REVERSE_SPEED, self.max_speed)

        if steer != 0.0 and abs(self.speed) > 0.1:
            ratio = min(abs(self.speed) / self.max_speed, 1.0)
            effect = math.sin(min(ratio * 2.0, 1.0) * math.pi / 2.0)
            effect *= (1.0 - 0.35 * ratio)
            direction = 1.0 if self.speed >= 0.0 else -1.0
            self.heading += (steer * self.steer_rate * self.grip
                             * effect * direction * dt)
        self.visual_steer = lerp(self.visual_steer, steer, min(1.0, dt * 10.0))
        self.wheel_roll += self.speed * dt / self.model["wheel_radius"]

        # heading 0 faces +Y; forward = (-sin h, cos h).
        self.x += -math.sin(self.heading) * self.speed * dt
        self.y += math.cos(self.heading) * self.speed * dt

    def sync_node(self):
        """Push physics state into the scene graph."""
        self.node.setPos(self.x, self.y, 0.0)
        self.node.setH(math.degrees(self.heading))
        for p in self.steer_pivots:
            p.setH(self.visual_steer * 22.0)
        deg = math.degrees(self.wheel_roll)
        for p in self.spin_pivots:
            p.setP(-deg)
        if self.hit_flash > 0.0 and self.node:
            k = 0.45 + 0.55 * (self.hit_flash / 0.25)
            self.node.setColorScale(1.0, k, k, 1.0)
        elif self.wreck_t > 0.0 and self.node:
            self.node.setColorScale(0.28, 0.28, 0.32, 1.0)
        elif self.node:
            self.node.clearColorScale()


def attach_car_gun(car):
    """Roof cannon used in gun mode."""
    if car.gun_node or not car.node:
        return
    mb = MeshBuilder("car-gun")
    mb.box(0.0, 0.15, 1.28, 0.42, 0.42, 0.22, (0.16, 0.16, 0.18, 1))
    mb.box(0.0, 0.55, 1.34, 0.16, 0.85, 0.16, (0.10, 0.10, 0.12, 1))
    node = mb.build()
    node.reparentTo(car.node)
    car.gun_node = node


class Bullet:
    """Forward-fired tracer. Owner is a Car."""

    def __init__(self, parent, owner, shot_id, heading=None, x=None, y=None):
        self.owner = owner
        self.shot_id = shot_id
        self.heading = owner.heading if heading is None else heading
        fx, fy = -math.sin(self.heading), math.cos(self.heading)
        self.x = owner.x + fx * 3.2 if x is None else x
        self.y = owner.y + fy * 3.2 if y is None else y
        self.life = BULLET_LIFE
        mb = MeshBuilder("bullet")
        mb.box(0, 0, 0, 0.16, 0.90, 0.16, (1.0, 0.82, 0.20, 1))
        self.node = mb.build()
        self.node.reparentTo(parent)
        self.node.setLightOff(1)
        self.node.setColorScale(1.4, 1.2, 0.6, 1)
        self._pose()

    def _pose(self):
        self.node.setPos(self.x, self.y, 0.95)
        self.node.setH(math.degrees(self.heading))

    def update(self, dt):
        fx, fy = -math.sin(self.heading), math.cos(self.heading)
        self.x += fx * BULLET_SPEED * dt
        self.y += fy * BULLET_SPEED * dt
        self.life -= dt
        self._pose()
        return self.life > 0.0

    def destroy(self):
        if self.node:
            self.node.removeNode()
            self.node = None


class HumanController:
    def __init__(self, game, up, down, left, right, use_touch=False, fire=None):
        self.game = game
        self.up, self.down, self.left, self.right = up, down, left, right
        self.use_touch = use_touch
        self.fire = fire or ("control", "lcontrol")

    def control(self, car, track):
        if getattr(self.game, "chat_open", False):
            return 0.0, 0.0
        keys = self.game.keys
        throttle = 0.0
        if any(keys.get(k) for k in self.up):
            throttle = 1.0
        elif any(keys.get(k) for k in self.down):
            throttle = -1.0
        steer = 0.0
        if any(keys.get(k) for k in self.left):
            steer += 1.0
        if any(keys.get(k) for k in self.right):
            steer -= 1.0
        if self.use_touch:
            tt = self.game.touch_throttle
            ts = self.game.touch_steer
            if abs(tt) > 0.08:
                throttle = 1.0 if tt > 0 else -1.0
            if abs(ts) > 0.08:
                steer = ts
        return throttle, steer

    def wants_fire(self, car, game):
        if getattr(game, "chat_open", False) or car.wreck_t > 0.0:
            return False
        if any(self.game.keys.get(k) for k in self.fire):
            return True
        if self.use_touch and getattr(game, "touch_fire", False):
            return True
        if (not getattr(game, "touch_enabled", False)
                and self.use_touch and getattr(game, "_mouse_fire", False)):
            return True
        return False


class RemoteController:
    """Applies interpolated poses from Firebase instead of local physics."""

    def __init__(self, uid):
        self.uid = uid
        self.name = "RACER"
        self.model_id = CAR_MODELS[0]["id"]
        self.color = 0
        self.tx = self.ty = self.th = self.tspeed = 0.0
        self.tsteer = 0.0
        self.last_ts = 0.0
        self.hp = HP_MAX
        self.kills = 0
        self.killer = ""

    def apply(self, snap):
        if not isinstance(snap, dict):
            return
        self.name = str(snap.get("name") or self.name)
        self.model_id = str(snap.get("model") or self.model_id)
        try:
            self.color = int(snap.get("color") or 0) % len(PAINT_COLORS)
        except (TypeError, ValueError):
            self.color = 0
        try:
            ts = float(snap.get("ts") or 0.0)
        except (TypeError, ValueError):
            ts = 0.0
        stale = ts and self.last_ts and ts + 0.0001 < self.last_ts
        if not stale:
            self.tx = float(snap.get("x") or 0.0)
            self.ty = float(snap.get("y") or 0.0)
            self.th = float(snap.get("h") or 0.0)
            self.tspeed = float(snap.get("s") or 0.0)
            self.tsteer = float(snap.get("steer") or 0.0)
            self.last_ts = ts
        try:
            self.hp = float(snap.get("hp") if snap.get("hp") is not None else HP_MAX)
        except (TypeError, ValueError):
            self.hp = HP_MAX
        try:
            self.kills = int(snap.get("kills") or 0)
        except (TypeError, ValueError):
            self.kills = 0
        self.killer = str(snap.get("killer") or "")

    def control(self, car, track):
        return 0.0, 0.0

    def wants_fire(self, car, game):
        return False

    def blend(self, car, dt):
        age = 0.0
        if self.last_ts > 1.0e9:
            age = clamp(time.time() - self.last_ts, 0.0, 0.12)
        fx, fy = -math.sin(self.th), math.cos(self.th)
        px = self.tx + fx * self.tspeed * age
        py = self.ty + fy * self.tspeed * age
        dx, dy = px - car.x, py - car.y
        if dx * dx + dy * dy > 100.0:
            car.x, car.y, car.heading = px, py, self.th
        else:
            t = min(1.0, dt * 28.0)
            car.x += dx * t
            car.y += dy * t
            car.heading += wrap_angle(self.th - car.heading) * t
        car.speed = self.tspeed
        car.visual_steer = lerp(car.visual_steer, self.tsteer, min(1.0, dt * 18.0))
        car.wheel_roll += car.speed * dt / max(car.model.get("wheel_radius", 0.3), 0.05)
        car.display_name = self.name
        car.hp = self.hp
        car.kills = self.kills
        if self.hp <= 0 and car.wreck_t <= 0:
            car.wreck_t = 0.4


class AIController:
    """Chases a speed-scaled lookahead waypoint; brakes for curvature."""

    def __init__(self, skill):
        self.skill = skill

    def control(self, car, track):
        look = 4 + int(abs(car.speed) * 0.35)
        tx, ty = track.wps[(car.wp_idx + look) % track.n]
        target_h = math.atan2(-(tx - car.x), ty - car.y)
        err = wrap_angle(target_h - car.heading)
        steer = clamp(err * 2.4, -1.0, 1.0)

        far = 10 + int(abs(car.speed) * 0.6)
        curve = abs(wrap_angle(track.heading_at((car.wp_idx + far) % track.n)
                               - track.heading_at(car.wp_idx)))
        desired = (car.max_speed * self.skill * car.grip
                   * clamp(1.35 - curve * 0.85, 0.45, 1.0))
        if car.speed < desired - 1.0:
            return 1.0, steer
        if car.speed > desired + 2.0:
            return -1.0, steer
        return 0.0, steer

    def wants_fire(self, car, game):
        if not getattr(game, "gun_enabled", False) or car.wreck_t > 0 or car.fire_cd > 0:
            return False
        best_d = 40.0
        best = None
        for other in game.cars:
            if other is car or other.wreck_t > 0:
                continue
            d = math.hypot(other.x - car.x, other.y - car.y)
            if d < best_d:
                best, best_d = other, d
        if best is None:
            return False
        aim = math.atan2(-(best.x - car.x), best.y - car.y)
        if abs(wrap_angle(aim - car.heading)) > 0.32:
            return False
        return random.random() < (0.10 + 0.18 * self.skill)


class PoliceController:
    """Pursues a target car — used for city free-play police chases."""

    def __init__(self, target):
        self.target = target

    def control(self, car, track):
        tx, ty = self.target.x, self.target.y
        target_h = math.atan2(-(tx - car.x), ty - car.y)
        err = wrap_angle(target_h - car.heading)
        steer = clamp(err * 3.0, -1.0, 1.0)

        dist = math.hypot(tx - car.x, ty - car.y)
        desired = car.max_speed * clamp(0.88 + dist * 0.004, 0.75, 1.0)
        if car.speed < desired - 1.5:
            return 1.0, steer
        if car.speed > desired + 4.0:
            return -0.4, steer
        return 0.3, steer

    def wants_fire(self, car, game):
        if not getattr(game, "gun_enabled", False) or car.wreck_t > 0 or car.fire_cd > 0:
            return False
        tgt = self.target
        if tgt is None or tgt.wreck_t > 0:
            return False
        d = math.hypot(tgt.x - car.x, tgt.y - car.y)
        if d > 36.0:
            return False
        aim = math.atan2(-(tgt.x - car.x), tgt.y - car.y)
        return abs(wrap_angle(aim - car.heading)) < 0.28


class ChaseCamera:
    """
    Multi-mode camera driving a Panda3D camera node.
    Modes (cycled with C): CHASE third-person, HOOD driver POV,
    TOP overhead.
    """

    BASE_DIST = 11.0
    BASE_HEIGHT = 4.6
    STIFFNESS = 5.0

    def __init__(self, car, cam_np, mode="CHASE"):
        self.car = car
        self.cam = cam_np
        self.mode = mode
        self.snap()

    def set_mode(self, mode):
        self.mode = mode
        self.snap()

    def _target(self):
        c = self.car
        if self.mode == "HOOD":
            # Driver eye: slightly left of center, above hood, looking forward.
            fx, fy = -math.sin(c.heading), math.cos(c.heading)
            return (c.x + fx * 0.45, c.y + fy * 0.45, 1.25)
        if self.mode == "TOP":
            return (c.x, c.y, 38.0 + abs(c.speed) * 0.04)
        d = self.BASE_DIST + abs(c.speed) * 0.035
        return (c.x + math.sin(c.heading) * d,
                c.y - math.cos(c.heading) * d,
                self.BASE_HEIGHT + abs(c.speed) * 0.012)

    def snap(self):
        self.x, self.y, self.z = self._target()
        self.apply()

    def update(self, dt):
        tx, ty, tz = self._target()
        stiff = 12.0 if self.mode == "HOOD" else (8.0 if self.mode == "TOP" else self.STIFFNESS)
        t = 1.0 - math.exp(-stiff * dt)
        self.x = lerp(self.x, tx, t)
        self.y = lerp(self.y, ty, t)
        self.z = lerp(self.z, tz, t)
        self.apply()

    def apply(self):
        c = self.car
        self.cam.setPos(self.x, self.y, self.z)
        if self.mode == "HOOD":
            fx, fy = -math.sin(c.heading), math.cos(c.heading)
            self.cam.lookAt(c.x + fx * 18.0, c.y + fy * 18.0, 1.0)
        elif self.mode == "TOP":
            self.cam.lookAt(c.x, c.y, 0.0)
            # Keep north-up so the map orientation stays readable.
            self.cam.setH(0)
            self.cam.setP(-90)
            self.cam.setR(0)
        else:
            self.cam.lookAt(c.x, c.y, 1.2)


class WindshieldRain:
    """
    Screen-space rain droplets for hood/first-person view.
    Droplets spawn, smear downward a little, then fade.
    """

    MAX_DROPS = 48

    def __init__(self, parent):
        self.root = parent.attachNewNode("windshield")
        self.drops = []   # dicts: node, life, max_life, vy
        self.active = False
        self._tex = self._make_drop_tex()

    def _make_drop_tex(self):
        size = 32
        img = PNMImage(size, size, 4)
        img.fill(0.85, 0.90, 1.0)
        img.alphaFill(0.0)
        cx = cy = size / 2.0
        for y in range(size):
            for x in range(size):
                d = math.hypot(x - cx, y - cy) / (size * 0.42)
                if d < 1.0:
                    a = (1.0 - d) ** 1.6 * 0.75
                    img.setAlpha(x, y, a)
                    if d < 0.35:
                        img.setXel(x, y, 0.95, 0.97, 1.0)
        tex = Texture("raindrop")
        tex.load(img)
        tex.setMinfilter(Texture.FT_linear)
        tex.setMagfilter(Texture.FT_linear)
        return tex

    def set_active(self, on):
        self.active = on
        if not on:
            self.clear()
            self.root.hide()
        else:
            self.root.show()

    def clear(self):
        for d in self.drops:
            d["node"].removeNode()
        self.drops = []

    def update(self, dt, raining):
        if not self.active or not raining:
            self.clear()
            return
        # Spawn new droplets.
        spawn = int(18 * dt) + (1 if random.random() < 0.35 else 0)
        for _ in range(spawn):
            if len(self.drops) >= self.MAX_DROPS:
                break
            size = random.uniform(0.018, 0.055)
            x = random.uniform(-ASPECT + 0.05, ASPECT - 0.05)
            y = random.uniform(-0.85, 0.85)
            cm = CardMaker("drop")
            cm.setFrame(-size, size, -size * 1.4, size * 1.4)
            node = self.root.attachNewNode(cm.generate())
            node.setTexture(self._tex)
            node.setTransparency(TransparencyAttrib.MAlpha)
            node.setLightOff(1)
            node.setBin("fixed", 60)
            node.setDepthTest(False)
            node.setDepthWrite(False)
            node.setPos(x, 0, y)
            life = random.uniform(0.8, 2.4)
            self.drops.append({
                "node": node, "life": life, "max": life,
                "vy": -random.uniform(0.04, 0.18),
                "vx": random.uniform(-0.02, 0.02),
            })
        # Age / move / fade.
        alive = []
        for d in self.drops:
            d["life"] -= dt
            if d["life"] <= 0:
                d["node"].removeNode()
                continue
            pos = d["node"].getPos()
            d["node"].setPos(pos.x + d["vx"] * dt, 0, pos.z + d["vy"] * dt)
            a = clamp(d["life"] / d["max"], 0.0, 1.0)
            d["node"].setColorScale(1, 1, 1, a)
            alive.append(d)
        self.drops = alive

    def destroy(self):
        self.clear()
        self.root.removeNode()


class TouchControls:
    """
    On-screen buttons + a virtual joystick for phones/tablets.
    Panda3D maps the first finger to mouse1, so the joystick is a full
    one-thumb drive (X = steer, Y = throttle) and GAS/BRAKE are extras
    when a second pointer exists (desktop mouse / future multi-touch).
    """

    def __init__(self, game):
        self.game = game
        self.root = game.aspect2d.attachNewNode("touch")
        self.root.setBin("fixed", 70)
        self.root.setDepthTest(False)
        self.root.setDepthWrite(False)
        self.buttons = []
        self.joy = None
        self.joy_knob = None
        self._joy_grabbed = False
        self._prev_down = False
        self.enabled = bool(TOUCH_DEFAULT)

    def aspect(self):
        try:
            return self.game.getAspectRatio()
        except Exception:
            return ASPECT

    def _clear(self):
        for child in self.root.getChildren():
            child.removeNode()
        self.buttons = []
        self.joy = None
        self.joy_knob = None
        self._joy_grabbed = False

    def _rect(self, x, y, w, h, color, alpha):
        cm = CardMaker("tbtn")
        cm.setFrame(x, x + w, y, y + h)
        np_ = self.root.attachNewNode(cm.generate())
        np_.setColor(*color, alpha)
        np_.setTransparency(TransparencyAttrib.MAlpha)
        np_.setLightOff(1)
        return np_

    def _label(self, x, y, text, scale=0.045):
        return OnscreenText(text=text, pos=(x, y), scale=scale,
                            fg=(1, 1, 1, 1), align=TextNode.ACenter,
                            shadow=(0, 0, 0, 0.8), parent=self.root)

    def _add_btn(self, x, y, w, h, label, action, hold=False,
                 color=(0.12, 0.16, 0.22)):
        node = self._rect(x, y, w, h, color, 0.62)
        self._label(x + w * 0.5, y + h * 0.38, label,
                    0.042 if len(label) < 10 else 0.034)
        self.buttons.append({
            "frame": (x, x + w, y, y + h),
            "action": action,
            "hold": hold,
            "node": node,
            "color": color,
            "inside": False,
        })

    def _add_joy(self, cx, cy, r):
        base = self._rect(cx - r, cy - r, r * 2, r * 2,
                          (0.10, 0.12, 0.16), 0.45)
        knob = self._rect(cx - r * 0.32, cy - r * 0.32, r * 0.64, r * 0.64,
                          (0.85, 0.85, 0.9), 0.8)
        self._label(cx, cy + r + 0.04, "STEER / GAS", 0.032)
        self.joy = {"cx": cx, "cy": cy, "r": r, "base": base}
        self.joy_knob = knob

    def _add_chat_keyboard(self):
        """Full QWERTY so phones can type any chat message."""
        rows = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
        key_w, key_h, gap = 0.135, 0.11, 0.008
        y0 = 0.18
        for r, row in enumerate(rows):
            total = len(row) * (key_w + gap) - gap
            x0 = -total / 2
            for i, ch in enumerate(row):
                label = ch.upper()
                self._add_btn(x0 + i * (key_w + gap), y0 - r * (key_h + gap),
                              key_w, key_h, label,
                              lambda c=ch: self.game._append_chat(c),
                              color=(0.16, 0.18, 0.24))
        yb = y0 - 4 * (key_h + gap)
        self._add_btn(-0.88, yb, 0.28, key_h, "DEL",
                      lambda: self.game._handle_key("backspace"),
                      color=(0.45, 0.18, 0.18))
        self._add_btn(-0.56, yb, 0.72, key_h, "SPACE",
                      lambda: self.game._append_chat(" "),
                      color=(0.20, 0.22, 0.28))
        self._add_btn(0.20, yb, 0.22, key_h, ",",
                      lambda: self.game._append_chat(","))
        self._add_btn(0.44, yb, 0.22, key_h, ".",
                      lambda: self.game._append_chat("."))
        self._add_btn(0.68, yb, 0.28, key_h, "SEND",
                      lambda: self.game._send_chat(),
                      color=(0.12, 0.48, 0.22))

    def sync(self):
        self._clear()
        ax = self.aspect()
        # Tiny toggle so desktop players can turn the overlay on.
        self._add_btn(ax - 0.38, 0.88, 0.34, 0.10,
                      "TOUCH " + ("ON" if self.enabled else "OFF"),
                      self._toggle, color=(0.25, 0.22, 0.35))
        if not self.enabled:
            return
        st = self.game.state
        if st == "menu":
            row_w, row_h, gap = 0.62, 0.11, 0.02
            x0 = -row_w * 1.5 - gap
            y0 = -0.92
            items = [
                ("1 PLAYER", lambda: self.game._handle_key("1"), (0.15, 0.45, 0.22)),
                ("SPLIT RACE", lambda: self.game._handle_key("2"), (0.15, 0.32, 0.55)),
                ("FREE PLAY", lambda: self.game._handle_key("3"), (0.55, 0.38, 0.12)),
            ]
            for i, (lab, act, col) in enumerate(items):
                self._add_btn(x0 + i * (row_w + gap), y0 + 0.26, row_w, row_h,
                              lab, act, color=col)
            self._add_btn(x0, y0 + 0.13, row_w * 3 + gap * 2, row_h,
                          "ONLINE MULTIPLAYER",
                          lambda: self.game._handle_key("4"),
                          color=(0.12, 0.42, 0.48))
            self._add_btn(x0, y0, row_w * 1.5 + gap * 0.5, row_h,
                          "GUN COMBAT",
                          lambda: self.game._handle_key("5"),
                          color=(0.50, 0.16, 0.16))
            self._add_btn(x0 + row_w * 1.5 + gap * 1.5, y0, row_w * 1.5 + gap * 0.5, row_h,
                          "GUNS " + ("ON" if getattr(self.game, "gun_enabled", False) else "OFF"),
                          lambda: self.game._handle_key("u"),
                          color=(0.42, 0.18, 0.18))
            opts = [
                ("LAPS", "l"), ("AI CARS", "o"), ("POLICE", "p"),
                ("FP SPLIT", "f"), ("GRAPHICS", "g"), ("WEATHER", "t"),
            ]
            y_opts = y0 - row_h - gap
            for i, (lab, key) in enumerate(opts):
                self._add_btn(x0 + (i % 3) * (row_w + gap),
                              y_opts - (i // 3) * (row_h + gap),
                              row_w, row_h, lab,
                              lambda k=key: self.game._handle_key(k),
                              color=(0.18, 0.20, 0.28))
        elif st == "car_select":
            self._add_btn(-ax + 0.08, -0.15, 0.38, 0.16, "< CAR",
                          lambda: self.game._handle_key("arrow_left"))
            self._add_btn(-ax + 0.50, -0.15, 0.38, 0.16, "CAR >",
                          lambda: self.game._handle_key("arrow_right"))
            self._add_btn(-ax + 0.08, -0.36, 0.38, 0.16, "< PAINT",
                          lambda: self.game._handle_key("arrow_up"))
            self._add_btn(-ax + 0.50, -0.36, 0.38, 0.16, "PAINT >",
                          lambda: self.game._handle_key("arrow_down"))
            self._add_btn(ax - 0.72, -0.15, 0.64, 0.16, "CONFIRM",
                          lambda: self.game._handle_key("enter"),
                          color=(0.12, 0.48, 0.22))
            self._add_btn(ax - 0.72, -0.36, 0.64, 0.16, "BACK",
                          lambda: self.game._handle_key("escape"),
                          color=(0.45, 0.18, 0.18))
        elif st == "map_select":
            self._add_btn(-0.70, -0.92, 0.40, 0.14, "< MAP",
                          lambda: self.game._handle_key("arrow_left"))
            self._add_btn(0.30, -0.92, 0.40, 0.14, "MAP >",
                          lambda: self.game._handle_key("arrow_right"))
            self._add_btn(-0.22, -0.92, 0.44, 0.14, "START",
                          lambda: self.game._handle_key("enter"),
                          color=(0.12, 0.48, 0.22))
            self._add_btn(ax - 0.50, -0.92, 0.42, 0.14, "BACK",
                          lambda: self.game._handle_key("escape"),
                          color=(0.45, 0.18, 0.18))
        elif st == "online":
            self._add_btn(-0.70, -0.20, 0.62, 0.18, "HOST ROOM",
                          lambda: self.game._handle_key("h"),
                          color=(0.12, 0.48, 0.22))
            self._add_btn(0.08, -0.20, 0.62, 0.18, "JOIN ROOM",
                          lambda: self.game._handle_key("j"),
                          color=(0.15, 0.32, 0.55))
            self._add_btn(-0.32, -0.46, 0.64, 0.16, "BACK",
                          lambda: self.game._handle_key("escape"),
                          color=(0.45, 0.18, 0.18))
        elif st == "online_join":
            labels = "1234567890"
            for i, ch in enumerate(labels):
                col, row = i % 5, i // 5
                self._add_btn(-0.70 + col * 0.28, 0.10 - row * 0.18, 0.25, 0.15,
                              ch, lambda c=ch: self.game._type_char(c))
            self._add_btn(-0.70, -0.36, 0.40, 0.15, "DEL",
                          lambda: self.game._handle_key("backspace"),
                          color=(0.45, 0.18, 0.18))
            self._add_btn(-0.26, -0.36, 0.54, 0.15, "JOIN",
                          lambda: self.game._handle_key("enter"),
                          color=(0.12, 0.48, 0.22))
            self._add_btn(0.32, -0.36, 0.40, 0.15, "BACK",
                          lambda: self.game._handle_key("escape"),
                          color=(0.35, 0.18, 0.18))
        elif st == "online_wait":
            self._add_btn(-0.70, -0.55, 0.54, 0.16, "CHAT",
                          lambda: self.game._toggle_chat(),
                          color=(0.20, 0.28, 0.40))
            if getattr(self.game.fb, "host", False):
                self._add_btn(-0.12, -0.55, 0.54, 0.16, "START",
                              lambda: self.game._handle_key("enter"),
                              color=(0.12, 0.48, 0.22))
            self._add_btn(0.46, -0.55, 0.42, 0.16, "LEAVE",
                          lambda: self.game._handle_key("escape"),
                          color=(0.45, 0.18, 0.18))
            if self.game.chat_open:
                self._add_chat_keyboard()
        elif st == "race":
            if getattr(self.game, "chat_open", False) and getattr(self.game, "online", False):
                self._add_btn(0.54, 0.82, 0.32, 0.12, "CHAT",
                              lambda: self.game._toggle_chat(),
                              color=(0.12, 0.40, 0.42))
                self._add_chat_keyboard()
            else:
                self._add_joy(-ax + 0.42, -0.42, 0.28)
                self._add_btn(ax - 0.34, -0.38, 0.28, 0.22, "GAS",
                              "gas", hold=True, color=(0.12, 0.50, 0.22))
                self._add_btn(ax - 0.34, -0.66, 0.28, 0.22, "BRAKE",
                              "brake", hold=True, color=(0.55, 0.16, 0.16))
                if getattr(self.game, "gun_enabled", False):
                    self._add_btn(ax - 0.66, -0.52, 0.28, 0.22, "FIRE",
                                  "fire", hold=True, color=(0.70, 0.45, 0.12))
                self._add_btn(-0.16, 0.82, 0.32, 0.12, "CAM",
                              lambda: self.game._handle_key("c"),
                              color=(0.20, 0.28, 0.40))
                self._add_btn(0.20, 0.82, 0.32, 0.12, "MENU",
                              lambda: self.game._handle_key("escape"),
                              color=(0.45, 0.18, 0.18))
                self._add_btn(-0.52, 0.82, 0.32, 0.12, "RETRY",
                              lambda: self.game._handle_key("r"),
                              color=(0.30, 0.26, 0.14))
                if getattr(self.game, "online", False):
                    self._add_btn(0.54, 0.82, 0.32, 0.12, "CHAT",
                                  lambda: self.game._toggle_chat(),
                                  color=(0.12, 0.40, 0.42))

    def _toggle(self):
        self.enabled = not self.enabled
        self.game.touch_enabled = self.enabled
        self.sync()

    def _inside(self, frame, mx, my):
        x0, x1, y0, y1 = frame
        return x0 <= mx <= x1 and y0 <= my <= y1

    def poll(self):
        game = self.game
        game.touch_steer = 0.0
        game.touch_throttle = 0.0
        game.touch_fire = False
        mw = getattr(game, "mouseWatcherNode", None)
        if mw is None:
            return
        has = mw.hasMouse()
        down = bool(has and mw.isButtonDown(MouseButton.one()))
        ax = self.aspect()
        mx = mw.getMouseX() * ax if has else 0.0
        my = mw.getMouseY() if has else 0.0
        clicked = self._prev_down and not down
        self._prev_down = down

        gas = brake = False
        clicks = []
        if self.enabled and self.joy and game.state == "race" and not game.chat_open:
            cx, cy, r = self.joy["cx"], self.joy["cy"], self.joy["r"]
            dx, dy = mx - cx, my - cy
            dist = math.hypot(dx, dy)
            if down and (self._joy_grabbed or dist <= r * 1.15):
                self._joy_grabbed = True
                if dist > r and dist > 1e-6:
                    dx, dy = dx / dist * r, dy / dist * r
                game.touch_steer = clamp(-dx / r, -1.0, 1.0)
                game.touch_throttle = clamp(dy / r, -1.0, 1.0)
                if abs(game.touch_steer) < 0.18:
                    game.touch_steer = 0.0
                if abs(game.touch_throttle) < 0.18:
                    game.touch_throttle = 0.0
                if self.joy_knob:
                    self.joy_knob.setPos(dx, 0, dy)
            else:
                self._joy_grabbed = False
                if self.joy_knob:
                    self.joy_knob.setPos(0, 0, 0)

        for btn in self.buttons:
            inside = has and self._inside(btn["frame"], mx, my)
            btn["inside"] = inside
            col = btn["color"]
            if inside and down:
                btn["node"].setColor(col[0] + 0.15, col[1] + 0.15, col[2] + 0.15, 0.85)
            else:
                btn["node"].setColor(*col, 0.62)
            if self.enabled and btn["hold"] and down and inside:
                if btn["action"] == "gas":
                    gas = True
                elif btn["action"] == "brake":
                    brake = True
                elif btn["action"] == "fire":
                    game.touch_fire = True
            elif (not btn["hold"]) and clicked and inside:
                clicks.append(btn["action"])

        if gas:
            game.touch_throttle = 1.0
        elif brake:
            game.touch_throttle = -1.0
        for act in clicks:
            if callable(act):
                act()


class ChatOverlay:
    """Race/lobby chat log + input line. Lives outside _clear_ui()."""

    def __init__(self, game):
        self.game = game
        self.root = game.aspect2d.attachNewNode("chat")
        self.root.setBin("fixed", 80)
        self.root.setDepthTest(False)
        self.root.setDepthWrite(False)
        self.lines = []
        for i in range(8):
            self.lines.append(OnscreenText(
                text="", pos=(-ASPECT + 0.08, 0.58 - i * 0.055),
                scale=0.038, fg=(0.92, 0.95, 1.0, 1),
                align=TextNode.ALeft, shadow=(0, 0, 0, 0.85),
                parent=self.root))
        self.input = OnscreenText(
            text="", pos=(-ASPECT + 0.08, -0.72), scale=0.042,
            fg=(1.0, 0.92, 0.45, 1), align=TextNode.ALeft,
            shadow=(0, 0, 0, 0.9), parent=self.root)
        self.status = OnscreenText(
            text="", pos=(-ASPECT + 0.08, 0.70), scale=0.040,
            fg=(0.55, 0.95, 0.75, 1), align=TextNode.ALeft,
            shadow=(0, 0, 0, 0.85), parent=self.root)
        self.hide()

    def hide(self):
        self.root.hide()

    def show(self):
        self.root.show()

    def refresh(self, snap, typing, buf):
        if not snap.get("room"):
            self.hide()
            return
        self.show()
        room = snap.get("room") or ""
        n = len(snap.get("players") or {})
        err = snap.get("error") or ""
        host = "HOST" if snap.get("host") else "GUEST"
        self.status.setText(
            err[:60] if err else f"ROOM {room}   {host}   {n} online")
        msgs = snap.get("chat") or []
        visible = msgs[-8:]
        pad = 8 - len(visible)
        for i, label in enumerate(self.lines):
            if i < pad:
                label.setText("")
            else:
                msg = visible[i - pad]
                name = str(msg.get("name") or "?")[:10]
                text = str(msg.get("text") or "")[:42]
                label.setText(f"{name}: {text}")
        if typing:
            self.input.setText("> " + buf + "_")
        else:
            self.input.setText("ENTER chat   ESC close")


# --------------------------------------------------------------------- HUD
class PlayerHUD:
    """
    Speedometer gauge + minimap + lap/pos text for one player, laid out
    inside a vertical band of the screen (full screen, or half of it in
    split-screen mode). Built from aspect2d geometry — no textures.
    """

    def __init__(self, game, band_bottom, band_top, compact=False):
        self.game = game
        self.root = game.aspect2d.attachNewNode("hud")
        self.band = (band_bottom, band_top)
        self.compact = compact
        mid_y = (band_bottom + band_top) / 2
        scale = 0.5 * (band_top - band_bottom)

        self.touch_ui = bool(getattr(game, "touch_enabled", False))
        self.gauge_r = 0.30 * (0.75 if compact else 1.0)
        if self.touch_ui and not compact:
            # Keep the dial above GAS/BRAKE and the map above the joystick.
            self.gauge_c = (ASPECT - self.gauge_r - 0.12, 0.22)
            self.map_c = (-ASPECT + 0.14, 0.18)
        else:
            self.gauge_c = (ASPECT - self.gauge_r - 0.12,
                            band_bottom + self.gauge_r + 0.10)
            self.map_c = (-ASPECT + 0.14, band_bottom + 0.12)
        self._build_gauge_static()

        self.map_size = 0.42 * (0.8 if compact else 1.0)
        self.map_node = self.root.attachNewNode("minimap")
        self.car_dots = []

        ts = 0.05 if compact else 0.055
        self.lap_text = OnscreenText(parent=self.root, align=TextNode.ALeft,
                                     pos=(-ASPECT + 0.10, band_top - 0.12),
                                     scale=ts, fg=(1, 1, 1, 1),
                                     shadow=(0, 0, 0, 0.8))
        self.name_text = OnscreenText(parent=self.root, align=TextNode.ARight,
                                      pos=(ASPECT - 0.10, band_top - 0.12),
                                      scale=ts, fg=(1, 0.86, 0.35, 1),
                                      shadow=(0, 0, 0, 0.8))
        self.banner = OnscreenText(parent=self.root, align=TextNode.ACenter,
                                   pos=(0, mid_y + scale * 0.15),
                                   scale=ts * 3.2, fg=(1, 0.9, 0.3, 1),
                                   shadow=(0, 0, 0, 0.9))
        self.speed_text = OnscreenText(parent=self.root, align=TextNode.ACenter,
                                       pos=(self.gauge_c[0], self.gauge_c[1] - self.gauge_r * 0.55),
                                       scale=ts * 1.4, fg=(1, 1, 1, 1),
                                       shadow=(0, 0, 0, 0.9))
        bounty_y = (band_top - 0.32) if self.touch_ui else (band_bottom + 0.28)
        heat_y = (band_top - 0.40) if self.touch_ui else (band_bottom + 0.20)
        self.bounty_text = OnscreenText(parent=self.root, align=TextNode.ALeft,
                                        pos=(-ASPECT + 0.10, bounty_y),
                                        scale=ts * 1.1, fg=(1, 0.75, 0.25, 1),
                                        shadow=(0, 0, 0, 0.85))
        self.heat_text = OnscreenText(parent=self.root, align=TextNode.ALeft,
                                      pos=(-ASPECT + 0.10, heat_y),
                                      scale=ts, fg=(1, 0.35, 0.30, 1),
                                      shadow=(0, 0, 0, 0.85))
        self.cp_text = OnscreenText(parent=self.root, align=TextNode.ALeft,
                                    pos=(-ASPECT + 0.10, band_top - 0.22),
                                    scale=ts * 0.95, fg=(0.55, 0.95, 0.85, 1),
                                    shadow=(0, 0, 0, 0.85))
        self.streak_text = OnscreenText(parent=self.root, align=TextNode.ARight,
                                        pos=(ASPECT - 0.10, band_top - 0.22),
                                        scale=ts * 0.9, fg=(1.0, 0.78, 0.35, 1),
                                        shadow=(0, 0, 0, 0.85))
        cam_pos = ((ASPECT - 0.10, 10.0) if self.touch_ui
                   else (ASPECT - 0.10, band_bottom + 0.08))
        self.cam_text = OnscreenText(parent=self.root, align=TextNode.ARight,
                                     pos=cam_pos,
                                     scale=ts * 0.85, fg=(0.75, 0.8, 0.9, 1),
                                     shadow=(0, 0, 0, 0.85))
        self.needle = None
        self.root.setBin("fixed", 40)

    # ------------------------------------------------------------------
    def _build_gauge_static(self):
        cx, cy = self.gauge_c
        r = self.gauge_r
        # Dial disc (triangle fan as a Geom).
        mb = MeshBuilder("dial")
        seg = 40
        for i in range(seg):
            a0 = 2 * math.pi * i / seg
            a1 = 2 * math.pi * (i + 1) / seg
            mb.tri((cx, 0, cy),
                   (cx + math.cos(a0) * r, 0, cy + math.sin(a0) * r),
                   (cx + math.cos(a1) * r, 0, cy + math.sin(a1) * r),
                   (0.02, 0.02, 0.04, 0.62), (0, -1, 0))
        disc = mb.build()
        disc.reparentTo(self.root)
        disc.setTransparency(TransparencyAttrib.MAlpha)
        disc.setLightOff(1)
        # Ticks.
        ls = LineSegs("ticks")
        ls.setThickness(2.5)
        ls.setColor(1, 1, 1, 0.9)
        dial_max = MAX_DIAL_KMH
        v = 0
        while v <= dial_max:
            f = v / dial_max
            a = math.radians(210.0 - 240.0 * f)
            r0 = r * (0.74 if v % 100 == 0 else 0.84)
            ls.moveTo(cx + math.cos(a) * r0, 0, cy + math.sin(a) * r0)
            ls.drawTo(cx + math.cos(a) * r * 0.93, 0, cy + math.sin(a) * r * 0.93)
            v += 50
        self.root.attachNewNode(ls.create()).setLightOff(1)
        self.dial_max = dial_max

    def build_minimap(self, points, map_point_fn):
        """(Re)build the track outline; called when a race starts."""
        self.map_node.removeNode()
        self.map_node = self.root.attachNewNode("minimap")
        self._map_fn = map_point_fn
        ox, oy = self.map_c
        s = self.map_size
        ls = LineSegs("outline")
        ls.setThickness(2.5)
        ls.setColor(0.95, 0.95, 0.98, 0.85)
        pts = points[::2]
        first = None
        for i, (px, py) in enumerate(pts):
            x, z = ox + px * s, oy + py * s
            if i == 0:
                first = (x, z)
                ls.moveTo(x, 0, z)
            else:
                ls.drawTo(x, 0, z)
        ls.drawTo(first[0], 0, first[1])
        self.map_node.attachNewNode(ls.create()).setLightOff(1)
        self.car_dots = []

    def make_car_dots(self, cars, player_car):
        for dot, ring, _ in self.car_dots:
            dot.removeNode()
            if ring:
                ring.removeNode()
        self.car_dots = []
        for car in cars:
            size = 0.016 if car is player_car else 0.011
            ring = None
            if car is player_car:
                # White ring drawn first so the colored dot sits on top.
                cm2 = CardMaker("ring")
                cm2.setFrame(-size * 1.5, size * 1.5, -size * 1.5, size * 1.5)
                ring = self.map_node.attachNewNode(cm2.generate())
                ring.setColor(1, 1, 1, 1)
                ring.setLightOff(1)
            cm = CardMaker("dot")
            cm.setFrame(-size, size, -size, size)
            dot = self.map_node.attachNewNode(cm.generate())
            if car.is_police:
                dot.setColor(0.25, 0.45, 0.95, 1.0)
            else:
                dot.setColor(*car.color, 1.0)
            dot.setLightOff(1)
            self.car_dots.append((dot, ring, car))

    def update(self, car, game):
        kmh = abs(car.speed) * 3.6
        cx, cy = self.gauge_c
        r = self.gauge_r
        # Needle rebuilt each frame (cheap: 1 line segment).
        if self.needle:
            self.needle.removeNode()
        f = clamp(kmh / self.dial_max, 0.0, 1.0)
        a = math.radians(210.0 - 240.0 * f)
        ls = LineSegs("needle")
        ls.setThickness(4.0)
        ls.setColor(0.95, 0.15, 0.15, 1.0)
        ls.moveTo(cx, 0, cy)
        ls.drawTo(cx + math.cos(a) * r * 0.80, 0, cy + math.sin(a) * r * 0.80)
        self.needle = self.root.attachNewNode(ls.create())
        self.needle.setLightOff(1)
        self.speed_text.setText(f"{int(kmh)} km/h")

        if getattr(game, "online", False):
            room = ""
            if getattr(game, "fb", None):
                room = game.fb.room
            extra = f"   ROOM {room}" if room else "   ONLINE"
            mode = "  GUNS" if getattr(game, "gun_enabled", False) else ""
            self.lap_text.setText(f"LAP {max(car.lap, 1)}   ONLINE{extra}{mode}")
        elif game.free_play:
            tag = "GUN COMBAT" if getattr(game, "gun_enabled", False) else "FREE PLAY"
            self.lap_text.setText(f"LAP {max(car.lap, 1)}   {tag}")
        else:
            total = game.total_laps
            racers = sum(1 for c in game.cars if not c.is_police)
            lap = clamp(car.lap, 1, total)
            self.lap_text.setText(
                f"LAP {lap}/{total}   POS {car.race_pos}/{racers}")

        if getattr(game, "gun_enabled", False):
            hp = int(clamp(car.hp, 0, HP_MAX))
            self.bounty_text.setText(f"HP  {hp}    KILLS  {car.kills}")
            if car.wreck_t > 0:
                self.heat_text.setText("WRECKED")
            elif getattr(game, "_kill_flash", 0) > 0:
                self.heat_text.setText(getattr(game, "_kill_text", "")[:42])
            else:
                self.heat_text.setText("")
        elif game.free_play and game.police_enabled and game.track.spec.get("city"):
            self.bounty_text.setText(f"BOUNTY  ${int(game.bounty):,}")
            stars = min(5, int(round(game.heat)))
            self.heat_text.setText("HEAT  " + "*" * stars + "." * (5 - stars))
        else:
            self.bounty_text.setText("")
            self.heat_text.setText("")

        # Checkpoints + streak + camera mode.
        if not game.free_play:
            self.cp_text.setText(
                f"CP {car.checkpoints_hit}/{CHECKPOINT_COUNT}")
        else:
            self.cp_text.setText("")
        if game.win_streak > 0:
            self.streak_text.setText(f"WIN STREAK x{game.win_streak}")
        else:
            self.streak_text.setText("")
        if getattr(game, "touch_enabled", False):
            self.cam_text.setText("")
        else:
            self.cam_text.setText(f"C  {game.camera_mode}")

        # Countdown / GO / finished banners.
        if game.race_time < 0.0:
            self.banner.setText(str(math.ceil(-game.race_time)))
        elif game.race_time < 1.0:
            self.banner.setText("GO!")
        elif car in game.finish_order:
            self.banner.setText(f"FINISHED  -  P{game.finish_order.index(car) + 1}")
        elif car.wreck_t > 0 and getattr(game, "gun_enabled", False) and car is game.players[0][0]:
            self.banner.setText("WRECKED")
        elif getattr(game, "_kill_flash", 0) > 0.6:
            self.banner.setText(getattr(game, "_kill_text", ""))
        elif getattr(game, "_cp_flash", 0) > 0 and car is game.players[0][0]:
            self.banner.setText("CHECKPOINT")
        else:
            self.banner.setText("")

        ox, oy = self.map_c
        s = self.map_size
        for dot, ring, dcar in self.car_dots:
            px, py = self._map_fn(dcar.x, dcar.y)
            dot.setPos(ox + px * s, 0, oy + py * s)
            if ring:
                ring.setPos(ox + px * s, 0.01, oy + py * s)

    def destroy(self):
        self.root.removeNode()


# -------------------------------------------------------------------- game
class RacingGame(ShowBase):
    """Owns the engine, world, menus, HUD and the simulation loop."""

    def __init__(self):
        ShowBase.__init__(self)
        self.disableMouse()
        clock = ClockObject.getGlobalClock()
        clock.setMode(ClockObject.MLimited)
        clock.setFrameRate(FPS)

        self.render.setAntialias(AntialiasAttrib.MMultisample if not USE_GLES
                                 else AntialiasAttrib.MNone)
        self.camLens.setFov(FOV_DEGREES)
        self.camLens.setNearFar(1.0, 1800.0)

        # --- lights ---
        self.ambient = AmbientLight("ambient")
        # Ambient + full sun must stay below ~0.95 or upward-facing
        # surfaces clip to white and the scene looks washed out.
        self.ambient.setColor((0.30, 0.30, 0.33, 1.0))
        self.ambient_np = self.render.attachNewNode(self.ambient)
        self.render.setLight(self.ambient_np)

        self.sun = DirectionalLight("sun")
        self.sun_np = self.render.attachNewNode(self.sun)
        self.sun_np.setHpr(-35.0, -55.0, 0.0)
        lens = self.sun.getLens()
        lens.setFilmSize(110, 110)
        lens.setNearFar(-250.0, 400.0)
        # Anti-"shadow acne": render back faces into the shadow map AND
        # push depths slightly away from the light. The depth offset is
        # what stops striping on thin shells like the car model bodies.
        self.sun.setInitialState(RenderState.make(
            CullFaceAttrib.makeReverse(), DepthOffsetAttrib.make(-4)))
        self.render.setLight(self.sun_np)

        # Per-pixel lighting / materials / shadows via the shader generator.
        # Android GLES cannot use the Cg shader generator yet.
        if not USE_GLES:
            self.render.setShaderAuto()

        # Draw-mask bits so rain rigs can be excluded from the shadow map
        # and from the other player's viewport.
        self.cam.node().setCameraMask(MASK_CAM1)
        try:
            self.sun.setCameraMask(MASK_SHADOW)
        except AttributeError:
            pass

        self.fog = Fog("fog")
        self.render.setFog(self.fog)

        self.sky_colors = (MAPS[0]["theme"]["sky"], MAPS[0]["theme"]["sky_top"])
        self.sky = self._build_sky()

        # --- real car models (Kenney Car Kit, CC0) ---
        self.car_assets = CarAssets(self.loader)

        # --- weather sounds (synthesized at startup, no asset files) ---
        try:
            rain_path, thunder_path, gun_path = synth_weather_sounds()
            self.rain_sfx = self.loader.loadSfx(Filename.fromOsSpecific(rain_path))
            self.thunder_sfx = self.loader.loadSfx(Filename.fromOsSpecific(thunder_path))
            self.gun_sfx = self.loader.loadSfx(Filename.fromOsSpecific(gun_path))
            self.rain_sfx.setLoop(True)
        except Exception as exc:
            print(f"Audio unavailable: {exc}")
            self.rain_sfx = self.thunder_sfx = self.gun_sfx = None

        # --- input state ---
        # One handler per key: records held state (for driving) AND feeds
        # the menu logic. Registering two accepts for the same event would
        # silently replace the first one.
        self.keys = {}
        type_keys = tuple("abcdefghijklmnopqrstuvwxyz0123456789") + (
            "arrow_up", "arrow_down", "arrow_left", "arrow_right",
            "enter", "space", "escape", "backspace",
            "period", "comma", "slash", "semicolon", "minus", "equals",
            "quote", "shift", "control", "lcontrol", "rcontrol")
        for key in type_keys:
            self.accept(key, self._on_key_down, [key])
            self.accept(key + "-up", self.keys.__setitem__, [key, False])
        self.accept("shift-up", self._on_shift_up)
        self.accept("mouse1", self._on_mouse_fire, [True])
        self.accept("mouse1-up", self._on_mouse_fire, [False])
        try:
            self.buttonThrowers[0].node().setKeystrokeEvent("keystroke")
            self.accept("keystroke", self._on_keystroke)
        except Exception:
            pass
        self._shift = False
        self._chat_dup = None

        # --- weather / effects state ---
        self.weather_idx = 0
        self.precip_rigs = []        # (rig, camera NodePath it follows)
        self.grades = []             # (FilterManager, fullscreen quad)
        self.flash = 0.0             # lightning white-out level
        self.next_strike = 0.0
        self.thunder_in = None
        self.windshield = WindshieldRain(self.aspect2d)
        self.windshield.set_active(False)
        self.touch_steer = 0.0
        self.touch_throttle = 0.0
        self.touch_fire = False
        self._mouse_fire = False
        self.gun_enabled = False
        self.bullets = []
        self._seen_shots = set()
        self._credited_kills = set()
        self._shot_seq = 0
        self._kill_flash = 0.0
        self._kill_text = ""
        self.gun_sfx = getattr(self, "gun_sfx", None)
        self.touch_enabled = bool(TOUCH_DEFAULT)
        self.touch = TouchControls(self)
        self.fb = firebase_mp.FirebaseSession()
        self.online = False
        self.online_host = False
        self.chat_open = False
        self.chat_buf = ""
        self.join_buf = ""
        self.chat_ui = ChatOverlay(self)
        self._remote_by_uid = {}

        # --- game state ---
        self.quality_idx = 0 if ANDROID else 1
        self.map_idx = 0
        self.track = None
        self.world = None
        self.lap_option_idx = LAP_OPTIONS.index(DEFAULT_LAPS)
        self.opponent_option_idx = 2          # 3 opponents by default
        self.police_enabled = True            # free-play police toggle
        self.freeplay_split = False
        self.camera_mode = "CHASE"
        self.win_streak = 0
        self._cp_flash = 0.0
        self.checkpoint_markers = []
        self.build_track(0)

        self.state = None
        self.menu_time = 0.0
        self.split = False
        self.free_play = False
        self.pending = (False, False)
        self.select_player = 0
        self.selections = [{"model": 0, "color": 0}, {"model": 1, "color": 3}]
        self.bounty = 0.0
        self.heat = 0.0
        self.chase_bonus = 0.0

        self.cars = []
        self.controllers = []
        self.players = []            # (car, ChaseCamera)
        self.huds = []
        self.race_time = 0.0
        self.finish_order = []

        self.cam2_np = None
        self.dr2 = None
        self.main_dr = None
        for dr in self.win.getDisplayRegions():
            if dr.getCamera() == self.cam:
                self.main_dr = dr

        self.car_root = self.render.attachNewNode("cars")
        self.bullet_root = self.render.attachNewNode("bullets")
        self.showroom = self._build_showroom()
        self.showroom.hide()
        self.preview_car = None
        self.ui_nodes = []           # current menu screen widgets

        self._apply_quality()
        self._setup_grades()
        self._enter_menu()
        self.taskMgr.add(self._update, "update")

    # --------------------------------------------------------- environment
    def _build_sky(self):
        """Gradient sky dome: a big inverted hemisphere with vertex colors
        blending the horizon color up into the zenith color."""
        mb = MeshBuilder("sky")
        radius = 1400.0
        rings, slices = 8, 24
        horizon, zenith = self.sky_colors

        def ring_color(f):
            a, b = horizon, zenith
            return (lerp(a[0], b[0], f), lerp(a[1], b[1], f), lerp(a[2], b[2], f), 1.0)

        for ri in range(rings):
            f0, f1 = ri / rings, (ri + 1) / rings
            z0 = math.sin(f0 * math.pi / 2) * radius * 0.5
            z1 = math.sin(f1 * math.pi / 2) * radius * 0.5
            r0 = math.cos(f0 * math.pi / 2) * radius
            r1 = math.cos(f1 * math.pi / 2) * radius
            for si in range(slices):
                a0 = 2 * math.pi * si / slices
                a1 = 2 * math.pi * (si + 1) / slices
                v0 = (math.cos(a0) * r0, math.sin(a0) * r0, z0 - 4)
                v1 = (math.cos(a1) * r0, math.sin(a1) * r0, z0 - 4)
                v2 = (math.cos(a1) * r1, math.sin(a1) * r1, z1 - 4)
                v3 = (math.cos(a0) * r1, math.sin(a0) * r1, z1 - 4)
                # Interpolate color via two triangles with per-ring colors.
                c0, c1 = ring_color(f0), ring_color(f1)
                i0 = mb._vertex(v0, (0, 0, -1), c0, (0, 0))
                i1 = mb._vertex(v1, (0, 0, -1), c0, (0, 0))
                i2 = mb._vertex(v2, (0, 0, -1), c1, (0, 0))
                i3 = mb._vertex(v3, (0, 0, -1), c1, (0, 0))
                mb.prim.addVertices(i0, i2, i1)
                mb.prim.addVertices(i0, i3, i2)
        sky = mb.build()
        sky.reparentTo(self.render)
        sky.setLightOff(1)
        sky.setFogOff(1)
        sky.setShaderOff(1)
        sky.setBin("background", 0)
        sky.setDepthWrite(False)
        sky.hide(MASK_SHADOW)
        return sky

    def _env_colors(self):
        """Map theme colors blended toward storm grey by the weather."""
        theme = self.track.theme
        gloom = self.weather["gloom"]

        def blend(a, b):
            return tuple(lerp(a[i], b[i], gloom) for i in range(3))

        return blend(theme["sky"], STORM_SKY), blend(theme["sky_top"], STORM_SKY_TOP)

    def _tint_sky(self):
        """Rebuild the sky dome for the current map theme + weather."""
        self.sky.removeNode()
        self.sky_colors = self._env_colors()
        self.sky = self._build_sky()

    def _build_showroom(self):
        """Enclosed studio so the car-select camera never sees the sky dome
        or the filter buffer's leftover clear color (that horizon-cut look)."""
        root = self.render.attachNewNode("showroom")
        mb = MeshBuilder("showroom-geo")
        mb.quad((-80, -80, 0), (80, -80, 0), (80, 80, 0), (-80, 80, 0),
                (0.20, 0.21, 0.24, 1), normal=(0, 0, 1))
        seg = 32
        for i in range(seg):
            a0 = 2 * math.pi * i / seg
            a1 = 2 * math.pi * (i + 1) / seg
            mb.tri((0, 0, 0.03),
                   (math.cos(a0) * 3.4, math.sin(a0) * 3.4, 0.03),
                   (math.cos(a1) * 3.4, math.sin(a1) * 3.4, 0.03),
                   (0.32, 0.33, 0.37, 1), (0, 0, 1))
        s, h = 22.0, 14.0
        wall = (0.16, 0.17, 0.20, 1)
        mb.quad((-s, s, 0), (s, s, 0), (s, s, h), (-s, s, h),
                wall, normal=(0, -1, 0))
        mb.quad((s, -s, 0), (-s, -s, 0), (-s, -s, h), (s, -s, h),
                wall, normal=(0, 1, 0))
        mb.quad((-s, -s, 0), (-s, s, 0), (-s, s, h), (-s, -s, h),
                wall, normal=(1, 0, 0))
        mb.quad((s, s, 0), (s, -s, 0), (s, -s, h), (s, s, h),
                wall, normal=(-1, 0, 0))
        mb.quad((-s, -s, h), (-s, s, h), (s, s, h), (s, -s, h),
                wall, normal=(0, 0, -1))
        geo = mb.build()
        geo.reparentTo(root)
        geo.setMaterial(WORLD_MATERIAL, 1)
        geo.setFogOff(1)
        root.setFogOff(1)
        # Own lights so the preview is not a silhouette when the sun
        # is aimed at the track instead of this room.
        root.setLightOff(1)
        amb = AmbientLight("showroom-amb")
        amb.setColor((0.62, 0.62, 0.66, 1.0))
        root.setLight(root.attachNewNode(amb))
        key = DirectionalLight("showroom-key")
        key.setColor((0.90, 0.88, 0.84, 1.0))
        knp = root.attachNewNode(key)
        knp.setHpr(155, -28, 0)
        root.setLight(knp)
        fill = DirectionalLight("showroom-fill")
        fill.setColor((0.28, 0.30, 0.36, 1.0))
        fnp = root.attachNewNode(fill)
        fnp.setHpr(-40, -15, 0)
        root.setLight(fnp)
        return root

    # ------------------------------------------------------------- quality
    @property
    def quality(self):
        return QUALITY_PRESETS[self.quality_idx][1]

    def _apply_quality(self):
        q = self.quality
        # GLES has no Cg shader generator, so shadow maps cannot be enabled.
        if (not USE_GLES) and q["shadow"]:
            self.sun.setShadowCaster(True, q["shadow"], q["shadow"])
        else:
            self.sun.setShadowCaster(False)

    def build_track(self, idx):
        self.map_idx = idx
        if self.world is not None:
            self.world.removeNode()
        q = self.quality
        spec = MAPS[idx]
        scenery = int(90 * q["scenery"])
        if spec.get("city"):
            scenery = int(130 * q["scenery"])
        self.track = Track(spec, scenery_count=scenery)
        self.world = self.track.build_world(self.render)
        self._apply_weather()

        # Minimap mapping (normalized 0..1 box, aspect preserved).
        x0, x1, y0, y1 = self.track.bounds
        span = max(x1 - x0, y1 - y0) or 1.0
        offx = (1.0 - (x1 - x0) / span) / 2
        offy = (1.0 - (y1 - y0) / span) / 2
        self._mm = (x0, y0, span, offx, offy)
        self.minimap_pts = [self._map_point(x, y) for x, y in self.track.wps]

    def _map_point(self, x, y):
        x0, y0, span, offx, offy = self._mm
        return ((x - x0) / span + offx, (y - y0) / span + offy)

    # ------------------------------------------------------------- weather
    @property
    def weather(self):
        return WEATHERS[self.weather_idx][1]

    def _apply_weather(self):
        """Apply the current weather to sky, fog, lights, road and rain."""
        w = self.weather
        theme = self.track.theme
        q = self.quality
        horizon, _ = self._env_colors()

        self.fog.setColor(*horizon)
        self.fog.setLinearRange(theme["fog"][0] * q["fog"] * w["fog_mult"],
                                theme["fog"][1] * q["fog"] * w["fog_mult"])
        self._set_clear_color(horizon)
        sun_m = 0.72 * w["sun"]
        self.sun.setColor((theme["sun"][0] * sun_m, theme["sun"][1] * sun_m,
                           theme["sun"][2] * sun_m, 1.0))
        amb = 0.30 * w["amb"]
        self.ambient_base = (amb, amb, amb * 1.08)
        self.ambient.setColor((*self.ambient_base, 1.0))
        self._tint_sky()

        # Wet asphalt: dark + glossy so the sun and sky "reflect" in it.
        road = self.track.road_np
        if w["wet"]:
            road.setMaterial(WET_MATERIAL, 2)
            road.setColorScale(0.74, 0.75, 0.84, 1.0)
        else:
            road.setMaterial(WORLD_MATERIAL, 2)
            road.clearColorScale()

        # Precipitation rigs, one per active viewport camera.
        for rig, _cam in self.precip_rigs:
            rig.destroy()
        self.precip_rigs = []
        if w["precip"]:
            cams = [(self.camera, MASK_CAM2 | MASK_SHADOW)]
            if getattr(self, "cam2_np", None) is not None:
                cams.append((self.cam2_np, MASK_CAM1 | MASK_SHADOW))
            for cam_np, hide_mask in cams:
                rig = PrecipRig(self.render, w["precip"], w["fall"], hide_mask)
                rig.update(0.0, cam_np.getPos(self.render))
                self.precip_rigs.append((rig, cam_np))
        if getattr(self, "state", None) == "car_select":
            self._set_precip_visible(False)

        # Rain loop audio.
        if self.rain_sfx:
            if w["rain_vol"] > 0.0:
                self.rain_sfx.setVolume(w["rain_vol"])
                if self.rain_sfx.status() != self.rain_sfx.PLAYING:
                    self.rain_sfx.play()
            else:
                self.rain_sfx.stop()

        self.flash = 0.0
        self.next_strike = random.uniform(3.0, 7.0)
        self.thunder_in = None
        if getattr(self, "state", None) == "race":
            self._apply_camera_mode()

    def _set_precip_visible(self, visible):
        for rig, _cam in self.precip_rigs:
            if visible:
                rig.root.show()
                rig.root.hide(MASK_SHADOW)
            else:
                rig.root.hide()

    def _update_weather_fx(self, dt):
        """Rain follows the cameras; lightning flashes + delayed thunder."""
        for rig, cam_np in self.precip_rigs:
            rig.update(dt, cam_np.getPos(self.render))

        if self.weather["lightning"]:
            self.next_strike -= dt
            if self.next_strike <= 0.0:
                self.flash = 1.0
                self.next_strike = random.uniform(4.0, 11.0)
                self.thunder_in = random.uniform(0.4, 1.8)
            if self.thunder_in is not None:
                self.thunder_in -= dt
                if self.thunder_in <= 0.0:
                    self.thunder_in = None
                    if self.thunder_sfx:
                        self.thunder_sfx.setVolume(0.9)
                        self.thunder_sfx.play()
        if self.flash > 0.001:
            self.flash *= math.exp(-7.0 * dt)
            a = self.ambient_base
            f = self.flash * 0.9
            self.ambient.setColor((a[0] + f, a[1] + f, a[2] + f, 1.0))
        elif self.flash != 0.0:
            self.flash = 0.0
            self.ambient.setColor((*self.ambient_base, 1.0))
        for _mgr, quad in self.grades:
            quad.setShaderInput("flash", self.flash * 0.32)

    # ------------------------------------------- post-process color grade
    def _set_clear_color(self, rgb):
        """Keep the window and every FilterManager scene buffer in sync.
        The post-process FBO copies clear color once at creation; changing
        only ShowBase.setBackgroundColor leaves a stale sky strip."""
        c = (*rgb, 1.0)
        self.setBackgroundColor(*rgb)
        if getattr(self, "win", None) is not None:
            self.win.setClearColor(c)
        for mgr, _quad in getattr(self, "grades", []):
            for buf in mgr.buffers:
                buf.setClearColor(c)
                buf.setClearColorActive(True)

    def _setup_grades(self):
        """(Re)build the NFSMW color-grade filter for each active camera."""
        for mgr, _quad in self.grades:
            mgr.cleanup()
        self.grades = []
        if USE_GLES:
            shader = Shader.make(Shader.SL_GLSL, GRADE_VERT_ES, GRADE_FRAG_ES)
        else:
            shader = Shader.make(Shader.SL_GLSL, GRADE_VERT, GRADE_FRAG)
        cams = [self.cam]
        if self.dr2 is not None:
            cams.append(self.cam2_np)
        samples = 0
        try:
            samples = int(self.win.getFbProperties().getMultisamples())
        except Exception:
            samples = 0
        for cam in cams:
            mgr = FilterManager(self.win, cam)
            tex = Texture()
            try:
                if (not USE_GLES) and samples > 0:
                    fbp = FrameBufferProperties()
                    fbp.setMultisamples(samples)
                    try:
                        quad = mgr.renderSceneInto(colortex=tex, fbprops=fbp)
                    except TypeError:
                        quad = mgr.renderSceneInto(colortex=tex)
                else:
                    quad = mgr.renderSceneInto(colortex=tex)
            except Exception as exc:
                print(f"Post-process buffer unavailable; skipping color grade: {exc}")
                continue
            if quad is None:
                print("Post-process buffer unavailable; skipping color grade")
                continue
            quad.setShader(shader, 1)
            quad.setShaderInput("tex", tex)
            quad.setShaderInput("flash", 0.0)
            self.grades.append((mgr, quad))

    # -------------------------------------------------------------- states
    def _clear_ui(self):
        for np_ in self.ui_nodes:
            np_.destroy() if isinstance(np_, OnscreenText) else np_.removeNode()
        self.ui_nodes = []

    def _text(self, msg, x, y, scale, color, align=TextNode.ACenter):
        t = OnscreenText(text=msg, pos=(x, y), scale=scale, fg=(*color, 1.0),
                         align=align, shadow=(0, 0, 0, 0.85), parent=self.aspect2d)
        self.ui_nodes.append(t)
        return t

    def _panel(self, x, y, w, h, color, alpha):
        cm = CardMaker("panel")
        cm.setFrame(x, x + w, y, y + h)
        np_ = self.aspect2d.attachNewNode(cm.generate())
        np_.setColor(*color, alpha)
        np_.setTransparency(TransparencyAttrib.MAlpha)
        self.ui_nodes.append(np_)
        return np_

    def _clear_race(self):
        for hud in self.huds:
            hud.destroy()
        self.huds = []
        for car in self.cars:
            if car.node:
                car.node.removeNode()
        self.cars, self.controllers, self.players = [], [], []
        self._remote_by_uid = {}
        for np_ in getattr(self, "checkpoint_markers", []):
            np_.removeNode()
        self.checkpoint_markers = []
        self.windshield.set_active(False)
        self._set_split_regions(False)
        self._clear_bullets()

    def _clear_bullets(self):
        for b in getattr(self, "bullets", []):
            b.destroy()
        self.bullets = []
        self._seen_shots = set()
        self._credited_kills = set()

    def _show_world(self):
        self.world.show()
        self.sky.show()
        self._set_clear_color(self._env_colors()[0])
        self._set_precip_visible(True)

    def _enter_menu(self):
        self._clear_ui()
        self._clear_race()
        self.showroom.hide()
        if self.preview_car:
            self.preview_car.removeNode()
            self.preview_car = None
        self._show_world()
        self.state = "menu"
        self.windshield.set_active(False)
        self._leave_online()
        self.chat_ui.hide()

        self._panel(-ASPECT, -1, 2 * ASPECT, 2, (0.0, 0.0, 0.04), 0.45)
        self._text("3D CAR RACING", 0, 0.72, 0.14, (1, 1, 1))
        streak = (f"  -  WIN STREAK x{self.win_streak}"
                  if self.win_streak else "")
        self._text(f"first across the line wins{streak}",
                   0, 0.58, 0.045, (0.8, 0.84, 0.92))
        self._text("1  -  SINGLE PLAYER", 0, 0.36, 0.07, (0.5, 1.0, 0.55))
        self._text("2  -  SPLIT SCREEN RACE", 0, 0.24, 0.07, (0.5, 0.8, 1.0))
        self._text("3  -  FREE PLAY", 0, 0.12, 0.07, (1.0, 0.8, 0.5))
        self._text("4  -  ONLINE MULTIPLAYER", 0, 0.00, 0.065, (0.55, 0.95, 1.0))
        self._text("5  -  GUN COMBAT", 0, -0.12, 0.065, (1.0, 0.45, 0.35))
        self.laps_text = self._text(
            f"L  -  LAPS: {self.total_laps}", 0, -0.24, 0.05, (0.95, 0.9, 0.55))
        self.opp_text = self._text(
            f"O  -  OPPONENTS: {self.opponent_count}",
            0, -0.34, 0.05, (0.95, 0.9, 0.55))
        self.police_text = self._text(
            f"P  -  FREE PLAY POLICE: {'ON' if self.police_enabled else 'OFF'}",
            0, -0.44, 0.05, (0.7, 0.85, 1.0))
        self.fpsplit_text = self._text(
            f"F  -  FREE PLAY SPLIT: {'ON' if self.freeplay_split else 'OFF'}",
            0, -0.54, 0.05, (0.7, 0.85, 1.0))
        self.quality_text = self._text(
            f"G  -  GRAPHICS: {QUALITY_PRESETS[self.quality_idx][0]}",
            0, -0.64, 0.05, (0.87, 0.63, 1.0))
        self.weather_text = self._text(
            f"T  -  WEATHER: {WEATHERS[self.weather_idx][0]}",
            0, -0.74, 0.05, (0.55, 0.85, 1.0))
        self.gun_text = self._text(
            f"U  -  GUNS: {'ON' if self.gun_enabled else 'OFF'}",
            0, -0.84, 0.05, (1.0, 0.55, 0.40))
        self._text("CTRL / FIRE to shoot in gun mode    P2: Q",
                   0, -0.93, 0.036, (0.75, 0.75, 0.8))
        self.touch.sync()

    @property
    def total_laps(self):
        return LAP_OPTIONS[self.lap_option_idx]

    @property
    def opponent_count(self):
        return OPPONENT_OPTIONS[self.opponent_option_idx]

    def _enter_car_select(self):
        self._clear_ui()
        self.state = "car_select"
        self.world.hide()
        self.sky.hide()
        self._set_precip_visible(False)
        self._set_clear_color((0.05, 0.06, 0.09))
        self.showroom.show()
        self.camera.setPos(5.4, -8.0, 2.9)
        self.camera.lookAt(0.0, 0.4, 0.85)
        self._rebuild_preview()

        who = "P1" if self.select_player == 0 else "P2"
        who_color = (1.0, 0.5, 0.5) if self.select_player == 0 else (1.0, 0.75, 0.45)
        self._text(f"{who}  -  CHOOSE YOUR CAR", 0, 0.82, 0.09, who_color)
        self.car_name_text = self._text("", 0, 0.66, 0.095, (1, 1, 1))
        self.car_tag_text = self._text("", 0, 0.56, 0.05, (0.78, 0.82, 0.9))
        self.paint_text = self._text("", 0, -0.62, 0.055, (0.92, 0.92, 0.92))
        self._text("LEFT/RIGHT car    UP/DOWN paint    ENTER confirm    ESC back",
                   0, -0.92, 0.045, (0.7, 0.72, 0.8))
        self.touch.sync()

        # Stat bars.
        self.stat_bars = []
        labels = ["SPEED", "ACCEL", "GRIP"]
        for i, label in enumerate(labels):
            y = -0.10 - i * 0.10
            self._text(label, -1.35, y, 0.05, (0.8, 0.8, 0.8), TextNode.ALeft)
            self._panel(-1.05, y - 0.005, 0.7, 0.05, (0.25, 0.25, 0.30), 0.9)
            bar = self._panel(-1.05, y - 0.005, 0.7, 0.05, (0.30, 0.75, 0.35), 1.0)
            self.stat_bars.append(bar)

        # Paint swatches.
        self.swatch_markers = []
        total = len(PAINT_COLORS) * 0.16
        self.swatch_x0 = -total / 2
        for i, (_, rgb) in enumerate(PAINT_COLORS):
            self._panel(self.swatch_x0 + i * 0.16, -0.80, 0.12, 0.12, rgb, 1.0)
        self._update_car_select_ui()

    def _rebuild_preview(self):
        if self.preview_car:
            self.preview_car.removeNode()
        sel = self.selections[self.select_player]
        model = CAR_MODELS[sel["model"]]
        self.preview_car, _, _ = self.car_assets.build(model, sel["color"])
        self.preview_car.reparentTo(self.showroom)
        self.preview_car.setPos(0, 0, 0.05)

    def _update_car_select_ui(self):
        sel = self.selections[self.select_player]
        model = CAR_MODELS[sel["model"]]
        self.car_name_text.setText(f"<   {model['name']}   >")
        self.car_tag_text.setText(model["tag"])
        self.paint_text.setText(PAINT_COLORS[sel["color"]][0])
        stats = model["stats"]
        fracs = [stats["max_speed"] / STAT_TOP["max_speed"],
                 stats["accel"] / STAT_TOP["accel"],
                 stats["steer"] / STAT_TOP["steer"]]
        for bar, frac in zip(self.stat_bars, fracs):
            bar.setScale(clamp(frac, 0.05, 1.0), 1.0, 1.0)
            # Panels scale from their left edge because the frame starts at x.
        if getattr(self, "swatch_markers", None):
            for n in self.swatch_markers:
                if n in self.ui_nodes:
                    self.ui_nodes.remove(n)
                n.removeNode()
        self.swatch_markers = []
        x = self.swatch_x0 + sel["color"] * 0.16
        y, w, h, t = -0.815, 0.15, 0.15, 0.012
        col = (1.0, 1.0, 1.0)
        self.swatch_markers = [
            self._panel(x - 0.015, y, w, t, col, 1.0),
            self._panel(x - 0.015, y + h - t, w, t, col, 1.0),
            self._panel(x - 0.015, y, t, h, col, 1.0),
            self._panel(x - 0.015 + w - t, y, t, h, col, 1.0),
        ]
        self._rebuild_preview()

    def _enter_map_select(self):
        self._clear_ui()
        self.state = "map_select"
        self.showroom.hide()
        if self.preview_car:
            self.preview_car.removeNode()
            self.preview_car = None
        self._show_world()

        self._panel(-ASPECT, 0.62, 2 * ASPECT, 0.38, (0, 0, 0.04), 0.55)
        self._panel(-ASPECT, -1.0, 2 * ASPECT, 0.32, (0, 0, 0.04), 0.55)
        self._text("CHOOSE TRACK", 0, 0.84, 0.08, (1, 1, 1))
        self.map_name_text = self._text("", 0, 0.70, 0.09, (1.0, 0.9, 0.45))
        self.map_tag_text = self._text("", 0, -0.80, 0.055, (0.82, 0.85, 0.92))
        self._text("LEFT/RIGHT browse    ENTER start race    ESC back",
                   0, -0.93, 0.045, (0.7, 0.72, 0.8))
        self._update_map_select_ui()
        self.touch.sync()

    def _update_map_select_ui(self):
        spec = MAPS[self.map_idx]
        self.map_name_text.setText(f"<   {spec['name']}   >")
        self.map_tag_text.setText(spec["tag"])

    # ---------------------------------------------------------- race set-up
    def _set_split_regions(self, split):
        if split == (self.dr2 is not None):
            return
        # The color-grade filters wrap the display regions - remove them
        # first and rebuild afterwards.
        for mgr, _quad in self.grades:
            mgr.cleanup()
        self.grades = []
        if split:
            self.main_dr.setDimensions(0, 1, 0.5, 1)
            self.camLens.setAspectRatio(WINDOW_W / (WINDOW_H / 2))
            lens = PerspectiveLens()
            lens.setFov(FOV_DEGREES)
            lens.setNearFar(1.0, 1800.0)
            lens.setAspectRatio(WINDOW_W / (WINDOW_H / 2))
            cam2 = Camera("p2cam", lens)
            cam2.setCameraMask(MASK_CAM2)
            self.cam2_np = self.render.attachNewNode(cam2)
            self.dr2 = self.win.makeDisplayRegion(0, 1, 0, 0.5)
            self.dr2.setCamera(self.cam2_np)
            self.dr2.setClearDepthActive(True)
        else:
            self.win.removeDisplayRegion(self.dr2)
            self.dr2 = None
            self.cam2_np.removeNode()
            self.cam2_np = None
            self.main_dr.setDimensions(0, 1, 0, 1)
            self.camLens.setAspectRatio(ASPECT)
        self._setup_grades()
        self._apply_weather()          # rain rigs are per-viewport

    def _spawn_police(self, target, slot):
        """Drop a police cruiser onto the track to chase `target`."""
        n = self.track.n
        idx = (n // 3 + slot * 11) % n
        wx, wy = self.track.wps[idx]
        nx, ny = self.track.normals[idx]
        car = Car(f"PURSUIT {slot + 1}", POLICE_MODEL, (0.12, 0.22, 0.55))
        car.is_police = True
        car.grip = self.weather["grip"]
        node, steer, spin = self.car_assets.build(POLICE_MODEL, 0)
        node.reparentTo(self.car_root)
        car.node, car.steer_pivots, car.spin_pivots = node, steer, spin
        side = 4.5 if slot % 2 == 0 else -4.5
        car.place(wx + nx * side, wy + ny * side, self.track.heading_at(idx), idx)
        if self.gun_enabled:
            attach_car_gun(car)
        car.sync_node()
        self.cars.append(car)
        self.controllers.append(PoliceController(target))

    def _update_bounty(self, dt):
        """NFS-style heat and bounty while evading police in city free play."""
        if not self.free_play or not self.police_enabled or not self.track.spec.get("city"):
            return
        player = self.players[0][0]
        kmh = abs(player.speed) * 3.6

        if kmh > 80:
            self.heat += dt * 0.07
        if kmh > 150:
            self.heat += dt * 0.11
        if kmh > 250:
            self.heat += dt * 0.16

        police_near = False
        police_close = False
        for car in self.cars:
            if not car.is_police:
                continue
            d = math.hypot(car.x - player.x, car.y - player.y)
            if d < 50:
                police_near = True
            if d < 20:
                police_close = True

        if police_near:
            self.heat += dt * 0.20
        if police_close:
            self.bounty += dt * 90
            self.heat += dt * 0.28

        if self.heat > 0.5:
            self.bounty += self.heat * dt * 40

        if kmh < 45 and not police_near:
            self.heat = max(0.0, self.heat - dt * 0.15)

        if self.heat > 1.0 and not police_near:
            self.chase_bonus += dt
            if self.chase_bonus > 5.0:
                self.bounty += int(self.heat * 300)
                self.heat = max(0.0, self.heat - 1.5)
                self.chase_bonus = 0.0
        else:
            self.chase_bonus = 0.0

        self.heat = clamp(self.heat, 0.0, 5.0)

        police_count = sum(1 for c in self.cars if c.is_police)
        if self.heat >= 4.0 and police_count < 5:
            self._spawn_police(player, police_count)

    def start_race(self, split, free_play=False):
        self._clear_ui()
        self._clear_race()
        self.showroom.hide()
        if self.preview_car:
            self.preview_car.removeNode()
            self.preview_car = None
        self._show_world()

        self.split = split
        self.free_play = free_play
        self.state = "race"
        self.race_time = 1.0 if free_play else -3.0
        self.finish_order = []
        self.bounty = 0.0
        self.heat = 0.0
        self.chase_bonus = 0.0
        self._cp_flash = 0.0
        self._set_split_regions(split)
        self._apply_weather()          # rebuild rain rigs per viewport
        self._build_checkpoints()

        specs = []
        spawn_ai = (not free_play) or (self.gun_enabled and not self.online)
        if spawn_ai:
            skills = [0.97, 0.94, 0.90, 0.86, 0.82][:self.opponent_count]
            for i, skill in enumerate(skills):
                specs.append((f"CPU {i + 1}", random.choice(CAR_MODELS),
                              random.randrange(len(PAINT_COLORS)),
                              AIController(skill)))

        sel = self.selections[0]
        if split:
            ctrl1 = HumanController(self, ["arrow_up"], ["arrow_down"],
                                    ["arrow_left"], ["arrow_right"],
                                    use_touch=True)
            sel2 = self.selections[1]
            ctrl2 = HumanController(self, ["w"], ["s"], ["a"], ["d"],
                                    fire=("q", "rcontrol"))
            specs.append(("P1", CAR_MODELS[sel["model"]], sel["color"], ctrl1))
            specs.append(("P2", CAR_MODELS[sel2["model"]], sel2["color"], ctrl2))
        else:
            ctrl1 = HumanController(self, ["arrow_up", "w"], ["arrow_down", "s"],
                                    ["arrow_left", "a"], ["arrow_right", "d"],
                                    use_touch=True)
            specs.append(("P1", CAR_MODELS[sel["model"]], sel["color"], ctrl1))

        grip = self.weather["grip"]
        for name, model, paint_idx, ctrl in specs:
            car = Car(name, model, PAINT_COLORS[paint_idx][1])
            car.grip = grip
            node, steer, spin = self.car_assets.build(model, paint_idx)
            node.reparentTo(self.car_root)
            car.node, car.steer_pivots, car.spin_pivots = node, steer, spin
            self.cars.append(car)
            self.controllers.append(ctrl)

        # Grid: AI front rows, players at the back.
        n = self.track.n
        for slot, car in enumerate(self.cars):
            idx = (n - 8 - slot * 4) % n
            wx, wy = self.track.wps[idx]
            nx, ny = self.track.normals[idx]
            side = 3.0 if slot % 2 == 0 else -3.0
            car.place(wx + nx * side, wy + ny * side, self.track.heading_at(idx), idx)
            car.hp = HP_MAX
            car.kills = 0
            car.killed_by = ""
            if self.gun_enabled:
                attach_car_gun(car)
            car.sync_node()

        humans = [(c, ct) for c, ct in zip(self.cars, self.controllers)
                  if isinstance(ct, HumanController)]
        if (free_play and self.police_enabled
                and self.track.spec.get("city") and humans):
            for i in range(3):
                self._spawn_police(humans[0][0], i)

        self.players = []
        self.huds = []
        mode = self.camera_mode
        if split:
            self.players.append((humans[0][0],
                                 ChaseCamera(humans[0][0], self.camera, mode)))
            self.players.append((humans[1][0],
                                 ChaseCamera(humans[1][0], self.cam2_np, mode)))
            bands = [(0.0, 1.0), (-1.0, 0.0)]
            for (car, _), (b0, b1) in zip(self.players, bands):
                hud = PlayerHUD(self, b0, b1, compact=True)
                hud.build_minimap(self.minimap_pts, self._map_point)
                hud.make_car_dots(self.cars, car)
                self.huds.append(hud)
        else:
            self.players.append((humans[0][0],
                                 ChaseCamera(humans[0][0], self.camera, mode)))
            hud = PlayerHUD(self, -1.0, 1.0)
            hud.build_minimap(self.minimap_pts, self._map_point)
            hud.make_car_dots(self.cars, humans[0][0])
            self.huds.append(hud)
        self._apply_camera_mode()
        self.touch.sync()

    def _build_checkpoints(self):
        """Place glowing checkpoint posts evenly around the circuit."""
        for np_ in getattr(self, "checkpoint_markers", []):
            np_.removeNode()
        self.checkpoint_markers = []
        self.checkpoint_indices = []
        if self.free_play:
            return
        n = self.track.n
        hw = self.track.half_width
        for i in range(CHECKPOINT_COUNT):
            idx = int((i + 0.5) * n / CHECKPOINT_COUNT) % n
            wx, wy = self.track.wps[idx]
            nx, ny = self.track.normals[idx]
            mb = MeshBuilder(f"cp-{i}")
            for side in (-1.0, 1.0):
                px = nx * side * (hw - 0.5)
                py = ny * side * (hw - 0.5)
                mb.box(px, py, 2.0, 0.4, 0.4, 4.0, (0.2, 0.95, 0.75))
            # Crossbar in the track-normal direction.
            mb.quad((-nx * (hw - 0.5), -ny * (hw - 0.5), 4.0),
                    (nx * (hw - 0.5), ny * (hw - 0.5), 4.0),
                    (nx * (hw - 0.5), ny * (hw - 0.5), 4.35),
                    (-nx * (hw - 0.5), -ny * (hw - 0.5), 4.35),
                    (0.2, 0.95, 0.75, 0.7), normal=(0, 0, 1))
            node = mb.build()
            node.reparentTo(self.render)
            node.setPos(wx, wy, 0)
            node.setTransparency(TransparencyAttrib.MAlpha)
            node.setColorScale(1, 1, 1, 0.6)
            node.setLightOff(1)
            node.setBin("transparent", 20)
            self.checkpoint_markers.append(node)
            self.checkpoint_indices.append(idx)

    def _apply_camera_mode(self):
        for car, cam in self.players:
            cam.set_mode(self.camera_mode)
            # Hide the driven car in hood view so the cabin doesn't clip.
            if car.node:
                if self.camera_mode == "HOOD":
                    car.node.hide()
                else:
                    car.node.show()
        raining = self.weather.get("precip") == "rain"
        hood = self.camera_mode == "HOOD"
        self.windshield.set_active(hood and raining and self.state == "race")
        # Re-show body when leaving hood.
        for car, _cam in self.players:
            if car.node:
                if hood:
                    car.node.hide()
                else:
                    car.node.show()

    def _cycle_camera(self):
        i = CAMERA_MODES.index(self.camera_mode)
        self.camera_mode = CAMERA_MODES[(i + 1) % len(CAMERA_MODES)]
        self._apply_camera_mode()

    def _on_mouse_fire(self, down):
        self._mouse_fire = bool(down)

    def _try_fire(self, car, networked=True, shot_id=None):
        if not self.gun_enabled or self.state != "race" or self.race_time < 0:
            return False
        if car.wreck_t > 0 or car.fire_cd > 0:
            return False
        self._shot_seq += 1
        sid = shot_id or f"{id(car) % 9999:04d}{self._shot_seq}"
        if sid in self._seen_shots:
            return False
        self._seen_shots.add(sid)
        if len(self._seen_shots) > 120:
            self._seen_shots = set(list(self._seen_shots)[-80:])
        bullet = Bullet(self.bullet_root, car, sid)
        self.bullets.append(bullet)
        car.fire_cd = GUN_COOLDOWN
        if self.gun_sfx:
            self.gun_sfx.setVolume(0.45)
            self.gun_sfx.play()
        if networked and self.online:
            try:
                local = isinstance(self.controllers[self.cars.index(car)], HumanController)
            except ValueError:
                local = False
            if local:
                self.fb.send_shot({
                    "id": sid, "uid": self.fb.uid,
                    "x": round(bullet.x, 3), "y": round(bullet.y, 3),
                    "h": round(bullet.heading, 4),
                    "ts": int(time.time() * 1000),
                })
        return True

    def _spawn_net_shots(self, snap):
        if not self.gun_enabled:
            return
        shots = snap.get("shots") or {}
        if not isinstance(shots, dict):
            return
        by_uid = {}
        for car, ctrl in zip(self.cars, self.controllers):
            if isinstance(ctrl, RemoteController):
                by_uid[ctrl.uid] = car
        for key, data in shots.items():
            if not isinstance(data, dict):
                continue
            sid = str(data.get("id") or key)
            if sid in self._seen_shots:
                continue
            uid = data.get("uid")
            owner = by_uid.get(uid)
            if owner is None:
                continue
            self._seen_shots.add(sid)
            heading = float(data.get("h") or owner.heading)
            bx = data.get("x")
            by = data.get("y")
            bullet = Bullet(
                self.bullet_root, owner, sid, heading=heading,
                x=None if bx is None else float(bx),
                y=None if by is None else float(by))
            self.bullets.append(bullet)

    def _damage_car(self, car, attacker):
        if car.wreck_t > 0:
            return
        car.hp -= GUN_DAMAGE
        car.hit_flash = 0.25
        if car.hp > 0:
            car.speed *= 0.82
            return
        car.hp = 0
        car.wreck_t = WRECK_TIME
        car.speed *= 0.15
        car.killed_by = ""
        if attacker is None or attacker is car:
            return
        a_ctrl = None
        try:
            a_ctrl = self.controllers[self.cars.index(attacker)]
        except ValueError:
            pass
        if isinstance(a_ctrl, RemoteController):
            car.killed_by = a_ctrl.uid
        elif self.online and getattr(self, "fb", None) and self.fb.uid:
            car.killed_by = self.fb.uid
        if not isinstance(a_ctrl, RemoteController):
            attacker.kills += 1
        self._kill_text = f"{attacker.display_name}  WRECKED  {car.display_name}"
        self._kill_flash = 1.6

    def _update_combat(self, dt):
        if not self.gun_enabled or self.state != "race":
            return
        if self._kill_flash > 0:
            self._kill_flash = max(0.0, self._kill_flash - dt)
        if self.race_time >= 0.0:
            for car, ctrl in zip(self.cars, self.controllers):
                if hasattr(ctrl, "wants_fire") and ctrl.wants_fire(car, self):
                    net = isinstance(ctrl, HumanController)
                    self._try_fire(car, networked=net)
        alive = []
        for bullet in self.bullets:
            if not bullet.update(dt):
                bullet.destroy()
                continue
            hit = False
            for car, ctrl in zip(self.cars, self.controllers):
                if car is bullet.owner or car.wreck_t > 0:
                    continue
                if (car.x - bullet.x) ** 2 + (car.y - bullet.y) ** 2 > 14.5:
                    continue
                hit = True
                if not isinstance(ctrl, RemoteController):
                    self._damage_car(car, bullet.owner)
                else:
                    car.hit_flash = 0.2
                break
            if hit:
                bullet.destroy()
            else:
                alive.append(bullet)
        self.bullets = alive
        for car, ctrl in zip(self.cars, self.controllers):
            if isinstance(ctrl, RemoteController):
                continue
            if car.wreck_t > 0:
                car.wreck_t -= dt
                if car.wreck_t <= 0:
                    idx = self.track.nearest_index(car.x, car.y, car.wp_idx)
                    wx, wy = self.track.wps[idx]
                    nx, ny = self.track.normals[idx]
                    car.respawn_at(wx + nx * 2.0, wy + ny * 2.0,
                                   self.track.heading_at(idx), idx)

    # ------------------------------------------------ online / firebase
    def _leave_online(self):
        self.online = False
        self.online_host = False
        self.online_intent = None
        self.chat_open = False
        self.chat_buf = ""
        self.join_buf = ""
        self._remote_by_uid = {}
        if getattr(self, "fb", None):
            self.fb.leave()

    def _enter_online(self, err=None):
        self._clear_ui()
        self._clear_race()
        self.showroom.hide()
        self._show_world()
        self.state = "online"
        self.online_intent = None
        self.chat_open = False
        cfg_ok = self.fb.configured
        self._panel(-ASPECT, -1, 2 * ASPECT, 2, (0.0, 0.0, 0.04), 0.50)
        self._text("ONLINE MULTIPLAYER", 0, 0.62, 0.10, (0.55, 0.95, 1.0))
        if err:
            self._text(str(err)[:88], 0, 0.48, 0.038, (1.0, 0.45, 0.38))
        elif cfg_ok:
            self._text("Firebase Realtime Database",
                       0, 0.46, 0.042, (0.75, 0.82, 0.9))
        if cfg_ok:
            self._text("H  -  HOST A ROOM", 0, 0.18, 0.07, (0.5, 1.0, 0.55))
            self._text("J  -  JOIN WITH A 5-DIGIT CODE", 0, 0.02, 0.07,
                       (0.5, 0.8, 1.0))
            guns = "ON" if self.gun_enabled else "OFF"
            self._text(f"Host guns follow menu U  (currently {guns})",
                       0, -0.18, 0.042, (1.0, 0.62, 0.42))
            self._text("Share the room code. Chat with ENTER in the lobby and race.",
                       0, -0.32, 0.04, (0.7, 0.74, 0.82))
        else:
            self._text("Copy firebase_config.example.json to firebase_config.json",
                       0, 0.20, 0.045, (1.0, 0.75, 0.4))
            self._text("Fill apiKey and databaseURL,",
                       0, 0.08, 0.042, (0.85, 0.85, 0.9))
            self._text("and publish firebase_rules.json on the Realtime Database.",
                       0, -0.04, 0.042, (0.85, 0.85, 0.9))
        self._text("ESC back", 0, -0.80, 0.045, (0.7, 0.72, 0.8))
        self.touch.sync()

    def _begin_host(self):
        self.online_intent = "host"
        self.pending = (False, True)
        self.select_player = 0
        self._enter_car_select()

    def _enter_online_join(self):
        self._clear_ui()
        self.state = "online_join"
        self.join_buf = ""
        self._panel(-ASPECT, -1, 2 * ASPECT, 2, (0.0, 0.0, 0.04), 0.50)
        self._text("JOIN ROOM", 0, 0.55, 0.10, (0.55, 0.95, 1.0))
        self._text("Type the 5-digit code", 0, 0.36, 0.05, (0.8, 0.84, 0.92))
        self.join_code_text = self._text("_____", 0, 0.10, 0.14, (1, 1, 1))
        self.join_err_text = self._text("", 0, -0.18, 0.045, (1.0, 0.45, 0.4))
        self._text("ENTER join    ESC back", 0, -0.80, 0.045, (0.7, 0.72, 0.8))
        self.touch.sync()

    def _refresh_join_ui(self):
        shown = (self.join_buf + "_____")[:5]
        if hasattr(self, "join_code_text") and self.join_code_text:
            self.join_code_text.setText(shown)

    def _type_char(self, char):
        self._on_keystroke(char)

    def _submit_join(self):
        code = "".join(ch for ch in self.join_buf if ch.isdigit())
        if not self.fb.connect():
            if hasattr(self, "join_err_text"):
                self.join_err_text.setText(self.fb.error or "connect failed")
            return
        if not self.fb.join_room(code):
            if hasattr(self, "join_err_text"):
                self.join_err_text.setText(self.fb.error or "join failed")
            return
        self.online_intent = "join"
        self.pending = (False, True)
        self.select_player = 0
        self._enter_car_select()

    def _host_online_room(self):
        try:
            if not self.fb.connect():
                self._enter_online(self.fb.error or "could not connect")
                return
            meta = {
                "map_idx": self.map_idx,
                "weather_idx": self.weather_idx,
                "gun_mode": bool(self.gun_enabled),
                "started": False,
            }
            code = self.fb.create_room(meta)
        except Exception as exc:
            self._enter_online(str(exc)[:88])
            return
        if not code:
            self._enter_online(self.fb.error or "could not create room")
            return
        self.online_host = True
        self._enter_online_wait()

    def _enter_online_wait(self):
        if self.online_intent == "join" and not self.fb.room:
            self._enter_online_join()
            return
        self._clear_ui()
        self._show_world()
        self.state = "online_wait"
        self.online = True
        self.chat_open = False
        snap = self.fb.snapshot()
        meta = snap.get("meta") or {}
        try:
            idx = int(meta.get("map_idx", self.map_idx)) % len(MAPS)
        except (TypeError, ValueError):
            idx = self.map_idx
        if idx != self.map_idx:
            self.build_track(idx)
        if "gun_mode" in meta:
            self.gun_enabled = bool(meta.get("gun_mode"))
        self._panel(-ASPECT, -1, 2 * ASPECT, 2, (0.0, 0.0, 0.04), 0.42)
        self._text(f"ROOM  {self.fb.room}", 0, 0.78, 0.12, (0.55, 0.95, 1.0))
        self.wait_players_text = self._text("players ...", 0, 0.58, 0.05,
                                            (0.85, 0.88, 0.95))
        self._text("GUNS ON" if self.gun_enabled else "GUNS OFF",
                   0, 0.46, 0.045, (1.0, 0.55, 0.40) if self.gun_enabled
                   else (0.7, 0.74, 0.8))
        host_hint = ("ENTER to start the session"
                     if self.fb.host else "waiting for host to start")
        self._text(host_hint, 0, -0.88, 0.042, (0.75, 0.78, 0.85))
        self._push_local_player(in_lobby=True)
        self.chat_ui.refresh(snap, False, "")
        self.touch.sync()
        if (not self.fb.host) and meta.get("started"):
            self._begin_online_race()

    def _start_online_from_lobby(self):
        self.fb.mark_started({
            "map_idx": self.map_idx,
            "weather_idx": self.weather_idx,
            "gun_mode": bool(self.gun_enabled),
            "started": True,
        })
        self._begin_online_race()

    def _begin_online_race(self):
        snap = self.fb.snapshot()
        meta = snap.get("meta") or {}
        try:
            idx = int(meta.get("map_idx", self.map_idx)) % len(MAPS)
        except (TypeError, ValueError):
            idx = self.map_idx
        try:
            widx = int(meta.get("weather_idx", self.weather_idx)) % len(WEATHERS)
        except (TypeError, ValueError):
            widx = self.weather_idx
        if idx != self.map_idx:
            self.build_track(idx)
        if widx != self.weather_idx:
            self.weather_idx = widx
        self.gun_enabled = bool(meta.get("gun_mode", self.gun_enabled))
        self.online = True
        self.police_enabled = False
        self.start_race(False, True)
        self._sync_remote_players(snap, force=True)

    def _push_local_player(self, in_lobby=False):
        if not self.fb.room:
            return
        sel = self.selections[0]
        model = CAR_MODELS[sel["model"]]
        payload = {
            "name": self.fb.display_name,
            "model": model["id"],
            "color": sel["color"],
            "x": 0.0, "y": 0.0, "h": 0.0, "s": 0.0, "steer": 0.0,
            "ts": time.time(),
            "lobby": bool(in_lobby),
        }
        if not in_lobby and self.players:
            car = self.players[0][0]
            payload.update({
                "x": round(car.x, 3), "y": round(car.y, 3),
                "h": round(car.heading, 4), "s": round(car.speed, 3),
                "steer": round(car.visual_steer, 3),
                "hp": int(car.hp),
                "kills": int(car.kills),
                "wreck": bool(car.wreck_t > 0),
                "killer": getattr(car, "killed_by", "") or "",
            })
        self.fb.display_name = model["name"].split()[0] + "-" + self.fb.uid[-3:].upper()
        payload["name"] = self.fb.display_name
        self.fb.set_player(payload)

    def _sync_remote_players(self, snap, force=False):
        if not self.online or self.state != "race":
            return
        players = snap.get("players") or {}
        seen = set()
        for uid, data in players.items():
            if uid == self.fb.uid or not isinstance(data, dict):
                continue
            seen.add(uid)
            ctrl = self._remote_by_uid.get(uid)
            if ctrl is None:
                ctrl = RemoteController(uid)
                ctrl.apply(data)
                model = model_by_id(ctrl.model_id)
                car = Car(ctrl.name, model, PAINT_COLORS[ctrl.color][1])
                car.grip = self.weather["grip"]
                node, steer, spin = self.car_assets.build(model, ctrl.color)
                node.reparentTo(self.car_root)
                car.node, car.steer_pivots, car.spin_pivots = node, steer, spin
                car.place(ctrl.tx, ctrl.ty, ctrl.th, 0)
                if self.gun_enabled:
                    attach_car_gun(car)
                car.sync_node()
                self.cars.append(car)
                self.controllers.append(ctrl)
                self._remote_by_uid[uid] = ctrl
                if self.huds:
                    self.huds[0].make_car_dots(self.cars, self.players[0][0])
            else:
                was_alive = ctrl.hp > 0
                ctrl.apply(data)
                if (was_alive and ctrl.hp <= 0 and ctrl.killer
                        and ctrl.killer == self.fb.uid and self.players):
                    token = uid
                    if token not in self._credited_kills:
                        self._credited_kills.add(token)
                        self.players[0][0].kills += 1
                        self._kill_text = (
                            f"{self.players[0][0].display_name}  WRECKED  "
                            f"{ctrl.name}")
                        self._kill_flash = 1.6
                elif ctrl.hp > 0:
                    self._credited_kills.discard(uid)
        stale = [uid for uid in self._remote_by_uid if uid not in seen]
        for uid in stale:
            ctrl = self._remote_by_uid.pop(uid)
            for i, c in enumerate(self.controllers):
                if c is ctrl:
                    car = self.cars[i]
                    if car.node:
                        car.node.removeNode()
                    del self.cars[i]
                    del self.controllers[i]
                    break
            if self.huds and self.players:
                self.huds[0].make_car_dots(self.cars, self.players[0][0])

    def _toggle_chat(self):
        if self.chat_open:
            self._close_chat()
        else:
            self.chat_open = True
            self.chat_buf = ""
            self.touch.sync()

    def _close_chat(self):
        self.chat_open = False
        self.chat_buf = ""
        self.touch.sync()

    def _send_chat(self):
        text = self.chat_buf.strip()
        self.chat_buf = ""
        self.chat_open = False
        if text:
            self.fb.send_chat(text)
        self.touch.sync()

    def _quick_chat(self, text):
        self.fb.send_chat(text)
        self.chat_open = False
        self.touch.sync()

    def _append_chat(self, char):
        """Add a character to the chat box (keyboard or on-screen keys)."""
        if not self.chat_open or not char:
            return
        if len(char) != 1 or ord(char) < 32:
            return
        if getattr(self, "_chat_dup", None) == char:
            return
        self._chat_dup = char
        if len(self.chat_buf) < 120:
            self.chat_buf += char

    def _on_keystroke(self, char):
        if self.state == "online_join" and char and char.isdigit() and len(self.join_buf) < 5:
            self.join_buf += char
            self._refresh_join_ui()
            return
        if self.chat_open:
            self._append_chat(char)

    def _on_key_down(self, key):
        if key == "shift":
            self._shift = True
            self.keys[key] = True
            return
        if self.chat_open:
            named = {"space": " ", "period": ".", "comma": ",",
                     "slash": "/", "semicolon": ";", "minus": "-",
                     "equals": "=", "quote": "'"}
            if key == "enter":
                self._send_chat()
            elif key == "escape":
                self._close_chat()
            elif key == "backspace":
                self.chat_buf = self.chat_buf[:-1]
            elif key in named:
                self._append_chat(named[key])
            elif len(key) == 1:
                ch = key.upper() if self._shift else key
                self._append_chat(ch)
            return
        self.keys[key] = True
        self._handle_key(key)

    def _on_shift_up(self):
        self._shift = False
        self.keys["shift"] = False

    def _update_online(self, dt):
        if not self.fb.room:
            return
        snap = self.fb.snapshot()
        if self.state == "online_wait":
            self._push_local_player(in_lobby=True)
            names = []
            for uid, data in (snap.get("players") or {}).items():
                if isinstance(data, dict):
                    names.append(str(data.get("name") or uid[-4:]))
            if hasattr(self, "wait_players_text") and self.wait_players_text:
                self.wait_players_text.setText(
                    "in lobby: " + (", ".join(names) if names else "..."))
            self.chat_ui.refresh(snap, self.chat_open, self.chat_buf)
            meta = snap.get("meta") or {}
            if "gun_mode" in meta:
                self.gun_enabled = bool(meta.get("gun_mode"))
            if (not self.fb.host) and meta.get("started"):
                self._begin_online_race()
            return
        if self.state == "race" and self.online:
            self._push_local_player(in_lobby=False)
            self._sync_remote_players(snap)
            self._spawn_net_shots(snap)
            self.chat_ui.refresh(snap, self.chat_open, self.chat_buf)

    # --------------------------------------------------------------- input
    def _handle_key(self, key):
        if self.state == "menu":
            if key == "1":
                self.pending = (False, False)
                self.select_player = 0
                self._enter_car_select()
            elif key == "2":
                self.pending = (True, False)
                self.select_player = 0
                self._enter_car_select()
            elif key == "3":
                self.pending = (self.freeplay_split, True)
                self.select_player = 0
                self._enter_car_select()
            elif key == "g":
                self.quality_idx = (self.quality_idx + 1) % len(QUALITY_PRESETS)
                self._apply_quality()
                self.build_track(self.map_idx)
                self.quality_text.setText(
                    f"G  -  GRAPHICS: {QUALITY_PRESETS[self.quality_idx][0]}")
            elif key == "t":
                self.weather_idx = (self.weather_idx + 1) % len(WEATHERS)
                self._apply_weather()
                self.weather_text.setText(
                    f"T  -  WEATHER: {WEATHERS[self.weather_idx][0]}")
            elif key == "l":
                self.lap_option_idx = (self.lap_option_idx + 1) % len(LAP_OPTIONS)
                self.laps_text.setText(f"L  -  LAPS: {self.total_laps}")
            elif key == "o":
                self.opponent_option_idx = (
                    (self.opponent_option_idx + 1) % len(OPPONENT_OPTIONS))
                self.opp_text.setText(
                    f"O  -  OPPONENTS: {self.opponent_count}")
            elif key == "p":
                self.police_enabled = not self.police_enabled
                self.police_text.setText(
                    f"P  -  FREE PLAY POLICE: "
                    f"{'ON' if self.police_enabled else 'OFF'}")
            elif key == "f":
                self.freeplay_split = not self.freeplay_split
                self.fpsplit_text.setText(
                    f"F  -  FREE PLAY SPLIT: "
                    f"{'ON' if self.freeplay_split else 'OFF'}")
            elif key == "4" or key == "m":
                self._enter_online()
            elif key == "5":
                self.gun_enabled = True
                self.pending = (False, True)
                self.select_player = 0
                self._enter_car_select()
            elif key == "u":
                self.gun_enabled = not self.gun_enabled
                if hasattr(self, "gun_text") and self.gun_text:
                    self.gun_text.setText(
                        f"U  -  GUNS: {'ON' if self.gun_enabled else 'OFF'}")
                self.touch.sync()
            elif key == "escape":
                sys.exit(0)

        elif self.state == "online":
            if key in ("h", "1", "enter"):
                self._begin_host()
            elif key in ("j", "2"):
                self._enter_online_join()
            elif key == "escape":
                self._enter_menu()

        elif self.state == "online_join":
            if key == "enter":
                self._submit_join()
            elif key == "backspace":
                self.join_buf = self.join_buf[:-1]
                self._refresh_join_ui()
            elif key == "escape":
                self._enter_online()

        elif self.state == "online_wait":
            if key == "enter" and self.fb.host:
                self._start_online_from_lobby()
            elif key == "space":
                self._toggle_chat()
            elif key == "escape":
                self._enter_menu()

        elif self.state == "car_select":
            sel = self.selections[self.select_player]
            if key == "arrow_left":
                sel["model"] = (sel["model"] - 1) % len(CAR_MODELS)
                self._update_car_select_ui()
            elif key == "arrow_right":
                sel["model"] = (sel["model"] + 1) % len(CAR_MODELS)
                self._update_car_select_ui()
            elif key == "arrow_up":
                sel["color"] = (sel["color"] - 1) % len(PAINT_COLORS)
                self._update_car_select_ui()
            elif key == "arrow_down":
                sel["color"] = (sel["color"] + 1) % len(PAINT_COLORS)
                self._update_car_select_ui()
            elif key in ("enter", "space"):
                if self.pending[0] and self.select_player == 0:
                    self.select_player = 1
                    self._enter_car_select()
                elif getattr(self, "online_intent", None) == "join":
                    self._enter_online_wait()
                else:
                    self._enter_map_select()
            elif key == "escape":
                if self.select_player == 1:
                    self.select_player = 0
                    self._enter_car_select()
                else:
                    self._enter_menu()

        elif self.state == "map_select":
            if key == "arrow_left":
                self.build_track((self.map_idx - 1) % len(MAPS))
                self._update_map_select_ui()
            elif key == "arrow_right":
                self.build_track((self.map_idx + 1) % len(MAPS))
                self._update_map_select_ui()
            elif key in ("enter", "space"):
                if getattr(self, "online_intent", None) == "host":
                    self._host_online_room()
                else:
                    self.start_race(*self.pending)
            elif key == "escape":
                self.select_player = 1 if self.pending[0] else 0
                self._enter_car_select()

        elif self.state == "race":
            if key == "escape":
                self._enter_menu()
            elif key == "enter" and self.online:
                self._toggle_chat()
            elif key == "r" and not self.online:
                self.start_race(self.split, self.free_play)
            elif key == "c":
                self._cycle_camera()
            elif key in ("control", "lcontrol", "rcontrol") and self.gun_enabled:
                pass

    # ---------------------------------------------------------- simulation
    def _update(self, task):
        dt = min(ClockObject.getGlobalClock().getDt(), 0.05)
        self._chat_dup = None
        self.touch.poll()
        if self.online or self.state in ("online_wait",):
            self._update_online(dt)

        if self.state == "race":
            self._update_race(dt)
        else:
            self.menu_time += dt
            if self.state in ("menu", "map_select", "online", "online_join",
                              "online_wait"):
                self._orbit_camera()
            elif self.state == "car_select" and self.preview_car:
                self.preview_car.setH(self.menu_time * 40.0)
        self._update_weather_fx(dt)
        raining = self.weather.get("precip") == "rain"
        self.windshield.update(dt, raining and self.camera_mode == "HOOD"
                               and self.state == "race")
        return task.cont

    def _orbit_camera(self):
        a = self.menu_time * 0.15
        x0, x1, y0, y1 = self.track.bounds
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        r = max(x1 - x0, y1 - y0) * 0.85
        self.camera.setPos(cx + math.sin(a) * r, cy + math.cos(a) * r, r * 0.45)
        self.camera.lookAt(cx, cy, 0)

    def _crossed_checkpoint(self, old_idx, new_idx, cp_idx):
        """True if the car advanced past checkpoint waypoint cp_idx."""
        n = self.track.n
        if old_idx == new_idx:
            return False
        # Forward progress wrapping around the loop.
        if old_idx < new_idx:
            return old_idx < cp_idx <= new_idx
        return old_idx < cp_idx or cp_idx <= new_idx

    def _update_checkpoints(self, car, old_idx, new_idx):
        if self.free_play or not self.checkpoint_indices:
            return
        target = car.checkpoint % CHECKPOINT_COUNT
        cp_wp = self.checkpoint_indices[target]
        if self._crossed_checkpoint(old_idx, new_idx, cp_wp):
            car.checkpoints_hit = min(CHECKPOINT_COUNT, car.checkpoints_hit + 1)
            car.checkpoint = (car.checkpoint + 1) % CHECKPOINT_COUNT
            if car is self.players[0][0]:
                self._cp_flash = 0.9
                # Pulse the matching gate.
                if target < len(self.checkpoint_markers):
                    self.checkpoint_markers[target].setColorScale(1.2, 1.4, 1.0, 0.95)

    def _update_race(self, dt):
        self.race_time += dt
        green = self.race_time >= 0.0
        if self._cp_flash > 0:
            self._cp_flash = max(0.0, self._cp_flash - dt)

        for car, ctrl in zip(self.cars, self.controllers):
            if isinstance(ctrl, RemoteController):
                ctrl.blend(car, dt)
                continue
            throttle, steer = ctrl.control(car, self.track) if green else (0.0, 0.0)
            car.update(dt, throttle, steer)

        self._resolve_car_collisions()
        if self.gun_enabled:
            self._update_combat(dt)

        n = self.track.n
        for car, ctrl in zip(self.cars, self.controllers):
            old_idx = car.wp_idx
            new_idx = self.track.nearest_index(car.x, car.y, car.wp_idx)
            if not isinstance(ctrl, RemoteController):
                self._update_checkpoints(car, old_idx, new_idx)
            if car.wp_idx > n * 0.8 and new_idx < n * 0.2:
                # Require all checkpoints before the lap counts (races only).
                if self.free_play or car.checkpoints_hit >= CHECKPOINT_COUNT:
                    car.lap += 1
                    car.checkpoints_hit = 0
                    car.checkpoint = 0
                    if (not self.free_play and car.lap > self.total_laps
                            and car not in self.finish_order):
                        self.finish_order.append(car)
                        self._on_finish(car)
            elif new_idx > n * 0.8 and car.wp_idx < n * 0.2:
                car.lap -= 1
            car.wp_idx = new_idx
            if not isinstance(ctrl, RemoteController):
                self.track.clamp_to_walls(car)
            car.sync_node()

        racers = [c for c in self.cars if not c.is_police]
        order = sorted(racers, key=lambda c: -(c.lap * n + c.wp_idx))
        for pos, car in enumerate(order):
            car.race_pos = pos + 1

        for (car, cam), hud in zip(self.players, self.huds):
            cam.update(dt)
            hud.update(car, self)

        if self.free_play:
            self._update_bounty(dt)

        # Keep the shadow camera centered on player 1 for crisp shadows.
        p1 = self.players[0][0]
        self.sun_np.setPos(p1.x, p1.y, 0)

    def _on_finish(self, car):
        """Update win streak when someone finishes a race."""
        humans = {c for c, ct in zip(self.cars, self.controllers)
                  if isinstance(ct, HumanController)}
        # First finisher decides the streak for this race.
        if len(self.finish_order) != 1:
            return
        if car in humans:
            self.win_streak += 1
        else:
            self.win_streak = 0

    def _resolve_car_collisions(self):
        radius = 2.5
        for i in range(len(self.cars)):
            for j in range(i + 1, len(self.cars)):
                a, b = self.cars[i], self.cars[j]
                if (isinstance(self.controllers[i], RemoteController)
                        or isinstance(self.controllers[j], RemoteController)):
                    continue
                dx, dy = b.x - a.x, b.y - a.y
                d2 = dx * dx + dy * dy
                if d2 < radius * radius and d2 > 1e-9:
                    d = math.sqrt(d2)
                    push = (radius - d) / 2.0
                    ux, uy = dx / d, dy / d
                    a.x -= ux * push; a.y -= uy * push
                    b.x += ux * push; b.y += uy * push
                    a.speed *= 0.97
                    b.speed *= 0.97


if __name__ == "__main__":
    RacingGame().run()
