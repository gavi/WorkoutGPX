#if targetEnvironment(simulator)
import Foundation
import HealthKit
import CoreLocation

// Realistic-looking workouts for the simulator, where HealthKit has no data.
// Each route entry borrows a track from the bundled sample GPX files (public
// Garmin demo tracks of Massachusetts trails) and gives it an activity, a recent
// date, and a plausible pace; route-less entries exercise the "without GPS" filter.
// Used for development and for App Store screenshot capture (WorkoutGPXUITests).
enum SimulatorDemoData {

    // A sample track dressed up as a workout
    struct RouteEntry {
        let trackName: String
        let activityType: HKWorkoutActivityType
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let kilometersPerHour: Double
    }

    // A workout with no location data
    struct RoutelessEntry {
        let activityType: HKWorkoutActivityType
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let durationMinutes: Double
        let kilocalories: Double
    }

    // A demo workout and, when it has a route, the track backing it
    struct DemoWorkout {
        let workout: HKWorkout
        let track: RouteTrack?
    }

    static let routeCatalog: [RouteEntry] = [
        RouteEntry(trackName: "Untitled",      activityType: .running, daysAgo: 0,  hour: 7,  minute: 12, kilometersPerHour: 9.6),
        RouteEntry(trackName: "SHORT TRACK",   activityType: .walking, daysAgo: 1,  hour: 17, minute: 40, kilometersPerHour: 5.2),
        RouteEntry(trackName: "LAP 1",         activityType: .running, daysAgo: 2,  hour: 6,  minute: 40, kilometersPerHour: 10.8),
        RouteEntry(trackName: "LONG TRACK",    activityType: .running, daysAgo: 4,  hour: 6,  minute: 55, kilometersPerHour: 10.2),
        RouteEntry(trackName: "BIG LOOP",      activityType: .cycling, daysAgo: 5,  hour: 7,  minute: 30, kilometersPerHour: 19.0),
        RouteEntry(trackName: "TUFTS CONNECT", activityType: .walking, daysAgo: 7,  hour: 12, minute: 5,  kilometersPerHour: 4.8),
        RouteEntry(trackName: "LAP 2",         activityType: .running, daysAgo: 9,  hour: 6,  minute: 45, kilometersPerHour: 10.5),
        RouteEntry(trackName: "SHORT LOOP",    activityType: .hiking,  daysAgo: 12, hour: 8,  minute: 5,  kilometersPerHour: 3.9),
        RouteEntry(trackName: "ASP RESERV",    activityType: .cycling, daysAgo: 14, hour: 8,  minute: 10, kilometersPerHour: 21.0),
        RouteEntry(trackName: "LAP 3",         activityType: .walking, daysAgo: 16, hour: 12, minute: 15, kilometersPerHour: 5.0),
        RouteEntry(trackName: "VIL RUNNING",   activityType: .running, daysAgo: 20, hour: 17, minute: 30, kilometersPerHour: 11.0),
        RouteEntry(trackName: "BUCK HILL",     activityType: .hiking,  daysAgo: 26, hour: 7,  minute: 50, kilometersPerHour: 4.1),
    ]

    static let routelessCatalog: [RoutelessEntry] = [
        RoutelessEntry(activityType: .traditionalStrengthTraining, daysAgo: 3,  hour: 7,  minute: 5,  durationMinutes: 42, kilocalories: 310),
        RoutelessEntry(activityType: .yoga,                        daysAgo: 6,  hour: 18, minute: 30, durationMinutes: 35, kilocalories: 120),
        RoutelessEntry(activityType: .swimming,                    daysAgo: 15, hour: 6,  minute: 30, durationMinutes: 40, kilocalories: 380),
    ]

    // Builds the demo workouts, most recent first. Only catalogued tracks are used:
    // the sample files also contain tiny untimed road stubs that would only add noise.
    static func makeWorkouts(from tracks: [RouteTrack]) -> [DemoWorkout] {
        var demos: [DemoWorkout] = []

        for entry in routeCatalog {
            guard let track = tracks.first(where: { $0.name.caseInsensitiveCompare(entry.trackName) == .orderedSame }) else {
                print("Demo catalog track not found in samples: \(entry.trackName)")
                continue
            }
            demos.append(makeRouteWorkout(entry: entry, track: track))
        }

        for entry in routelessCatalog {
            let start = startDate(daysAgo: entry.daysAgo, hour: entry.hour, minute: entry.minute)
            let duration = entry.durationMinutes * 60
            let workout = HKWorkout(
                activityType: entry.activityType,
                start: start,
                end: start.addingTimeInterval(duration),
                duration: duration,
                totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: entry.kilocalories),
                totalDistance: nil,
                metadata: ["source": "Simulator"]
            )
            demos.append(DemoWorkout(workout: workout, track: nil))
        }

        return demos.sorted { $0.workout.startDate > $1.workout.startDate }
    }

    // Retimes the track to the entry's date and pace and wraps it in a workout
    private static func makeRouteWorkout(entry: RouteEntry, track: RouteTrack) -> DemoWorkout {
        let distance = trackDistance(track)
        let start = startDate(daysAgo: entry.daysAgo, hour: entry.hour, minute: entry.minute)
        // Never shorter than a few minutes, even for tiny tracks
        let duration = max(distance / (entry.kilometersPerHour * 1000 / 3600), 180)
        let retimed = retime(track, start: start, duration: duration)
        let trackID = UUID()

        let workout = HKWorkout(
            activityType: entry.activityType,
            start: start,
            end: start.addingTimeInterval(duration),
            duration: duration,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: duration / 60 * kilocaloriesPerMinute(entry.activityType)),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
            metadata: [
                "source": "Simulator",
                "trackUUID": trackID.uuidString
            ]
        )
        return DemoWorkout(workout: workout, track: retimed)
    }

    private static func startDate(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func trackDistance(_ track: RouteTrack) -> Double {
        track.segments.reduce(0) { total, segment in
            total + zip(segment.locations, segment.locations.dropFirst()).reduce(0) { $0 + $1.1.distance(from: $1.0) }
        }
    }

    // Spreads the points evenly across the workout so the exported GPX and the
    // map/elevation tooling see a consistent timeline
    private static func retime(_ track: RouteTrack, start: Date, duration: TimeInterval) -> RouteTrack {
        let totalPoints = track.segments.reduce(0) { $0 + $1.locations.count }
        guard totalPoints > 1 else { return track }

        var index = 0
        let segments = track.segments.map { segment -> RouteSegment in
            let locations = segment.locations.map { location -> CLLocation in
                let timestamp = start.addingTimeInterval(duration * Double(index) / Double(totalPoints - 1))
                index += 1
                return CLLocation(
                    coordinate: location.coordinate,
                    altitude: location.altitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    verticalAccuracy: location.verticalAccuracy,
                    timestamp: timestamp
                )
            }
            return RouteSegment(locations: locations)
        }
        return RouteTrack(name: track.name, type: track.type, date: start, segments: segments)
    }

    private static func kilocaloriesPerMinute(_ activityType: HKWorkoutActivityType) -> Double {
        switch activityType {
        case .running: return 11
        case .cycling: return 9
        case .hiking: return 7
        case .walking: return 4.5
        default: return 6
        }
    }
}
#endif
