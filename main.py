"""
True 3D Car Driving Simulator
=============================
Tech stack:
    - Pygame   : window creation, input events, main-loop timing.
    - PyOpenGL : all 3D rendering (fixed-function pipeline for simplicity).

No external assets are required — every shape is built from OpenGL
primitives (GL_QUADS / GL_LINES) and colored with plain RGB values.

Controls:
    UP / DOWN    : accelerate / brake & reverse
    LEFT / RIGHT : steer
    ESC          : quit

-------------------------------------------------------------------------
A quick primer on the two OpenGL matrices used here
-------------------------------------------------------------------------
OpenGL (fixed-function) transforms every vertex through two matrix stacks:

1.  PROJECTION matrix
    Describes *the lens of the camera*: how 3D view-space coordinates are
    squashed into the 2D screen. We build it once (and on resize) with
    gluPerspective(fov, aspect, near, far), which creates a perspective
    frustum — distant objects appear smaller, giving the sense of depth.

2.  MODELVIEW matrix
    A single matrix that combines:
      - VIEW  : where the camera is and what it looks at (gluLookAt).
      - MODEL : where each object sits in the world (glTranslate/glRotate).
    Every frame we reset it (glLoadIdentity), apply the camera transform
    first, then push/pop object transforms around each draw call so that
    objects don't inherit each other's positions.

The rendering loop each frame is therefore:
    clear buffers -> set MODELVIEW = camera -> draw world -> draw car
    -> swap the double buffer so the finished image appears at once.
-------------------------------------------------------------------------
"""

import math
import random
import sys

import pygame
from OpenGL.GL import *
from OpenGL.GLU import *

# ------------------------------------------------------------------ config
WINDOW_SIZE = (1280, 720)
FOV_DEGREES = 70.0        # vertical field of view of the camera "lens"
NEAR_PLANE = 0.1          # anything closer than this is clipped
FAR_PLANE = 500.0         # anything farther than this is clipped
FPS = 60

GRID_SPACING = 4.0        # distance between ground grid lines
GRID_HALF_LINES = 40      # grid extends this many lines in each direction
NUM_OBSTACLES = 40        # random cubes scattered around the world
WORLD_SPREAD = 180.0      # obstacles spawn within +/- this range


# ---------------------------------------------------------------- utilities
def lerp(a: float, b: float, t: float) -> float:
    """Linear interpolation — used for smooth camera motion."""
    return a + (b - a) * t


def draw_box(width: float, height: float, length: float, color):
    """
    Draw an axis-aligned rectangular prism centered on the local origin.

    Each face gets a slightly different brightness of the base color.
    This fakes directional lighting without enabling GL_LIGHTING, so the
    box still reads as a 3D object instead of a flat silhouette.

    The box is drawn in *model space*; the caller positions it in the
    world by manipulating the MODELVIEW matrix (glTranslate / glRotate)
    before calling this function.
    """
    r, g, b = color
    hw, hh, hl = width / 2.0, height / 2.0, length / 2.0

    # (brightness, 4 corner vertices) per face
    faces = [
        # top (brightest — pretends the light comes from above)
        (1.00, [(-hw, hh, -hl), (hw, hh, -hl), (hw, hh, hl), (-hw, hh, hl)]),
        # front / back (+Z / -Z)
        (0.80, [(-hw, -hh, hl), (hw, -hh, hl), (hw, hh, hl), (-hw, hh, hl)]),
        (0.60, [(-hw, -hh, -hl), (-hw, hh, -hl), (hw, hh, -hl), (hw, -hh, -hl)]),
        # left / right (-X / +X)
        (0.70, [(-hw, -hh, -hl), (-hw, -hh, hl), (-hw, hh, hl), (-hw, hh, -hl)]),
        (0.70, [(hw, -hh, -hl), (hw, hh, -hl), (hw, hh, hl), (hw, -hh, hl)]),
        # bottom (darkest)
        (0.35, [(-hw, -hh, -hl), (hw, -hh, -hl), (hw, -hh, hl), (-hw, -hh, hl)]),
    ]

    glBegin(GL_QUADS)
    for brightness, verts in faces:
        glColor3f(r * brightness, g * brightness, b * brightness)
        for v in verts:
            glVertex3f(*v)
    glEnd()

    # Dark outline so edges stay crisp against similar colors.
    glColor3f(0.05, 0.05, 0.05)
    glLineWidth(1.5)
    edges = [
        ((-hw, -hh, -hl), (hw, -hh, -hl)), ((hw, -hh, -hl), (hw, -hh, hl)),
        ((hw, -hh, hl), (-hw, -hh, hl)), ((-hw, -hh, hl), (-hw, -hh, -hl)),
        ((-hw, hh, -hl), (hw, hh, -hl)), ((hw, hh, -hl), (hw, hh, hl)),
        ((hw, hh, hl), (-hw, hh, hl)), ((-hw, hh, hl), (-hw, hh, -hl)),
        ((-hw, -hh, -hl), (-hw, hh, -hl)), ((hw, -hh, -hl), (hw, hh, -hl)),
        ((hw, -hh, hl), (hw, hh, hl)), ((-hw, -hh, hl), (-hw, hh, hl)),
    ]
    glBegin(GL_LINES)
    for a, b_ in edges:
        glVertex3f(*a)
        glVertex3f(*b_)
    glEnd()


