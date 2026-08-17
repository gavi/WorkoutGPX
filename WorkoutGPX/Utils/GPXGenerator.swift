import Foundation
import HealthKit
import CoreLocation
import CoreGPX

// Options controlling what goes into an exported GPX document
struct GPXExportOptions {
    var useMetricSystem: Bool = true
    // Emit heart rate / cadence / power as Garmin TrackPointExtension + <power> elements
    var includeSensorData: Bool = true
    
    // Reads the current user preferences from UserDefaults
    static var current: GPXExportOptions {
        GPXExportOptions(
            useMetricSystem: UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? true,
            includeSensorData: UserDefaults.standard.object(forKey: "includeSensorData") as? Bool ?? true
        )
    }
}

// Namespaces for the Garmin extensions used to carry sensor data in GPX:
// TrackPointExtension v2 (heart rate, cadence, speed, course) and PowerExtension v1,
// understood by Strava, Garmin Connect, Komoot and most GPX consumers.
private enum GPXNamespaces {
    static let trackPointExtensionPrefix = "gpxtpx"
    static let trackPointExtensionURI = "http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
    static let trackPointExtensionSchema = "http://www.garmin.com/xmlschemas/TrackPointExtensionv2.xsd"
    static let powerExtensionPrefix = "gpxpx"
    static let powerExtensionURI = "http://www.garmin.com/xmlschemas/PowerExtension/v1"
    static let powerExtensionSchema = "http://www.garmin.com/xmlschemas/PowerExtensionv1.xsd"
    static let projectURL = "https://github.com/gavi/WorkoutGPX"
}

// How far (in seconds) a sensor reading may be from a track point and still be attached to it
private let sensorMatchTolerance: TimeInterval = 15

// Builds the GPX document for a workout as a CoreGPX object graph
func buildGPX(
    for workout: HKWorkout,
    trackSegments: [RouteSegment],
    sensorData: WorkoutSensorData = WorkoutSensorData(),
    options: GPXExportOptions = .current
) -> GPXRoot {
    let includeSensors = options.includeSensorData && !sensorData.isEmpty
    
    // Root with extension namespaces declared only when they are actually used
    let version = appVersionString()
    let creator = version.isEmpty ? "WorkoutGPX" : "WorkoutGPX \(version)"
    let root: GPXRoot
    if includeSensors {
        var attributes = ["xmlns:\(GPXNamespaces.trackPointExtensionPrefix)": GPXNamespaces.trackPointExtensionURI]
        var schemaLocations = ["\(GPXNamespaces.trackPointExtensionURI) \(GPXNamespaces.trackPointExtensionSchema)"]
        if !sensorData.power.isEmpty {
            attributes["xmlns:\(GPXNamespaces.powerExtensionPrefix)"] = GPXNamespaces.powerExtensionURI
            schemaLocations.append("\(GPXNamespaces.powerExtensionURI) \(GPXNamespaces.powerExtensionSchema)")
        }
        root = GPXRoot(
            withExtensionAttributes: attributes,
            schemaLocation: schemaLocations.joined(separator: " "),
            creator: creator
        )
    } else {
        root = GPXRoot(creator: creator)
    }
    
    let title = workoutTitle(for: workout)
    
    // Metadata: what this file is, when it happened, where it came from
    let metadata = GPXMetadata()
    metadata.name = title
    metadata.desc = workoutDescription(for: workout, sensorData: includeSensors ? sensorData : WorkoutSensorData(), options: options)
    metadata.time = workout.startDate
    let link = GPXLink(withHref: GPXNamespaces.projectURL)
    link.text = "WorkoutGPX"
    metadata.links = [link]
    root.metadata = metadata
    
    // Track: one per workout, one segment per HealthKit route (pauses become segment breaks)
    let track = GPXTrack()
    track.name = title
    track.type = gpxActivityTypeString(workout.workoutActivityType)
    track.desc = metadata.desc
    track.source = workoutSourceString(for: workout)
    
    for segment in trackSegments {
        let gpxSegment = GPXTrackSegment()
        gpxSegment.points.reserveCapacity(segment.locations.count)
        
        for location in segment.locations {
            let point = GPXTrackPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            if location.verticalAccuracy >= 0 {
                point.elevation = location.altitude
            }
            point.time = location.timestamp
            
            if includeSensors, let extensions = trackPointExtensions(for: location, sensorData: sensorData) {
                point.extensions = extensions
            }
            
            gpxSegment.add(trackpoint: point)
        }
        
        track.add(trackSegment: gpxSegment)
    }
    
    root.add(track: track)
    return root
}

