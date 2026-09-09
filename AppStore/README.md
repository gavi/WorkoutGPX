# App Store screenshots

How the store artboards get refreshed. Everything comes from **driving the real app
in a simulator** — nothing is mocked up in a design tool.

```
xcodebuild test (ScreenshotTests)  →  raw PNGs  →  make-butterkit.py  →  ButterKit  →  Publish  →  App Store Connect
```

## 0. Where the data comes from

The simulator has no HealthKit data, so `HealthStore` seeds demo workouts from
`SimulatorDemoData` (simulator-only, compiled out of device builds). Each entry
borrows a track from the bundled `WorkoutGPX/Samples/*.gpx` files — public Garmin
demo tracks of Massachusetts trails, one `<trk>` each — and gives it an activity,
a recent date and a plausible pace; three route-less entries exercise the
"without GPS" filter. Edit the catalog there to change what the list shows.

Never put real workout exports in `Samples/`: the folder ships inside the app bundle.

## 1. Capture

`WorkoutGPXUITests/ScreenshotTests` walks the scenes and writes PNGs straight to
the directory in `TEST_RUNNER_DOC_SHOTS`; without that variable it skips, so a
normal test pass (Xcode Cloud included) never runs it. Use release Xcode; the
iOS 26.5 simulators below match the ButterKit device models.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=4F5CD2F7-C817-40C0-8BB2-A48A9BA03B9E   # iPhone 17 Pro Max, iOS 26.5 (1320×2868)
# SIM=082FD504-67F0-40CA-986D-755DE2340028 # iPad Pro 13" M5, iOS 26.5 (2064×2752)
xcrun simctl boot "$SIM"; xcrun simctl bootstatus "$SIM" -b
xcrun simctl ui "$SIM" appearance dark
xcrun simctl status_bar "$SIM" override --time 9:41 \
  --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4

xcodebuild build-for-testing -project WorkoutGPX.xcodeproj -scheme WorkoutGPX \
  -destination "platform=iOS Simulator,id=$SIM" CODE_SIGNING_ALLOWED=NO

TEST_RUNNER_DOC_SHOTS=$PWD/AppStore/screenshots/iphone-6.9 \
xcodebuild test-without-building -project WorkoutGPX.xcodeproj -scheme WorkoutGPX \
  -destination "platform=iOS Simulator,id=$SIM" \
  -only-testing:WorkoutGPXUITests/ScreenshotTests
```

Repeat with the iPad simulator into `AppStore/screenshots/ipad-13/`. The scenes
launch with fixed settings (miles, `en_US`, Standard map, Effort coloring, line
width 5) passed as launch arguments, so captures are reproducible; the
`-keepChartSelection` flag lets the scrub scene keep the map marker after the
synthetic drag lifts.

Scenes: `00-hero` (hike, no route-info card), `01-workouts`, `02-filters`,
`03-hike-effort`, `04-hike-gradient-satellite`, `05-run-effort`, `05b-run-scrub`,
`06-ride-satellite`, `07-share`, `08-settings`, `09-select-all` (every row ticked,
bottom bar with Export), `10-share-all` (the share sheet with one GPX per workout).
Add `TEST_RUNNER_DOC_SCENES=09-select-all,10-share-all` to capture only some scenes.

## 2. Build the ButterKit package

```sh
python3 AppStore/make-butterkit.py
```

Writes `~/Library/Mobile Documents/com~apple~CloudDocs/ButterKit/WorkoutGPX.butterkit`
(a `Document.json` plus `Assets/<UUID>.png`), replacing the previous package: one
artboard per scene for `app_store_iphone` and `app_store_ipad`, the first as a hero
with title + subtitle, the rest with a caption. Captions, scene order, background
(`preset-bg-5`, the dark contour map) and device geometry live in the script — change
them there, not in ButterKit, or the next regeneration discards the edits.

**Quit ButterKit before regenerating**: it caches the document and assets while the
package is open.

iPhone captions are 40 pt and must stay under ~565 px wide or they wrap off the
bottom edge; measure before changing copy:

```python
from PIL import ImageFont
ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40, index=1).getlength("New caption")
```

## 3. Export and upload

ButterKit exports from the GUI (**Publish**) — there is no CLI. Export both size
classes and upload in App Store Connect → the version → iPhone 6.9" / iPad 13".
The App Store takes at most 10 screenshots per size; the package has nine boards
(the multi-select board is second, the multi-file share sheet last). The single-file
`07-share` scene is still captured but no longer on a board.

The listing copy (description, promotional text, release notes) is in
`listing-metadata.txt`.
