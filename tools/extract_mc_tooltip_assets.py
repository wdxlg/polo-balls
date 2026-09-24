"""Extract unmodified Minecraft 1.21.4 tooltip/effect sprites from Mojang's client.

No third-party image copies or drawn approximations are used. Existing edited images
are not overwritten unless --force is explicitly supplied.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
from urllib.request import urlopen
from zipfile import ZipFile


CLIENT_URL = "https://piston-data.mojang.com/v1/objects/a7e5a6024bfd3cd614625aa05629adf760020304/client.jar"
CLIENT_SHA1 = "a7e5a6024bfd3cd614625aa05629adf760020304"
CLIENT_VERSION = "1.21.4"
SOURCE_PREFIX = "assets/minecraft/textures/"
DESTINATION = Path(__file__).resolve().parents[1] / "Images/UI/minecraft_tooltips"
BACKGROUND_SPRITES = {
    "gui/sprites/container/inventory/effect_background_large.png": "effect_background_large.png",
    "gui/sprites/tooltip/background.png": "tooltip_background.png",
    "gui/sprites/tooltip/frame.png": "tooltip_frame.png",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, help="Use an already downloaded official client JAR")
    parser.add_argument("--force", action="store_true", help="Replace locally modified PNGs")
    args = parser.parse_args()
    if args.jar:
        client_bytes = args.jar.read_bytes()
    else:
        with urlopen(CLIENT_URL, timeout=120) as response:
            client_bytes = response.read()
    digest = hashlib.sha1(client_bytes).hexdigest()
    if digest != CLIENT_SHA1:
        raise ValueError(f"Refusing to extract: official client SHA-1 mismatch ({digest})")

    with ZipFile(io.BytesIO(client_bytes)) as jar:
        sprites = dict(BACKGROUND_SPRITES)
        icon_prefix = "mob_effect/"
        for jar_path in jar.namelist():
            if not jar_path.startswith(SOURCE_PREFIX + icon_prefix) or not jar_path.endswith(".png"):
                continue
            relative_path = jar_path.removeprefix(SOURCE_PREFIX)
            if "/" in relative_path.removeprefix(icon_prefix):
                continue
            sprites[relative_path] = relative_path

        if not any(path.startswith(icon_prefix) for path in sprites):
            raise ValueError("Client JAR has no vanilla effect icons")
        source_assets = []
        for original_path, output_path in sorted(sprites.items()):
            original = SOURCE_PREFIX + original_path
            png = jar.read(original)
            destination = DESTINATION / output_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists() and destination.read_bytes() != png and not args.force:
                raise ValueError(f"Locally customized sprite exists: {destination}. Use --force only deliberately.")
            if not destination.exists() or destination.read_bytes() != png:
                destination.write_bytes(png)
            source_assets.append({
                "filename": output_path.replace("\\", "/"),
                "jar_path": original,
                "sha256": hashlib.sha256(png).hexdigest(),
            })

    metadata = {
        "source": "Mojang official Minecraft Java Edition client JAR",
        "version": CLIENT_VERSION,
        "client_url": CLIENT_URL,
        "client_sha1": CLIENT_SHA1,
        "verification": "Client SHA-1 verified before extraction; original PNG bytes were not modified.",
        "assets": source_assets,
        "rights": "Minecraft textures belong to Mojang/Microsoft; inclusion does not grant a new license.",
        "usage": "Potion 120x32 background uses nine-slice expansion; tooltip 100x100 background/frame use their official 9px/10px nine-slice margins. Mob-effect icons are the original 18x18 PNGs.",
    }
    (DESTINATION / "SOURCE.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified Minecraft {CLIENT_VERSION} JAR SHA-1; installed {len(source_assets)} original sprites at {DESTINATION}")


if __name__ == "__main__":
    main()