// Serialises the workout as a GPX 1.1 string
func generateGPX(
    for workout: HKWorkout,
    trackSegments: [RouteSegment],
    sensorData: WorkoutSensorData = WorkoutSensorData(),
    options: GPXExportOptions = .current
) -> String {
    return buildGPX(for: workout, trackSegments: trackSegments, sensorData: sensorData, options: options).gpx()
}

// Writes the GPX file to the app's Documents directory and returns its URL
func exportGPX(
    for workout: HKWorkout,
    trackSegments: [RouteSegment],
    sensorData: WorkoutSensorData = WorkoutSensorData(),
    options: GPXExportOptions = .current
) -> URL? {
    let gpxString = generateGPX(for: workout, trackSegments: trackSegments, sensorData: sensorData, options: options)
    
    do {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: workout.startDate)
        
        // Keep the historical filename layout (unit suffix included) so existing users' files stay consistent
        let unitSystem = options.useMetricSystem ? "km" : "mi"
        let activityType = workoutActivityTypeString(workout.workoutActivityType)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: "-")
        let segmentCount = trackSegments.count > 1 ? "_\(trackSegments.count)segments" : ""
        let filename = "\(activityType)_\(dateString)_\(unitSystem)\(segmentCount).gpx"
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    } catch {
        print("Failed to save GPX file: \(error.localizedDescription)")
        return nil
    }
}

// MARK: - Backward compatibility (single segment from a flat location list)

func generateGPX(for workout: HKWorkout, routeData: [CLLocation]) -> String {
    return generateGPX(for: workout, trackSegments: [RouteSegment(locations: routeData)])
}

func exportGPX(for workout: HKWorkout, routeData: [CLLocation]) -> URL? {
    return exportGPX(for: workout, trackSegments: [RouteSegment(locations: routeData)])
}

// MARK: - Element builders

// Extensions for one track point. Power is written twice on purpose: as the bare
// <power> element that Strava/Zwift/RideWithGPS exchange, and as Garmin's schema-valid
// PowerExtension. Heart rate, cadence, speed and course go in a TrackPointExtension
// block whose child order follows the v2 schema sequence (hr, cad, speed, course).
private func trackPointExtensions(for location: CLLocation, sensorData: WorkoutSensorData) -> GPXExtensions? {
    let time = location.timestamp
    let prefix = GPXNamespaces.trackPointExtensionPrefix
    
    let extensions = GPXExtensions()
    
    if let watts = sensorData.power.value(at: time, tolerance: sensorMatchTolerance) {
        let wattsText = String(Int(watts.rounded()))
        
        let power = GPXExtensionsElement(name: "power")
        power.text = wattsText
        extensions.children.append(power)
        
        let powerExtension = GPXExtensionsElement(name: "\(GPXNamespaces.powerExtensionPrefix):PowerExtension")
        let powerInWatts = GPXExtensionsElement(name: "\(GPXNamespaces.powerExtensionPrefix):PowerInWatts")
        powerInWatts.text = wattsText
        powerExtension.children.append(powerInWatts)
        extensions.children.append(powerExtension)
    }
    
    let tpx = GPXExtensionsElement(name: "\(prefix):TrackPointExtension")
    
    if let bpm = sensorData.heartRate.value(at: time, tolerance: sensorMatchTolerance) {
        let hr = GPXExtensionsElement(name: "\(prefix):hr")
        hr.text = String(Int(bpm.rounded()))
        tpx.children.append(hr)
    }
    if let rpm = sensorData.cyclingCadence.value(at: time, tolerance: sensorMatchTolerance) {
        let cad = GPXExtensionsElement(name: "\(prefix):cad")
        cad.text = String(Int(rpm.rounded()))
        tpx.children.append(cad)
    }
    if location.speed >= 0 {
        let speed = GPXExtensionsElement(name: "\(prefix):speed")
        speed.text = String(format: "%.2f", location.speed)
        tpx.children.append(speed)
    }
    if location.course >= 0 {
        let course = GPXExtensionsElement(name: "\(prefix):course")
        course.text = String(format: "%.1f", location.course)
        tpx.children.append(course)
    }
    
    if !tpx.children.isEmpty {
        extensions.children.append(tpx)
    }
    
    return extensions.children.isEmpty ? nil : extensions
}