# --------------------------------------------------------------------- car
class Car:
    """
    The player's vehicle: a rectangular prism plus simple arcade physics.

    State:
        x, z     : position on the ground plane (y is always 0 / on ground)
        heading  : direction the car faces, in radians (0 = facing -Z)
        speed    : signed scalar velocity along the heading
                   (positive = forward, negative = reversing)
    """

    # --- physics tuning constants (units are "world units" and seconds)
    ACCELERATION = 18.0       # forward thrust
    BRAKE_POWER = 28.0        # deceleration when pressing DOWN while moving
    REVERSE_ACCEL = 10.0      # thrust when reversing
    MAX_SPEED = 45.0
    MAX_REVERSE_SPEED = -12.0
    FRICTION = 0.995          # per-frame rolling resistance (velocity decay)
    DRAG = 0.0008             # aerodynamic drag, scales with speed^2
    STEER_RATE = 2.2          # base steering responsiveness (rad/sec)

    # --- body dimensions
    WIDTH, HEIGHT, LENGTH = 2.0, 1.0, 4.0

    def __init__(self):
        self.x = 0.0
        self.z = 0.0
        self.heading = 0.0
        self.speed = 0.0

    # -------------------------------------------------- physics update
    def update(self, dt: float, keys):
        """Advance the car state by dt seconds based on held keys."""

        # --- longitudinal forces (accelerate / brake / reverse) ---
        if keys[pygame.K_UP]:
            self.speed += self.ACCELERATION * dt
        elif keys[pygame.K_DOWN]:
            if self.speed > 0.5:
                # Moving forward: DOWN acts as a brake.
                self.speed -= self.BRAKE_POWER * dt
            else:
                # (Nearly) stopped: DOWN engages reverse.
                self.speed -= self.REVERSE_ACCEL * dt

        # --- passive slowdown: rolling friction + quadratic drag ---
        self.speed *= self.FRICTION
        self.speed -= self.DRAG * self.speed * abs(self.speed)
        if abs(self.speed) < 0.02 and not (keys[pygame.K_UP] or keys[pygame.K_DOWN]):
            self.speed = 0.0  # snap to rest so the car doesn't creep forever

        # --- clamp to top speeds ---
        self.speed = max(self.MAX_REVERSE_SPEED, min(self.MAX_SPEED, self.speed))

        # --- steering: turning radius depends on current speed ---
        # A real car can't rotate in place; the yaw rate grows with speed
        # at low speed and tapers off at high speed (larger turning radius).
        # The factor below peaks around mid speed for a stable feel.
        steer_input = 0.0
        if keys[pygame.K_LEFT]:
            steer_input += 1.0
        if keys[pygame.K_RIGHT]:
            steer_input -= 1.0

        if steer_input != 0.0 and abs(self.speed) > 0.1:
            speed_ratio = min(abs(self.speed) / self.MAX_SPEED, 1.0)
            # Rises quickly from 0, then eases off toward high speed:
            turn_effect = math.sin(min(speed_ratio * 2.0, 1.0) * math.pi / 2.0)
            turn_effect *= (1.0 - 0.4 * speed_ratio)  # tighter radius at speed
            # Reversing flips the steering direction, like a real car.
            direction = 1.0 if self.speed >= 0.0 else -1.0
            self.heading += steer_input * self.STEER_RATE * turn_effect * direction * dt

        # --- integrate position along the heading ---
        # heading 0 points down -Z (into the screen in OpenGL's convention).
        # Rotating (0, 0, -1) around Y by `heading` gives the forward
        # vector (-sin h, 0, -cos h).
        self.x += -math.sin(self.heading) * self.speed * dt
        self.z += -math.cos(self.heading) * self.speed * dt

    # ------------------------------------------------------- rendering
    def draw(self):
        """
        Draw the car body + a small cabin.

        glPushMatrix/glPopMatrix sandwich the transforms so that the
        car's translation/rotation do not leak into whatever is drawn
        next — we temporarily append to the MODELVIEW matrix, draw,
        then restore it.
        """
        glPushMatrix()
        # MODEL part of MODELVIEW: place the car in the world...
        glTranslatef(self.x, self.HEIGHT / 2.0, self.z)
        # ...and rotate it around the vertical (Y) axis to face `heading`.
        glRotatef(math.degrees(self.heading), 0.0, 1.0, 0.0)

        # Main chassis (red).
        draw_box(self.WIDTH, self.HEIGHT, self.LENGTH, (0.85, 0.10, 0.10))

        # Cabin: a smaller dark box on top, slightly toward the rear.
        glPushMatrix()
        glTranslatef(0.0, self.HEIGHT * 0.75, self.LENGTH * 0.08)
        draw_box(self.WIDTH * 0.8, self.HEIGHT * 0.6, self.LENGTH * 0.45,
                 (0.15, 0.15, 0.20))
        glPopMatrix()

        glPopMatrix()


