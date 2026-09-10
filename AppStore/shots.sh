#!/bin/zsh
# Captures the App Store scenes from the real app in the simulator, the way
# gpxexplore/AppStore/shots.sh does for GPX Explore.
#
#   AppStore/shots.sh                     # both platforms, English  → screenshots/<platform>/
#   AppStore/shots.sh iphone              # one platform
#   UI_LANG=de AppStore/shots.sh          # the German app          → screenshots/de/<platform>/
#   SCENES=09-select-all,10-share-all AppStore/shots.sh iphone
#
# The scenes themselves live in WorkoutGPXUITests/ScreenshotTests.swift; this only
# drives xcodebuild. Uses release Xcode (DEVELOPER_DIR overrides) and the iOS 26.5
# simulators that match the ButterKit device models.
set -e
here=${0:A:h}
repo=${here:h}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Locale and units follow the language; the test maps the code to both.
# Unset UI_LANG means English into the flat screenshots/<platform>/.
lang=${UI_LANG:-en}
out=$here/screenshots
[[ $lang == en ]] || out=$here/screenshots/$lang

IPHONE_SIM=${IPHONE_SIM:-4F5CD2F7-C817-40C0-8BB2-A48A9BA03B9E}   # iPhone 17 Pro Max, iOS 26.5
IPAD_SIM=${IPAD_SIM:-082FD504-67F0-40CA-986D-755DE2340028}       # iPad Pro 13" M5, iOS 26.5

platforms=(${@:-iphone ipad})

for platform in $platforms; do
  case $platform in
    iphone) udid=$IPHONE_SIM; folder=iphone-6.9 ;;
    ipad)   udid=$IPAD_SIM;   folder=ipad-13 ;;
    *) echo "unknown platform: $platform" >&2; exit 1 ;;
  esac

  echo "== $platform ($lang) → $out/$folder"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b
  # Dark everywhere (Gavi's rule), and the store's 9:41 status bar
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override --time 9:41 \
    --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4

  xcodebuild build-for-testing -project "$repo/WorkoutGPX.xcodeproj" -scheme WorkoutGPX \
    -destination "platform=iOS Simulator,id=$udid" CODE_SIGNING_ALLOWED=NO \
    -quiet

  mkdir -p "$out/$folder"
  # TEST_RUNNER_* reach the test as plain environment variables (DOC_SHOTS, DOC_SCENES,
  # UI_LANG); passing them as xcodebuild build settings does not work here.
  TEST_RUNNER_DOC_SHOTS="$out/$folder" TEST_RUNNER_UI_LANG=$lang \
  TEST_RUNNER_DOC_SCENES=${SCENES:-} \
    xcodebuild test-without-building -project "$repo/WorkoutGPX.xcodeproj" -scheme WorkoutGPX \
      -destination "platform=iOS Simulator,id=$udid" \
      -only-testing:WorkoutGPXUITests/ScreenshotTests
done
