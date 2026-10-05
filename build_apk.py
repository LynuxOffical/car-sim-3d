"""Build an Android App Bundle and a sideloadable universal APK.

Panda3D 1.10 pip wheels cannot produce Android packages. This uses Panda3D 1.11
`bdist_apps` with Android wheels from rdb.name, then bundletool --mode universal.

Requires Python 3.13, JDK (keytool), and an Android SDK (build-tools + platforms).
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VENDOR = ROOT / "vendor"
WHEELS = VENDOR / "android-wheels"
VENV = ROOT / ".venv-android"
DIST = ROOT / "dist"
KEYSTORE = ROOT / "debug.keystore"
BUNDLETOOL_VER = "1.18.2"
BUNDLETOOL = VENDOR / f"bundletool-all-{BUNDLETOOL_VER}.jar"

WHEEL_URLS = [
    "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_arm64.whl",
    "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_armv7a.whl",
]
WHEEL_FALLBACK = {
    "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_arm64.whl":
        "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_arm64-r26b.whl",
    "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_armv7a.whl":
        "https://rdb.name/panda3d-1.11.0-cp313-cp313-android_armv7a-r26b.whl",
}
BUNDLETOOL_URL = (
    f"https://github.com/google/bundletool/releases/download/"
    f"{BUNDLETOOL_VER}/bundletool-all-{BUNDLETOOL_VER}.jar"
)
HOST_PANDA = "https://archive.panda3d.org/"


class BuildError(RuntimeError):
    pass


def log(msg: str) -> None:
    print(msg, flush=True)


def run(cmd, **kwargs):
    log("> " + " ".join(str(c) for c in cmd))
    subprocess.check_call(cmd, **kwargs)


def find_python313() -> str:
    candidates = [
        os.environ.get("PYTHON313"),
        str(Path(os.environ.get("LOCALAPPDATA", ""))
            / "Programs" / "Python" / "Python313" / "python.exe"),
        shutil.which("py") and "py",
    ]
    for c in candidates:
        if not c:
            continue
        if c == "py":
            try:
                out = subprocess.check_output(
                    ["py", "-3.13", "-c", "import sys; print(sys.executable)"],
                    text=True)
                return out.strip()
            except (subprocess.CalledProcessError, FileNotFoundError):
                continue
        if Path(c).is_file():
            return c
    raise BuildError("Python 3.13 is required for Panda3D Android packaging.")


def find_java_home() -> Path:
    env = os.environ.get("JAVA_HOME")
    if env and (Path(env) / "bin" / "keytool.exe").is_file():
        return Path(env)
    jdk = Path(r"C:\Program Files\Java\jdk-21.0.11")
    if (jdk / "bin" / "keytool.exe").is_file():
        return jdk
    # Newest jdk-* under Program Files\Java
    root = Path(r"C:\Program Files\Java")
    if root.is_dir():
        jdks = sorted(root.glob("jdk-*"), reverse=True)
        for j in jdks:
            if (j / "bin" / "keytool.exe").is_file():
                return j
    raise BuildError("JDK not found (need keytool). Install a JDK and/or set JAVA_HOME.")


def find_android_sdk() -> Path:
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        val = os.environ.get(key)
        if val and Path(val).is_dir():
            return Path(val)
    local = Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk"
    if local.is_dir():
        return local
    raise BuildError("Android SDK not found. Set ANDROID_HOME.")


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and dest.stat().st_size > 1024:
        log(f"have {dest.name}")
        return
    log(f"download {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        urllib.request.urlretrieve(url, tmp)
        tmp.replace(dest)
    except Exception:
        if tmp.exists():
            tmp.unlink()
        raise


def download_wheels() -> None:
    WHEELS.mkdir(parents=True, exist_ok=True)
    for url in WHEEL_URLS:
        name = url.rsplit("/", 1)[-1]
        dest = WHEELS / name
        try:
            download(url, dest)
        except Exception as exc:
            fallback = WHEEL_FALLBACK.get(url)
            if not fallback:
                raise BuildError(f"Could not download {url}: {exc}") from exc
            log(f"retry {fallback}")
            fb_name = fallback.rsplit("/", 1)[-1]
            fb_dest = WHEELS / fb_name
            download(fallback, fb_dest)
            # bdist_apps matches cp313-android_arm64; copy to the expected name.
            if not dest.exists():
                shutil.copyfile(fb_dest, dest)


def ensure_icon() -> None:
    icon = ROOT / "assets" / "icon.png"
    if not icon.is_file():
        run([sys.executable, str(ROOT / "make_icon.py")], cwd=str(ROOT))


def ensure_venv(py313: str) -> Path:
    python = VENV / "Scripts" / "python.exe"
    if not python.is_file():
        log(f"creating {VENV}")
        run([py313, "-m", "venv", str(VENV)])
    run([str(python), "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"])
    # Snapshot index first so pip does not settle on PyPI's 1.10.x stable.
    run([str(python), "-m", "pip", "install", "--pre", "--upgrade",
         "--index-url", HOST_PANDA, "--extra-index-url", "https://pypi.org/simple",
         "--prefer-binary", "panda3d"])
    ver = subprocess.check_output(
        [str(python), "-c",
         "from panda3d.core import PandaSystem; print(PandaSystem.getVersionString())"],
        text=True).strip()
    log(f"host panda3d = {ver}")
    if not ver.startswith("1.11"):
        raise BuildError(
            f"Need Panda3D 1.11 on the host for Android packaging, got {ver}. "
            f"Check {HOST_PANDA}")
    run([str(python), "-m", "pip", "install",
         "--extra-index-url", "https://pypi.org/simple",
         "panda3d-gltf>=1.3", "protobuf"])
    return python


def ensure_keystore(java_home: Path) -> None:
    if KEYSTORE.is_file():
        return
    keytool = java_home / "bin" / "keytool.exe"
    run([str(keytool), "-genkeypair", "-keystore", str(KEYSTORE),
         "-storepass", "android", "-keypass", "android",
         "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048",
         "-validity", "10000",
         "-dname", "CN=CarSim3D, OU=Dev, O=CarSim, L=NA, ST=NA, C=US"])


def find_aab() -> Path:
    DIST.mkdir(exist_ok=True)
    aabs = sorted(DIST.glob("*android*.aab"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not aabs:
        aabs = sorted(DIST.glob("*.aab"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not aabs:
        raise BuildError("bdist_apps did not produce an .aab in dist/")
    return aabs[0]


def extract_universal_apk(apks_path: Path, dest_apk: Path) -> None:
    with zipfile.ZipFile(apks_path) as zf:
        names = zf.namelist()
        uni = [n for n in names if n.lower().endswith("universal.apk")]
        if not uni:
            uni = [n for n in names if n.lower().endswith(".apk")]
        if not uni:
            raise BuildError(f"No .apk inside {apks_path}: {names}")
        dest_apk.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(uni[0]) as src, open(dest_apk, "wb") as out:
            shutil.copyfileobj(src, out)
        log(f"extracted {uni[0]} -> {dest_apk} ({dest_apk.stat().st_size} bytes)")


def main() -> int:
    try:
        ensure_icon()
        py313 = find_python313()
        log(f"python3.13 = {py313}")
        java_home = find_java_home()
        sdk = find_android_sdk()
        log(f"JAVA_HOME = {java_home}")
        log(f"ANDROID_SDK = {sdk}")
        env = os.environ.copy()
        env["JAVA_HOME"] = str(java_home)
        env["ANDROID_HOME"] = str(sdk)
        env["ANDROID_SDK_ROOT"] = str(sdk)
        env["PATH"] = str(java_home / "bin") + os.pathsep + env.get("PATH", "")

        download_wheels()
        download(BUNDLETOOL_URL, BUNDLETOOL)
        python = ensure_venv(py313)
        ensure_keystore(java_home)

        # Fresh Android package (leave Windows exe in dist/ alone).
        for leftover in DIST.glob("*android*"):
            leftover.unlink()

        run([str(python), "setup.py", "bdist_apps",
             "--requirements-path", "requirements-android.txt"],
            cwd=str(ROOT), env=env)

        aab = find_aab()
        apks = DIST / "CarSim3D.apks"
        if apks.exists():
            apks.unlink()
        run(["java", "-jar", str(BUNDLETOOL), "build-apks",
             f"--bundle={aab}",
             f"--output={apks}",
             f"--ks={KEYSTORE}",
             "--ks-key-alias=androiddebugkey",
             "--ks-pass=pass:android",
             "--key-pass=pass:android",
             "--mode=universal"],
            env=env)

        apk = DIST / "CarSim3D.apk"
        extract_universal_apk(apks, apk)
        log("")
        log(f"AAB : {aab}")
        log(f"APK : {apk}")
        log("Install with:  adb install -r dist\\CarSim3D.apk")
        return 0
    except (BuildError, subprocess.CalledProcessError, OSError) as exc:
        log(f"APK build failed: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