# ------------------------------------------------------------------ camera
class ChaseCamera:
    """
    Third-person chase camera.

    Every frame it computes a *desired* position: a point behind and above
    the car along the car's heading. Instead of jumping there instantly it
    lerps (exponentially smooths) toward it, which gives the camera a
    pleasant lag when the car turns or accelerates.
    """

    DISTANCE = 12.0    # how far behind the car
    HEIGHT = 5.0       # how far above the ground
    STIFFNESS = 4.0    # higher = snappier follow, lower = floatier

    def __init__(self, car: Car):
        self.car = car
        # Start already behind the car so the first frame isn't a jump cut.
        self.x = car.x + math.sin(car.heading) * self.DISTANCE
        self.y = self.HEIGHT
        self.z = car.z + math.cos(car.heading) * self.DISTANCE

    def update(self, dt: float):
        # Desired spot: DISTANCE units behind the car's current heading.
        target_x = self.car.x + math.sin(self.car.heading) * self.DISTANCE
        target_z = self.car.z + math.cos(self.car.heading) * self.DISTANCE

        # Frame-rate independent exponential smoothing.
        t = 1.0 - math.exp(-self.STIFFNESS * dt)
        self.x = lerp(self.x, target_x, t)
        self.z = lerp(self.z, target_z, t)
        self.y = lerp(self.y, self.HEIGHT, t)

    def apply_view(self):
        """
        Write the VIEW part of the MODELVIEW matrix.

        gluLookAt(eye, center, up) builds a matrix that moves the whole
        world so the camera sits at the origin looking down -Z (OpenGL's
        canonical view direction). It must be applied *before* any model
        transforms each frame.
        """
        gluLookAt(
            self.x, self.y, self.z,                      # eye: camera position
            self.car.x, 1.0, self.car.z,                 # center: look at the car
            0.0, 1.0, 0.0,                               # up: world +Y
        )


# ------------------------------------------------------------------- world
class World:
    """The ground grid and the scattered obstacle cubes."""

    def __init__(self):
        rng = random.Random(42)  # fixed seed -> same world every run
        self.obstacles = []
        for _ in range(NUM_OBSTACLES):
            x = rng.uniform(-WORLD_SPREAD, WORLD_SPREAD)
            z = rng.uniform(-WORLD_SPREAD, WORLD_SPREAD)
            if abs(x) < 10 and abs(z) < 10:
                continue  # keep the spawn area clear
            size = rng.uniform(1.5, 5.0)
            color = (rng.uniform(0.2, 0.9),
                     rng.uniform(0.2, 0.9),
                     rng.uniform(0.2, 0.9))
            self.obstacles.append((x, z, size, color))

    def draw(self, focus_x: float, focus_z: float):
        self._draw_ground(focus_x, focus_z)
        self._draw_grid(focus_x, focus_z)
        self._draw_obstacles()

    # ------------------------------------------------------------------
    def _draw_ground(self, fx: float, fz: float):
        """A huge dark quad under the grid so the 'floor' looks solid."""
        extent = GRID_HALF_LINES * GRID_SPACING
        glColor3f(0.13, 0.15, 0.13)
        glBegin(GL_QUADS)
        # Slightly below y=0 to avoid z-fighting with the grid lines.
        glVertex3f(fx - extent, -0.02, fz - extent)
        glVertex3f(fx + extent, -0.02, fz - extent)
        glVertex3f(fx + extent, -0.02, fz + extent)
        glVertex3f(fx - extent, -0.02, fz + extent)
        glEnd()

    def _draw_grid(self, fx: float, fz: float):
        """
        'Infinite' grid trick: only draw grid lines in a window around the
        camera focus, but snap that window to GRID_SPACING. Because the
        lines always land on the same world coordinates, the grid appears
        endless and stationary as the car drives across it.
        """
        base_x = math.floor(fx / GRID_SPACING) * GRID_SPACING
        base_z = math.floor(fz / GRID_SPACING) * GRID_SPACING
        extent = GRID_HALF_LINES * GRID_SPACING

        glColor3f(0.30, 0.42, 0.30)
        glLineWidth(1.0)
        glBegin(GL_LINES)
        for i in range(-GRID_HALF_LINES, GRID_HALF_LINES + 1):
            offset = i * GRID_SPACING
            # Lines parallel to Z.
            glVertex3f(base_x + offset, 0.0, base_z - extent)
            glVertex3f(base_x + offset, 0.0, base_z + extent)
            # Lines parallel to X.
            glVertex3f(base_x - extent, 0.0, base_z + offset)
            glVertex3f(base_x + extent, 0.0, base_z + offset)
        glEnd()

    def _draw_obstacles(self):
        for x, z, size, color in self.obstacles:
            glPushMatrix()
            glTranslatef(x, size / 2.0, z)  # sit the cube on the ground
            draw_box(size, size, size, color)
            glPopMatrix()


