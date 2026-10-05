# car-sim-3d

Arcade circuit racer in **Godot 4.6**. Kenney car models, walled tracks, weather, gun combat, and Firebase / LAN multiplayer.

The original **Panda3D** Python game is still in `main.py`. `main_classic.py` is the older Pygame + PyOpenGL renderer.

## Play (Godot)

Open `project.godot` in Godot 4.6, or run the Windows export:

`dist/CarSim3D.exe` (built locally; not committed)

### Menu

1. Single player  
2. Split screen (P1 arrows, P2 WASD)  
3. Free play  
4. Online (Firebase rooms)  
5. Gun combat  
6. Roam  

L laps · O opponents · T weather · G graphics · U guns

## Maps

Meadow Circuit, Sunset Speedway, Alpine Run, Rockport City, Harbor District, Canyon Pass, Midnight Metro, Palm Coast, Foundry Loop, Volcano Ridge, Salt Flats, **Switchback Ridge**, **Lagoon Straits**.

## Setup

- Godot 4.6 + Windows export templates
- Copy `firebase_config.example.json` to `firebase_config.json` for online play (do not commit secrets)

Cars and scenery: CC0 [Kenney Car Kit](https://kenney.nl/assets/car-kit) and Kenney city / nature packs.
