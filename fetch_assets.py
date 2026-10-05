"""One-shot helper: download the CC0 Kenney Car Kit and extract the GLB
models we need into assets/cars/."""
import io
import os
import re
import urllib.request
import zipfile

UA = {"User-Agent": "Mozilla/5.0 (car-sim-3d asset fetcher)"}

page = urllib.request.urlopen(
    urllib.request.Request("https://kenney.nl/assets/car-kit", headers=UA),
    timeout=60).read().decode("utf-8", "replace")

candidates = re.findall(r'["\']([^"\'\s]*(?:\.zip|download)[^"\'\s]*)["\']', page)
print("candidate links:", candidates[:40])
zips = [c for c in candidates if ".zip" in c]
if not zips:
    with open("carkit_page.html", "w", encoding="utf-8") as f:
        f.write(page)
    raise SystemExit("no zip link; page dumped to carkit_page.html")
url = zips[0]
if url.startswith("/"):
    url = "https://kenney.nl" + url
print("downloading", url)

data = urllib.request.urlopen(
    urllib.request.Request(url, headers=UA), timeout=300).read()
print("got", len(data), "bytes")

zf = zipfile.ZipFile(io.BytesIO(data))
names = zf.namelist()
glbs = [n for n in names if n.lower().endswith((".glb", ".gltf"))]
print("archive entries:", len(names))
for n in sorted(glbs):
    print("  ", n)

os.makedirs("assets/cars/Textures", exist_ok=True)
for n in glbs:
    out = os.path.join("assets/cars", os.path.basename(n))
    with open(out, "wb") as f:
        f.write(zf.read(n))
extra = [n for n in names
         if "license" in n.lower()
         or ("/GLB format/Textures/" in n and n.lower().endswith(".png"))]
for n in extra:
    sub = "Textures/" + os.path.basename(n) if n.lower().endswith(".png") else os.path.basename(n)
    with open(os.path.join("assets/cars", sub), "wb") as f:
        f.write(zf.read(n))
print("extracted", len(glbs), "models +", len(extra), "extras to assets/cars/")