# -------------------------------------------------------------------- game
class Game:
    """Owns the window, the OpenGL state, and the main loop."""

    def __init__(self):
        pygame.init()
        pygame.display.set_caption("3D Car Driving Simulator — arrows to drive, ESC to quit")
        # DOUBLEBUF: render to a hidden buffer, then flip — no flicker.
        # OPENGL:    hand the drawing surface over to the GL driver.
        pygame.display.set_mode(WINDOW_SIZE, pygame.DOUBLEBUF | pygame.OPENGL)

        self._setup_opengl()

        self.car = Car()
        self.camera = ChaseCamera(self.car)
        self.world = World()
        self.clock = pygame.time.Clock()

    # ------------------------------------------------------------------
    def _setup_opengl(self):
        """One-time GL state + the PROJECTION matrix."""
        glEnable(GL_DEPTH_TEST)          # correct occlusion of 3D faces
        glDepthFunc(GL_LEQUAL)
        glClearColor(0.45, 0.65, 0.90, 1.0)  # sky blue background

        # Simple distance fog softens the horizon and sells the depth.
        glEnable(GL_FOG)
        glFogi(GL_FOG_MODE, GL_LINEAR)
        glFogfv(GL_FOG_COLOR, (0.45, 0.65, 0.90, 1.0))  # match the sky
        glFogf(GL_FOG_START, 60.0)
        glFogf(GL_FOG_END, 160.0)

        # ---- PROJECTION matrix ------------------------------------
        # Switch the matrix stack to PROJECTION, reset it, then build a
        # perspective frustum. This matrix rarely changes (only on window
        # resize), so we set it once here instead of every frame.
        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        aspect = WINDOW_SIZE[0] / WINDOW_SIZE[1]
        gluPerspective(FOV_DEGREES, aspect, NEAR_PLANE, FAR_PLANE)

        # Switch back to MODELVIEW — the stack the render loop works in.
        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()

    # ------------------------------------------------------------------
    def run(self):
        running = True
        while running:
            # dt in seconds; clock.tick caps the loop at FPS and returns
            # the milliseconds elapsed since the previous frame.
            dt = self.clock.tick(FPS) / 1000.0
            dt = min(dt, 0.05)  # clamp huge hitches so physics stays stable

            # ---- input / events ------------------------------------
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    running = False

            keys = pygame.key.get_pressed()

            # ---- simulation ----------------------------------------
            self.car.update(dt, keys)
            self.camera.update(dt)

            # ---- rendering ------------------------------------------
            self._render()
            pygame.display.set_caption(
                f"3D Car Simulator — {abs(self.car.speed) * 3.6:.0f} km/h — ESC to quit"
            )

        pygame.quit()
        sys.exit()

    # ------------------------------------------------------------------
    def _render(self):
        """
        One frame of the rendering loop:

        1. Clear the color buffer (last frame's pixels) and the depth
           buffer (last frame's per-pixel distances used by GL_DEPTH_TEST).
        2. Reset MODELVIEW and load the camera (VIEW) transform.
        3. Draw every object; each one push/pops its own MODEL transform.
        4. Flip the double buffer to present the finished image.
        """
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()          # start from a clean matrix every frame
        self.camera.apply_view()  # VIEW: world -> camera space

        self.world.draw(self.car.x, self.car.z)  # ground, grid, cubes
        self.car.draw()                          # the player

        pygame.display.flip()     # swap hidden buffer to the screen


if __name__ == "__main__":
    Game().run()
