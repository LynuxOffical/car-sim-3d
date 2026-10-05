"""Offscreen smoke test for cameras, options, checkpoints, free-play toggles."""
import os
import sys

os.environ["CARSIM_OFFSCREEN"] = "1"
os.makedirs("shots", exist_ok=True)

from main import (RacingGame, AIController, CAMERA_MODES, CHECKPOINT_COUNT,
                  MAPS, WEATHERS)

game = RacingGame()


def frames(n):
    for _ in range(n):
        game.taskMgr.step()


def shot(name):
    game.win.saveScreenshot(f"shots/{name}.png")
    print("shot", name)


assert game.state == "menu"
# Cycle options
game._handle_key("l")  # 1 -> wait, default is 3, so first L -> 5
assert game.total_laps == 5
game._handle_key("o")  # 3 -> 4
game._handle_key("p")
assert game.police_enabled is False
game._handle_key("p")
assert game.police_enabled is True
game._handle_key("f")
assert game.freeplay_split is True
game._handle_key("f")
assert game.freeplay_split is False
frames(20)
shot("menu_options")

# Single player race with checkpoints
game.lap_option_idx = 0  # 1 lap
game.opponent_option_idx = 0  # 1 opponent
game._handle_key("1")
game._handle_key("enter")
game._handle_key("enter")
assert game.state == "race"
assert len(game.checkpoint_markers) == CHECKPOINT_COUNT
assert sum(1 for c in game.cars if not c.is_police) == 2
game.controllers[-1] = AIController(0.95)
frames(200)
# Cycle cameras
game._handle_key("c")
assert game.camera_mode == "HOOD"
frames(30)
shot("cam_hood")
game._handle_key("c")
assert game.camera_mode == "TOP"
frames(30)
shot("cam_top")
game._handle_key("c")
assert game.camera_mode == "CHASE"

# Rain + hood windshield droplets
game._handle_key("escape")
assert game.state == "menu"
# set rain weather
while WEATHERS[game.weather_idx][0] != "RAIN":
    game._handle_key("t")
game._handle_key("1")
game._handle_key("enter")
game._handle_key("enter")
game.controllers[-1] = AIController(0.9)
game._handle_key("c")  # HOOD
assert game.camera_mode == "HOOD"
assert game.windshield.active
frames(90)
shot("hood_rain_drops")
assert len(game.windshield.drops) > 0

# City free play with police
game._handle_key("escape")
while WEATHERS[game.weather_idx][0] != "CLEAR":
    game._handle_key("t")
city_idx = next(i for i, m in enumerate(MAPS) if m.get("city"))
game.police_enabled = True
game.freeplay_split = False
game._handle_key("3")
game._handle_key("enter")
while game.map_idx != city_idx:
    game._handle_key("arrow_right")
game._handle_key("enter")
assert game.free_play
assert sum(1 for c in game.cars if c.is_police) == 3
frames(120)
shot("freeplay_police")

# Free play split without police
game._handle_key("escape")
game.police_enabled = False
game.freeplay_split = True
game._handle_key("3")
assert game.select_player == 0
game._handle_key("enter")  # P1
assert game.select_player == 1
game._handle_key("enter")  # P2
game._handle_key("enter")  # map
assert game.split and game.free_play
assert sum(1 for c in game.cars if c.is_police) == 0
assert len(game.players) == 2
frames(60)
shot("freeplay_split")

# Checkpoint progress
game._handle_key("escape")
game.lap_option_idx = 0
game.opponent_option_idx = 0
game._handle_key("1")
game._handle_key("enter")
game._handle_key("enter")
p1 = game.cars[-1]
game.controllers[-1] = AIController(1.0)
# Drive enough to hit at least one checkpoint
for _ in range(900):
    game.taskMgr.step()
    if p1.checkpoints_hit >= 1:
        break
assert p1.checkpoints_hit >= 1, f"cp hits={p1.checkpoints_hit}"
shot("checkpoint_progress")

print("ALL FEATURE TESTS PASSED")
sys.exit(0)
