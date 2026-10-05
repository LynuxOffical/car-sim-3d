@echo off
REM Build a standalone Windows executable (dist\CarSim3D.exe).
REM Requires the project venv to exist: python -m venv .venv
cd /d "%~dp0"
call .venv\Scripts\activate.bat
pip install --quiet pyinstaller
set EXTRA_FB=
if exist firebase_config.json set EXTRA_FB=--add-data "firebase_config.json;."
pyinstaller --noconfirm --onefile --windowed --name CarSim3D ^
    --add-data "assets;assets" ^
    --copy-metadata panda3d-gltf ^
    --collect-all gltf ^
    --collect-binaries panda3d ^
    --hidden-import gltf._loader ^
    --hidden-import firebase_mp ^
    --add-data "firebase_config.example.json;." ^
    %EXTRA_FB% ^
    main.py
if %errorlevel% neq 0 (
    echo Build failed.
    exit /b 1
)
echo.
echo Build complete: dist\CarSim3D.exe
