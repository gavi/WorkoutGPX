import Foundation
import CoreLocation
import HealthKit

// Represents a track segment with location points
struct RouteSegment {
    let locations: [CLLocation]
}

struct RouteTrack {
    var name: String
    let type: String
    let date: Date
    // Updated to support multiple track segments
    let segments: [RouteSegment]
    
    // Convenience computed property to get all locations across all segments
    var allLocations: [CLLocation] {
        return segments.flatMap { $0.locations }
    }
    
    var workoutType: HKWorkoutActivityType {
        // Check filename first for simulator samples
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("run") || lowercaseName.contains("running") {
            return .running
        } else if lowercaseName.contains("bike") || lowercaseName.contains("cycling") {
            return .cycling
        } else if lowercaseName.contains("hike") || lowercaseName.contains("hiking") {
            return .hiking
        }
        
        // Then check type field
        switch type.lowercased() {
        case "running":
            return .running
        case "cycling":
            return .cycling
        case "hiking":
            return .hiking
        default:
            // Default to running for simulator testing
            #if targetEnvironment(simulator)
                return .running
            #else
                return .other
            #endif
        }
    }
    
    var workout: HKWorkout {
        // Create a workout representation for the GPX track
        // Use sorted locations to ensure start and end dates are correct
        let allLocations = self.allLocations
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        // Make sure we have valid dates (start date must be before end date)
        var startDate = sortedLocations.first?.timestamp ?? date
        var endDate = sortedLocations.last?.timestamp ?? date.addingTimeInterval(3600)
        
        // Ensure end date is after start date
        if endDate <= startDate {
            // If timestamps are invalid, use the current date with a 1-hour duration
            startDate = Date()
            endDate = startDate.addingTimeInterval(3600)
        }
        
        return HKWorkout(
            activityType: workoutType,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: [
                "name": name,
                "source": "GPX Sample"
            ]
        )
    }
}

class GPXParser {
    
    // Every track in every bundled sample GPX file (the files are multi-track
    // Garmin exports, so one file can contribute several routes)
    static func loadSampleTracks() -> [RouteTrack] {
        let fileManager = FileManager.default
        var sampleURLs: [URL] = []
        
        // Bundled as a folder reference ("Samples/") or as loose resources
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        if fileManager.fileExists(atPath: samplesDirPath),
           let files = try? fileManager.contentsOfDirectory(atPath: samplesDirPath) {
            sampleURLs = files
                .filter { $0.hasSuffix(".gpx") }
                .map { URL(fileURLWithPath: samplesDirPath + "/" + $0) }
        }
        if sampleURLs.isEmpty {
            sampleURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) ?? []
        }
        
        let tracks = sampleURLs
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { parseGPXFile(at: $0) }
        print("Loaded \(tracks.count) sample tracks from \(sampleURLs.count) GPX files")
        return tracks
    }
    
    static func parseGPXFile(at url: URL) -> [RouteTrack] {
        guard let xmlData = try? Data(contentsOf: url) else {
            print("Failed to read GPX file at \(url)")
            return []
        }
        
        // Unnamed tracks fall back to the filename without extension
        let filename = url.deletingPathExtension().lastPathComponent
        return parseGPXData(xmlData).map { track in
            var named = track
            if named.name.isEmpty {
                named.name = filename
            }
            return named
        }
    }
    
    static func parseGPXData(_ data: Data) -> [RouteTrack] {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        guard parser.parse() else {
            print("Failed to parse GPX data")
            return []
        }
        return delegate.tracks
    }
}

class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var trackName = ""
    private var trackType = ""
    private var trackDate = Date()
    
    // Track the current track, segment, and point
    private var isTrack = false
    private var isTrackSegment = false
    private var isTrackPoint = false
    
    // Data for the current point
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    // Segments of the track being parsed, and every finished track with points
    private var currentSegmentPoints: [CLLocation] = []
    private var segments: [RouteSegment] = []
    private(set) var tracks: [RouteTrack] = []
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "trk":
            isTrack = true
            // Each <trk> becomes its own RouteTrack
            trackName = ""
            segments = []
            
        case "trkseg":
            isTrackSegment = true
            // Reset current segment points
            currentSegmentPoints = []
            
        case "trkpt":
            isTrackPoint = true
            currentLat = Double(attributeDict["lat"] ?? "0")
            currentLon = Double(attributeDict["lon"] ?? "0")
            currentEle = nil
            currentTime = nil
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        if isTrackPoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                let formatter = ISO8601DateFormatter()
                currentTime = formatter.date(from: trimmedString)
            default:
                break
            }
        } else {
            switch currentElement {
            case "name":
                // Only set track name if we're in a track element
                if isTrack {
                    trackName = trimmedString
                }
            case "type":
                trackType = trimmedString
            case "time":
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: trimmedString) {
                    trackDate = date
                }
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "trkpt" && isTrackPoint {
            if let lat = currentLat, let lon = currentLon {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: currentEle ?? 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: 10,
                    timestamp: currentTime ?? Date()
                )
                currentSegmentPoints.append(location)
            }
            isTrackPoint = false
        } else if elementName == "trkseg" {
            // End of segment - add it to the list of segments
            let segment = RouteSegment(locations: currentSegmentPoints)
            segments.append(segment)
            isTrackSegment = false
        } else if elementName == "trk" {
            // Keep the track only if it carries at least one point
            if segments.contains(where: { !$0.locations.isEmpty }) {
                tracks.append(RouteTrack(name: trackName, type: trackType, date: trackDate, segments: segments))
            }
            isTrack = false
        }
        
        currentElement = ""
    }
}
