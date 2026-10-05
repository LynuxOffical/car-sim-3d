"""Panda3D 1.11 Android packaging. Host: Python 3.13 + panda3d>=1.11.

    python setup.py bdist_apps --requirements-path requirements-android.txt

Produces dist/CarSim3D-1.0.0_android.aab (Play Store). Convert to a
sideloadable APK with build_apk.py / bundletool --mode universal.
"""
from setuptools import setup

PRC_DATA = """
load-display pandagles2
aux-display pandagles
audio-library-name p3openal_audio
framebuffer-multisample 0
textures-power-2 none
sync-video true
window-title 3D Car Racing Simulator
notify-level warning
"""

setup(
    name="CarSim3D",
    version="1.0.0",
    options={
        "build_apps": {
            "application_id": "com.carsim3d.game",
            "android_version_code": 1,
            "platforms": ["android"],
            "android_abis": ["arm64-v8a", "armeabi-v7a"],
            "gui_apps": {
                "CarSim3D": "main.py",
            },
            "plugins": [
                "pandagles2",
                "pandagles",
                "p3openal_audio",
            ],
            "include_patterns": [
                "assets/**/*.glb",
                "assets/**/*.png",
                "assets/**/*.txt",
                "assets/icon.png",
                "firebase_config.example.json",
                "firebase_config.json",
            ],
            "include_modules": {
                "*": ["gltf", "firebase_mp"],
            },
            "extra_prc_data": PRC_DATA,
            "icons": {"*": "assets/icon.png"},
        },
    },
    classifiers=["Topic :: Games/Entertainment"],
)
