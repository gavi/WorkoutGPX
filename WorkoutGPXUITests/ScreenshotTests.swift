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
        // Miles and the US locale match the storefront the listing is written for;
        // every run starts from the same settings so captures are reproducible.
        let baseArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-useMetricSystem", "NO",
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
                self.openWorkout(app, activity: "Hiking", index: 0)
            },

            Scene(name: "01-workouts", arguments: []) { _ in },

            Scene(name: "02-filters", arguments: []) { app in
                app.buttons["filters-button"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.0)
            },

            // The Blue Hills hike: the longest climb, so the elevation profile has shape
            Scene(name: "03-hike-effort", arguments: []) { app in
                self.openWorkout(app, activity: "Hiking", index: 0)
            },

            Scene(name: "04-hike-gradient-satellite", arguments: ["-mapStyle", "Hybrid", "-elevationVisualizationMode", "Gradient"]) { app in
                self.openWorkout(app, activity: "Hiking", index: 0)
            },

            Scene(name: "05-run-effort", arguments: []) { app in
                self.openWorkout(app, activity: "Running", index: 0)
            },

            // Scrub the profile: the chart annotation and the map marker follow the finger
            Scene(name: "05b-run-scrub", arguments: ["-keepChartSelection"]) { app in
                self.openWorkout(app, activity: "Running", index: 0)
                let chart = app.otherElements["elevation-chart"].firstMatch
                XCTAssertTrue(chart.waitForExistence(timeout: 5), "elevation chart not on screen")
                let from = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
                let to = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.5))
                from.press(forDuration: 0.3, thenDragTo: to)
                Thread.sleep(forTimeInterval: 1.5)
            },

            Scene(name: "06-ride-satellite", arguments: ["-mapStyle", "Satellite"]) { app in
                self.openWorkout(app, activity: "Cycling", index: 0)
            },

            Scene(name: "07-share", arguments: []) { app in
                self.openWorkout(app, activity: "Hiking", index: 0)
                app.buttons["export-button"].firstMatch.tap()
                // The share sheet is a system overlay; give it time to lay out its targets
                Thread.sleep(forTimeInterval: 3.0)
            },

            Scene(name: "08-settings", arguments: []) { app in
                app.buttons["settings-button"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.0)
            },
        ]

        for scene in scenes {
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

    // Opens the n-th row of the given activity and waits for its route to render
    @MainActor
    private func openWorkout(_ app: XCUIApplication, activity: String, index: Int) {
        let row = app.cells.containing(.staticText, identifier: activity).element(boundBy: index)
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
