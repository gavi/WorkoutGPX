#!/usr/bin/env python3
"""Builds the WorkoutGPX.butterkit package from the captured screenshots.

    python3 AppStore/make-butterkit.py [--shots AppStore/screenshots] [--out "<iCloud ButterKit dir>"]

Reads AppStore/screenshots/{iphone-6.9,ipad-13}/<scene>.png (written by
WorkoutGPXUITests/ScreenshotTests via AppStore/shots.sh) and writes a ButterKit
document with one artboard per scene for each size class, English as the source
language, plus a language variant of every artboard for each language in LANGUAGES
whose captures exist in AppStore/screenshots/<lang>/ (UI_LANG=<lang> AppStore/shots.sh):
the caption from CAPTIONS and that language's screenshot on the device. One package,
the localizations ButterKit shows in its Localizations panel and uploads per App Store
locale — never one package per language.

Re-running replaces the package, so edit the SCENES table below rather than the
artboards in ButterKit if you want the changes to survive a recapture. Quit ButterKit
before running: it caches the document and assets while the package is open.
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
    ("09-select-all", "Select many, export once"),
    ("02-filters", "Filter by activity and date"),
    ("03-hike-effort", "See every climb and descent"),
    ("05b-run-scrub", "Scrub the elevation profile"),
    ("04-hike-gradient-satellite", "Color routes by elevation"),
    ("06-ride-satellite", "Satellite and hybrid maps"),
    ("08-settings", "Units, maps and sensor data"),
    ("10-share-all", "One share sheet, every GPX"),
]

HERO_TITLE = "WorkoutGPX"
HERO_SUBTITLE = "Apple Health workouts, exported as GPX"

# The languages that become variants, in the order ButterKit lists them; a language without
# captures in screenshots/<lang>/ is skipped with a note.
LANGUAGES = ["de", "fr", "es", "ja"]

# Captions per language; the captures come from `UI_LANG=<lang> AppStore/shots.sh` into
# screenshots/<lang>/. Same width rule as the English captions: measured under 565 px at
# 40 pt (Hiragino for Japanese), or they wrap off the bottom edge of the iPhone board.
CAPTIONS = {
    "de": {
        "subtitle": "Apple-Health-Workouts als GPX",
        "09-select-all": "Viele wählen, einmal teilen",
        "02-filters": "Nach Aktivität und Datum",
        "03-hike-effort": "Jeder Anstieg, jeder Abstieg",
        "05b-run-scrub": "Das Höhenprofil abfahren",
        "04-hike-gradient-satellite": "Route nach Höhe einfärben",
        "06-ride-satellite": "Satelliten- und Hybridkarten",
        "08-settings": "Einheiten, Karten, Sensoren",
        "10-share-all": "Ein Teilen-Dialog, alle GPX",
    },
    "fr": {
        "subtitle": "Vos séances Apple Santé en GPX",
        "09-select-all": "Plusieurs séances, un export",
        "02-filters": "Filtrez par activité et par date",
        "03-hike-effort": "Chaque montée et descente",
        "05b-run-scrub": "Parcourez le profil d'altitude",
        "04-hike-gradient-satellite": "Colorez la trace par altitude",
        "06-ride-satellite": "Cartes satellite et hybride",
        "08-settings": "Unités, cartes et capteurs",
        "10-share-all": "Un partage, tous les GPX",
    },
    "es": {
        "subtitle": "Tus entrenos de Apple Salud en GPX",
        "09-select-all": "Selecciona varios y exporta",
        "02-filters": "Filtra por actividad y fecha",
        "03-hike-effort": "Cada subida y cada bajada",
        "05b-run-scrub": "Recorre el perfil de altitud",
        "04-hike-gradient-satellite": "Colorea la ruta por altitud",
        "06-ride-satellite": "Mapas satélite e híbrido",
        "08-settings": "Unidades, mapas y sensores",
        "10-share-all": "Todos los GPX de una vez",
    },
    "ja": {
        "subtitle": "ヘルスケアのワークアウトをGPXに",
        "09-select-all": "まとめて選んで、一度に書き出し",
        "02-filters": "アクティビティと日付で絞り込み",
        "03-hike-effort": "登りも下りもひと目で",
        "05b-run-scrub": "高度プロフィールをなぞる",
        "04-hike-gradient-satellite": "高度でルートを色分け",
        "06-ride-satellite": "衛星写真とハイブリッド地図",
        "08-settings": "単位・地図・センサーデータ",
        "10-share-all": "一度の共有ですべてのGPX",
    },
}

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


def variant(base, lang, captions, shot, is_hero, asset_filename):
    """The language variant of a base artboard: same geometry and text ids (ButterKit links the
    styles, background and callouts to the base), translated strings, its own device carrying the
    localized screenshot, parentID and variation as ButterKit writes them."""
    texts = []
    for block in base["textBlocks"]:
        block = dict(block)
        # `string` stays the English source; the variant shows `translatedString`. The app name
        # is the same in every language (ButterKit's own translator would render it otherwise).
        if is_hero:
            block["translatedString"] = captions["subtitle"] if block["role"] == "SubTitle" else HERO_TITLE
        else:
            block["translatedString"] = captions[shot]
        texts.append(block)
    models = []
    for model in base["models"]:
        model = dict(model)
        # The variant's device is its own instance, but `sourceModelID` has to keep pointing at
        # the base artboard's model or ButterKit cannot map the variant device to the base one
        # and draws a placeholder instead of the screenshot.
        model["id"] = new_id()
        model["screenImageFilename"] = asset_filename
        models.append(model)
    out = dict(base)
    out.update({
        "id": new_id(),
        "parentID": base["id"],
        "variation": {"code": lang, "kind": "language"},
        "linkBackground": True, "linkCallouts": True, "linkImages": True, "linkTextStyles": True,
        "textBlocks": texts,
        "models": models,
    })
    return out


def build(shots_dir, out_dir):
    package = os.path.join(out_dir, "WorkoutGPX.butterkit")
    assets = os.path.join(package, "Assets")
    if os.path.exists(package):
        shutil.rmtree(package)
    os.makedirs(assets)

    languages = [lang for lang in LANGUAGES if os.path.isdir(os.path.join(shots_dir, lang))]
    for lang in LANGUAGES:
        if lang not in languages:
            print(f"no captures in {os.path.join(shots_dir, lang)}: {lang} left out")

    def copy_asset(path):
        if not os.path.exists(path):
            sys.exit(f"missing screenshot: {path}")
        asset_filename = f"{new_id()}.png"
        shutil.copyfile(path, os.path.join(assets, asset_filename))
        return asset_filename

    artboards = []
    sequence = 0
    for preset_name, preset in PRESETS.items():
        count = len(SCENES)
        for index, (shot, caption) in enumerate(SCENES):
            asset_filename = copy_asset(os.path.join(shots_dir, preset["folder"], f"{shot}.png"))

            is_hero = caption is None
            if is_hero:
                texts = [
                    text_block(HERO_TITLE, 0, preset["hero_title"], "heavy", "#F5FCFFFF"),
                    text_block(HERO_SUBTITLE, 1, preset["hero_subtitle"], "regular", "#C9D3DCFF"),
                ]
            else:
                texts = [text_block(caption, 0, preset["caption"], "heavy", "#FFFFFFFF")]

            x = (index - (count - 1) / 2) * preset["spacing"]
            sequence += 1
            base = {
                "id": new_id(),
                "name": f"{preset_name} hero" if is_hero else f"{preset_name} {shot}",
                "sequenceIndex": sequence,
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
            }
            artboards.append(base)
            for lang in languages:
                localized = copy_asset(os.path.join(shots_dir, lang, preset["folder"], f"{shot}.png"))
                artboards.append(variant(base, lang, CAPTIONS[lang], shot, is_hero, localized))

    document = {
        "schemaVersion": 1,
        "baseLanguageCode": "en-US",
        "metadata": {},
        "translationEngineByLanguage": {},
        "translationCloudConfigIDByLanguage": {},
        "artboards": artboards,
    }
    with open(os.path.join(package, "Document.json"), "w") as handle:
        json.dump(document, handle, indent=2, ensure_ascii=False)
    bases = sum(1 for a in artboards if "parentID" not in a)
    print(f"wrote {package}: {bases} artboards, {len(artboards) - bases} language variants "
          f"({', '.join(languages) or 'none'}), {len(os.listdir(assets))} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", default=DEFAULT_SHOTS)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()
    build(args.shots, args.out)
