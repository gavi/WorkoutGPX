import XCTest

// App Store screenshot harness. Drives the simulator build (which seeds the
// demo workouts from SimulatorDemoData) through the scenes the store listing
// shows and writes a full-screen PNG of each straight to the host directory
// named by TEST_RUNNER_DOC_SHOTS. Skips when that variable is unset so it never
// runs as part of a normal test pass. See AppStore/README.md for the workflow.
final class ScreenshotTests: XCTestCase {

    // Scenes are (attachment name, launch-argument overrides, steps to reach it)
    private struct Scene {
        let name: String
        let arguments: [String]
        let navigate: (XCUIApplication) -> Void
    }

    private var outputDirectory: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let directory = ProcessInfo.processInfo.environment["DOC_SHOTS"] ?? ""
        guard !directory.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_DOC_SHOTS=<dir> on the xcodebuild invocation to capture screenshots.")
        }
        outputDirectory = directory
    }

    @MainActor
    func testCaptureStoreScenes() throws {
        // UI_LANG (TEST_RUNNER_UI_LANG on the xcodebuild invocation) picks the language the app
        // launches in; the locale and the units follow it, as they do in GPX Explore's shots.sh.
        // Unset means English with miles and the US locale, the storefront the listing is
        // written for. Every run starts from the same settings so captures are reproducible.
        let language = Self.language
        let baseArguments = [
            "-AppleLanguages", "(\(language.code))",
            "-AppleLocale", language.locale,
            "-reviewPromptDisabled", "YES",
            "-useMetricSystem", language.metric,
            "-includeSensorData", "YES",
            "-mapStyle", "Standard",
            "-elevationVisualizationMode", "Effort",
            "-trackLineWidth", "5",
            "-defaultShowElevationOverlay", "YES",
            "-defaultShowRouteInfoOverlay", "YES",
            "-chartDataDensity", "0.5",
        ]

        let scenes: [Scene] = [
            // Hero artboard: the tilted device shows the top of the screen, so let the map fill it
            Scene(name: "00-hero", arguments: ["-defaultShowRouteInfoOverlay", "NO"]) { app in
                self.openWorkout(app, activity: "hiking", index: 0)
            },

            Scene(name: "01-workouts", arguments: []) { _ in },

            Scene(name: "02-filters", arguments: []) { app in
                app.buttons["filters-button"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.0)
            },

            // The Blue Hills hike: the longest climb, so the elevation profile has shape
            Scene(name: "03-hike-effort", arguments: []) { app in
                self.openWorkout(app, activity: "hiking", index: 0)
            },

            Scene(name: "04-hike-gradient-satellite", arguments: ["-mapStyle", "Hybrid", "-elevationVisualizationMode", "Gradient"]) { app in
                self.openWorkout(app, activity: "hiking", index: 0)
            },

            Scene(name: "05-run-effort", arguments: []) { app in
                self.openWorkout(app, activity: "running", index: 0)
            },

            // Scrub the profile: the chart annotation and the map marker follow the finger
            Scene(name: "05b-run-scrub", arguments: ["-keepChartSelection"]) { app in
                self.openWorkout(app, activity: "running", index: 0)
                let chart = app.otherElements["elevation-chart"].firstMatch
                XCTAssertTrue(chart.waitForExistence(timeout: 5), "elevation chart not on screen")
                let from = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
                let to = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.5))
                from.press(forDuration: 0.3, thenDragTo: to)
                Thread.sleep(forTimeInterval: 1.5)
            },

            Scene(name: "06-ride-satellite", arguments: ["-mapStyle", "Satellite"]) { app in
                self.openWorkout(app, activity: "cycling", index: 0)
            },

            Scene(name: "07-share", arguments: []) { app in
                self.openWorkout(app, activity: "hiking", index: 0)
                app.buttons["export-button"].firstMatch.tap()
                // The share sheet is a system overlay; give it time to lay out its targets
                Thread.sleep(forTimeInterval: 3.0)
            },

            Scene(name: "08-settings", arguments: []) { app in
                app.buttons["settings-button"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.0)
            },

            // Multi-select: Select, then Select All, so every row is ticked and the
            // bottom bar shows the count and the Export button
            Scene(name: "09-select-all", arguments: []) { app in
                self.selectAllWorkouts(app)
                Thread.sleep(forTimeInterval: 1.0)
            },

            // Export the selection: one share sheet carrying every GPX file
            Scene(name: "10-share-all", arguments: []) { app in
                self.selectAllWorkouts(app)
                app.buttons["export-selected-button"].firstMatch.tap()
                // Route fetches, then the share sheet laying out its targets
                Thread.sleep(forTimeInterval: 6.0)
            },
        ]

        // DOC_SCENES=09-select-all,10-share-all captures a subset (TEST_RUNNER_DOC_SCENES from xcodebuild)
        let wanted: Set<String>? = ProcessInfo.processInfo.environment["DOC_SCENES"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { Set($0.split(separator: ",").map { String($0) }) }

        for scene in scenes where wanted?.contains(scene.name) ?? true {
            let app = XCUIApplication()
            app.launchArguments = baseArguments + scene.arguments
            app.launch()

            // The list is the first screen; wait for the demo workouts to land
            XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 15), "workout list never appeared")
            Thread.sleep(forTimeInterval: 1.0)

            scene.navigate(app)
            snap(app, name: scene.name)
            app.terminate()
        }
    }

    // Enters selection mode and ticks every workout under the current filter
    @MainActor
    private func selectAllWorkouts(_ app: XCUIApplication) {
        app.buttons["select-button"].firstMatch.tap()
        let selectAll = app.buttons["select-all-button"].firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "select-all button never appeared")
        selectAll.tap()
        let export = app.buttons["export-selected-button"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5), "export button never appeared in the bottom bar")
    }

    // Opens the n-th row of the given activity and waits for its route to render. The activity
    // is the unlocalized GPX type ("hiking", "running", "cycling") behind WorkoutRow's
    // accessibility identifier, so the same scene works in every language.
    @MainActor
    private func openWorkout(_ app: XCUIApplication, activity: String, index: Int) {
        let identifier = "workout-row-\(activity)"
        let row = app.cells.containing(.any, identifier: identifier).element(boundBy: index)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no \(activity) row #\(index) in the list")
        row.tap()

        // The options menu enables once the route has loaded; the map tiles and
        // chart need a moment more to draw.
        let menu = app.buttons["view-options-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "detail view never appeared")
        let deadline = Date().addingTimeInterval(10)
        while !menu.isEnabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        Thread.sleep(forTimeInterval: 4.0)
    }

    // The language the captures are taken in, with the locale and units that go with it.
    // Captures land in AppStore/screenshots/<lang>/<platform>/ (the caller sets DOC_SHOTS);
    // English keeps the flat AppStore/screenshots/<platform>/.
    private struct Language {
        let code: String
        let locale: String
        let metric: String
    }

    private static var language: Language {
        let code = ProcessInfo.processInfo.environment["UI_LANG"].flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        switch code {
        case "de": return Language(code: code, locale: "de_DE", metric: "YES")
        case "fr": return Language(code: code, locale: "fr_FR", metric: "YES")
        case "es": return Language(code: code, locale: "es_ES", metric: "YES")
        case "ja": return Language(code: code, locale: "ja_JP", metric: "YES")
        case "en": return Language(code: code, locale: "en_US", metric: "NO")
        default: return Language(code: code, locale: "\(code)_\(code.uppercased())", metric: "YES")
        }
    }

    @MainActor
    private func snap(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = outputDirectory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: directory), withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
            NSLog("[store-capture] wrote \(url.path)")
        } catch {
            XCTFail("could not write \(url.path): \(error)")
        }
    }
}
