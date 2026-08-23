#!/usr/bin/env python3
"""Builds the WorkoutGPX.butterkit package from the captured screenshots.

    python3 AppStore/make-butterkit.py [--shots AppStore/screenshots] [--out "<iCloud ButterKit dir>"]

Reads AppStore/screenshots/{iphone-6.9,ipad-13}/<scene>.png (written by
WorkoutGPXUITests/ScreenshotTests) and writes a ButterKit document with one
artboard per scene for each size class. Re-running replaces the package, so edit
the SCENES table below rather than the artboards in ButterKit if you want the
changes to survive a recapture. Quit ButterKit before running: it caches the
document and assets while the package is open.
"""

import argparse
import json
import os
import shutil
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SHOTS = os.path.join(HERE, "screenshots")
DEFAULT_OUT = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/ButterKit")

# (screenshot basename, caption). The first entry becomes the hero artboard with a
# title and subtitle instead of a caption. The App Store takes at most 10 per size.
SCENES = [
    ("01-workouts", None),
    ("02-filters", "Filter by activity and date"),
    ("03-hike-effort", "See every climb and descent"),
    ("05b-run-scrub", "Scrub the elevation profile"),
    ("04-hike-gradient-satellite", "Color routes by elevation"),
    ("06-ride-satellite", "Satellite and hybrid maps"),
    ("08-settings", "Units, maps and sensor data"),
    ("07-share", "Share GPX files anywhere"),
]

HERO_TITLE = "WorkoutGPX"
HERO_SUBTITLE = "Apple Health workouts, exported as GPX"

BACKGROUND = {"image": {"fill": "fill", "ref": {"name": "preset-bg-5", "type": "bundle"}}}

# Geometry copied from a ButterKit-authored document: artboard size, camera and
# column spacing per size preset. iPhone captions fit on one line up to ~565 px
# at 40 pt (measure with Helvetica bold 40 via PIL before changing copy).
PRESETS = {
    "iphone": {
        "folder": "iphone-6.9",
        "sizePresetID": "app_store_iphone",
        "size": [1.6125, 3.495],
        "y": 0.0,
        "spacing": 1.7328,
        "model": {"assetName": "iPhone17ProMax", "instanceLabel": "iPhone16",
                  "rotationEuler": [0, 0, 0], "scale": [1, 1, 1], "positionOffset": [0, 0, 0]},
        "hero_model": {"assetName": "iPhone17ProMax", "instanceLabel": "iPhone16",
                       "rotationEuler": [0, -0.46381047, -0.66531944], "scale": [1.09, 1.09, 1.09],
                       "positionOffset": [0.0, 0.012, 0]},
        "caption": {"sizePt": 40, "paddingTop": 93.38908032319392, "paddingSides": 0.0,
                    "fontFamily": "System Default", "role": "Text1"},
        "hero_title": {"sizePt": 44, "paddingTop": 80.8, "paddingSides": 24.898407794676803,
                       "fontFamily": "Avenir Next", "role": "Title", "horizontalAlignment": "leading"},
        "hero_subtitle": {"sizePt": 36, "paddingTop": 89.53035884030417, "paddingSides": 0.0,
                          "fontFamily": "System Default", "role": "SubTitle"},
    },
    "ipad": {
        "folder": "ipad-13",
        "sizePresetID": "app_store_ipad",
        "size": [2.56, 3.415],
        "y": -4.495,
        "spacing": 2.68,
        "model": {"assetName": "iPadPro129", "instanceLabel": "iPad Pro 12.9″",
                  "rotationEuler": [0, -0.2617994, 0], "scale": [1.1, 1.1, 1.1],
                  "positionOffset": [0, -0.0074857413, 0]},
        "hero_model": {"assetName": "iPadPro129", "instanceLabel": "iPad Pro 12.9″",
                       "rotationEuler": [0, -0.2617994, 0], "scale": [1.1, 1.1, 1.1],
                       "positionOffset": [0, -0.0074857413, 0]},
        "caption": {"sizePt": 44, "paddingTop": 4.421637357414459, "paddingSides": 6,
                    "fontFamily": "Avenir Next", "role": "Title"},
        "hero_title": {"sizePt": 52, "paddingTop": 3.2, "paddingSides": 6,
                       "fontFamily": "Avenir Next", "role": "Title"},
        "hero_subtitle": {"sizePt": 32, "paddingTop": 8.6, "paddingSides": 6,
                          "fontFamily": "System Default", "role": "SubTitle"},
    },
}


