"""Resize the existing AppStore icon into launchers (requires Pillow)."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent
source = Image.open(root / "AppStore/icon.png")
assert source.size == (1024, 1024) and source.mode == "RGB"
paths = list((root / "android/app/src/main/res").glob("mipmap-*/ic_launcher.png"))
paths += list((root / "ios/Runner/Assets.xcassets/AppIcon.appiconset").glob("*.png"))
for path in paths:
    with Image.open(path) as existing:
        size = existing.size
    source.resize(size, Image.Resampling.LANCZOS).save(path)
source.save(root / "windows/runner/resources/app_icon.ico", format="ICO",
            sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
