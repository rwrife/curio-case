"""Resize the AppStore icon into launchers; --check asserts they match."""
import sys
from pathlib import Path
from PIL import Image, ImageChops

root = Path(__file__).resolve().parent.parent
source = Image.open(root / "AppStore/icon.png")
assert source.size == (1024, 1024) and source.mode == "RGB"
paths = list((root / "android/app/src/main/res").glob("mipmap-*/ic_launcher.png"))
paths += list((root / "ios/Runner/Assets.xcassets/AppIcon.appiconset").glob("*.png"))
assert len(paths) >= 20, "Launcher icons missing"
for path in paths:
    with Image.open(path) as existing:
        size = existing.size
        expected = source.resize(size, Image.Resampling.LANCZOS)
        if "--check" in sys.argv:
            assert existing.mode == "RGB" and ImageChops.difference(existing, expected).getbbox() is None, path
        else:
            expected.save(path)
icon = root / "windows/runner/resources/app_icon.ico"
if "--check" in sys.argv:
    with Image.open(icon) as existing:
        assert existing.size == (256, 256), icon
        assert ImageChops.difference(existing.convert("RGB"), source.resize(existing.size, Image.Resampling.LANCZOS)).getbbox() is None, icon
else:
    source.save(icon, format="ICO", sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
print(f"{'Verified' if '--check' in sys.argv else 'Wrote'} {len(paths)} launchers and Windows icon")