def new_id():
    return str(uuid.uuid4()).upper()


def text_block(string, index, spec, weight, color):
    return {
        "id": new_id(),
        "index": index,
        "string": string,
        "role": spec["role"],
        "fontFamily": spec["fontFamily"],
        "sizePt": spec["sizePt"],
        "weight": weight,
        "colorHex": color,
        "alignment": "center",
        "horizontalAlignment": spec.get("horizontalAlignment", "center"),
        "paddingTop": spec["paddingTop"],
        "paddingSides": spec["paddingSides"],
        "isItalic": False,
        "isUnderlined": False,
    }


def model_block(spec, asset_filename):
    model_id = new_id()
    return {
        "id": model_id,
        "sourceModelID": model_id,
        "assetName": spec["assetName"],
        "instanceLabel": spec["instanceLabel"],
        "deviceStyle": "realistic",
        "clayColorHex": "#CCCCCCFF",
        "rotationEuler": spec["rotationEuler"],
        "scale": spec["scale"],
        "positionOffset": spec["positionOffset"],
        "uiOnlyOverlayCornerRadiusFactor": 0,
        "screenImageFilename": asset_filename,
    }


def build(shots_dir, out_dir):
    package = os.path.join(out_dir, "WorkoutGPX.butterkit")
    assets = os.path.join(package, "Assets")
    if os.path.exists(package):
        shutil.rmtree(package)
    os.makedirs(assets)

    artboards = []
    for preset_name, preset in PRESETS.items():
        count = len(SCENES)
        for index, (shot, caption) in enumerate(SCENES):
            source = os.path.join(shots_dir, preset["folder"], f"{shot}.png")
            if not os.path.exists(source):
                sys.exit(f"missing screenshot: {source}")
            asset_filename = f"{new_id()}.png"
            shutil.copyfile(source, os.path.join(assets, asset_filename))

            is_hero = caption is None
            if is_hero:
                texts = [
                    text_block(HERO_TITLE, 0, preset["hero_title"], "heavy", "#F5FCFFFF"),
                    text_block(HERO_SUBTITLE, 1, preset["hero_subtitle"], "regular", "#C9D3DCFF"),
                ]
            else:
                texts = [text_block(caption, 0, preset["caption"], "heavy", "#FFFFFFFF")]

            x = (index - (count - 1) / 2) * preset["spacing"]
            artboards.append({
                "id": new_id(),
                "name": "Hero" if is_hero else shot,
                "sequenceIndex": index + 1,
                "sizePresetID": preset["sizePresetID"],
                "size": preset["size"],
                "position": [round(x, 4), preset["y"], 0],
                "cameraProjection": "perspective",
                "perspectiveFOVDeg": 35,
                "orthoHeight": 0.18917927,
                "background": BACKGROUND,
                "models": [model_block(preset["hero_model"] if is_hero else preset["model"], asset_filename)],
                "textBlocks": texts,
                "imageBlocks": [],
            })

    document = {"schemaVersion": 1, "baseLanguageCode": "en", "artboards": artboards}
    with open(os.path.join(package, "Document.json"), "w") as handle:
        json.dump(document, handle, indent=2)
    print(f"wrote {package}: {len(artboards)} artboards, {len(os.listdir(assets))} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", default=DEFAULT_SHOTS)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()
    build(args.shots, args.out)
