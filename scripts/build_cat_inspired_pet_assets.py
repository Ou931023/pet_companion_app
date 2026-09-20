#!/usr/bin/env python3
"""Build two pet packs from fixed RGBA bodies and feathered expression patches.

Requires ImageMagick. Sources and output are restricted to CR-0100G art; no
configuration or credentials are read. Run without --install to inspect first.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/asset_candidates/cr0100g_cat_inspired"
STATES = ("normal", "happy", "caring", "sad", "sleepy", "excited", "hungry", "thirsty")
SIZE = 1024
PROFILES = {
    "fox": {"ellipse": (630, 450, 165, 145), "talk": 6},
    "guinea_pig": {"ellipse": (600, 490, 210, 190), "talk": 3},
}


def magick(*args):
    return subprocess.run(["magick", *map(str, args)], check=True, capture_output=True).stdout


def digest_alpha(path):
    return hashlib.sha256(magick(path, "-alpha", "extract", "-depth", "8", "gray:-")).hexdigest()


def build(install=False):
    if not shutil.which("magick"):
        raise SystemExit("ImageMagick is required.")
    required = [SOURCE / f"{skin}_master_v1.png" for skin in PROFILES]
    required += [SOURCE / f"{skin}_{state}_source.png"
                 for skin in PROFILES for state in (*STATES[1:], "listening")]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        raise SystemExit("Missing source art:\n" + "\n".join(missing))

    output = SOURCE / "prepared"
    output.mkdir(exist_ok=True)
    report = {}
    for skin, profile in PROFILES.items():
        folder = output / skin
        folder.mkdir(exist_ok=True)
        normal = folder / "normal.png"
        master = SOURCE / f"{skin}_master_v1.png"
        protected = folder / "protected-body.png"
        magick(master, "-alpha", "extract", "-threshold", "5%",
               "-bordercolor", "black", "-border", "1", "-fill", "#808080",
               "-draw", "color 0,0 floodfill", "-fill", "white", "-opaque", "black",
               "-fill", "black", "-opaque", "#808080", "-shave", "1x1",
               "-morphology", "Erode", "Disk:6", protected)
        # Remove saturated red/yellow fringe only in the outer six pixels;
        # interior fur and eyes are protected from color-based removal.
        fringe = "((u.r>0.65&&u.g<0.25&&u.b<0.2)||(u.r>0.7&&u.g>0.65&&u.b<0.2))"
        magick(master, protected, "-channel", "A", "-fx",
               f"v.r>0.99?1:({fringe}?0:u.a)", "-morphology",
               "Erode", "Disk:1", "+channel", "-resize", f"{SIZE}x{SIZE}",
               "-strip", "-depth", "8", "-define", "png:color-type=6", normal)
        width = int(magick("identify", "-format", "%w", SOURCE / f"{skin}_master_v1.png"))
        cx, cy, rx, ry = profile["ellipse"]
        factor = SIZE / width
        ellipse = f"ellipse {cx*factor},{cy*factor} {rx*factor},{ry*factor} 0,360"
        mask = folder / "face-mask.png"
        magick("-size", f"{SIZE}x{SIZE}", "xc:black", "-fill", "white", "-draw",
               ellipse, "-blur", "0x6", "-depth", "8", mask)
        safe_face = folder / "opaque-interior.png"
        magick(normal, "-alpha", "extract", "-threshold", "99.9%",
               "-morphology", "Erode", "Disk:2", safe_face)
        magick(mask, safe_face, "-compose", "Multiply", "-composite", "-depth", "8", mask)
        mask_bytes = magick(mask, "-depth", "8", "gray:-")
        body = magick(normal, "-depth", "8", "rgba:-")
        alpha_hash = digest_alpha(normal)
        for state in (*STATES[1:], "listening"):
            patch = folder / "face-patch.png"
            # Ignore generated background alpha: only the inner face is used.
            magick(SOURCE / f"{skin}_{state}_source.png", "-resize", f"{SIZE}x{SIZE}!",
                   mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite", patch)
            target = folder / f"{state}.png"
            magick(normal, patch, "-compose", "Over", "-composite", "-strip",
                   "-depth", "8", "-define", "png:color-type=6", target)
            if digest_alpha(target) != alpha_hash:
                raise RuntimeError(f"{skin}/{state}: facial patch changes the body silhouette")
            pixels = magick(target, "-depth", "8", "rgba:-")
            changed_outside = sum(1 for i, amount in enumerate(mask_bytes)
                                  if amount == 0 and body[i*4+3] > 0
                                  and pixels[i*4:i*4+4] != body[i*4:i*4+4])
            if changed_outside:
                raise RuntimeError(f"{skin}/{state}: changed {changed_outside} body pixels outside face")

        report[skin] = {"size": SIZE, "alpha_sha256": alpha_hash,
                        "body_outside_face_unchanged": True, "states": list(STATES),
                        "listening": True}

    # Validate both complete packs before replacing any production image.
    if install:
        for skin, profile in PROFILES.items():
            folder = output / skin
            pets = ROOT / "assets/pets"
            for state in STATES:
                shutil.copyfile(folder / f"{state}.png", pets / "states" / f"{skin}_{state}.png")
            shutil.copyfile(folder / "listening.png", pets / "listening" / f"{skin}_listening.png")
            for index, state in enumerate(("normal", "sleepy", "normal"), 1):
                shutil.copyfile(folder / f"{state}.png", pets / "rest" / f"{skin}_rest_{index:02}.png")
            mouth_cycle = ("normal", "excited", "happy", "excited", "happy", "normal")
            for index, state in enumerate(mouth_cycle[:profile["talk"]], 1):
                shutil.copyfile(folder / f"{state}.png", pets / "talk" / f"{skin}_talk_{index:02}.png")
    (output / "qa-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"installed": install, "packs": report}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Replace only fox and guinea pig assets after validation")
    build(parser.parse_args().install)