// "Running - May 1, 2024" style title used for metadata and track names.
// Kept to ASCII so CoreGPX writes plain text rather than CDATA.
private func workoutTitle(for workout: HKWorkout) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return "\(workoutActivityTypeString(workout.workoutActivityType)) - \(formatter.string(from: workout.startDate))"
}

// Human-readable summary of the workout: distance, duration, energy, elevation, sensors, weather
private func workoutDescription(for workout: HKWorkout, sensorData: WorkoutSensorData, options: GPXExportOptions) -> String {
    var parts: [String] = []
    
    if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 0 {
        parts.append("Distance " + formatDistance(meters, metric: options.useMetricSystem))
    }
    
    if let duration = durationFormatter.string(from: workout.duration) {
        parts.append("Duration \(duration)")
    }
    
    if let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), kcal > 0 {
        parts.append("Energy \(Int(kcal.rounded())) kcal")
    }
    
    if let ascended = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
        parts.append("Elevation gain " + formatElevation(ascended.doubleValue(for: .meter()), metric: options.useMetricSystem))
    }
    
    if let average = sensorData.heartRate.average {
        var hr = "Avg HR \(Int(average.rounded())) bpm"
        if let maximum = sensorData.heartRate.maximum {
            hr += " (max \(Int(maximum.rounded())))"
        }
        parts.append(hr)
    }
    
    if let average = sensorData.power.average {
        parts.append("Avg power \(Int(average.rounded())) W")
    }
    
    if let average = sensorData.cyclingCadence.average {
        parts.append("Avg cadence \(Int(average.rounded())) rpm")
    }
    
    if let temperature = workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
        let celsius = temperature.doubleValue(for: .degreeCelsius())
        parts.append(String(format: "Weather %.0f C", celsius))
    }
    
    var sentences: [String] = []
    if !parts.isEmpty {
        sentences.append(parts.joined(separator: ", ") + ".")
    }
    sentences.append("Exported from Apple Health by WorkoutGPX.")
    let source = workoutSourceString(for: workout)
    if !source.isEmpty {
        sentences.append("Recorded with \(source).")
    }
    return sentences.joined(separator: " ")
}

// e.g. "Apple Watch (Watch7,4) via Workout"
private func workoutSourceString(for workout: HKWorkout) -> String {
    let appName = workout.sourceRevision.source.name
    if let device = workout.device, let deviceName = device.name ?? device.model {
        if let hardware = device.hardwareVersion {
            return "\(deviceName) (\(hardware)) via \(appName)"
        }
        return "\(deviceName) via \(appName)"
    }
    return appName
}

private func formatDistance(_ meters: Double, metric: Bool) -> String {
    return metric
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.2f mi", meters / 1609.344)
}

private func formatElevation(_ meters: Double, metric: Bool) -> String {
    return metric
        ? String(format: "%.0f m", meters)
        : String(format: "%.0f ft", meters * 3.28084)
}

private func appVersionString() -> String {
    return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
}
