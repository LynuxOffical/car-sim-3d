@echo off
REM Build dist\CarSim3D.apk (and the Play Store .aab) via Panda3D 1.11.
REM Requires Python 3.13, a JDK, and the Android SDK.
cd /d "%~dp0"
set "PYTHON313=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not exist "%PYTHON313%" (
    echo Python 3.13 not found at %PYTHON313%
    exit /b 1
)
"%PYTHON313%" build_apk.py
