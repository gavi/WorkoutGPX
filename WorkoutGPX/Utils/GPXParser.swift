import Foundation
import CoreLocation
import HealthKit

struct GPXTrack {
    let name: String
    let type: String
    let date: Date
    let locations: [CLLocation]
    
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
        let sortedLocations = locations.sorted { $0.timestamp < $1.timestamp }
        
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
    
    static func loadSampleTracks() -> [GPXTrack] {
        var tracks: [GPXTrack] = []
        
        // Look for GPX files in the Samples directory
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: samplesDirPath) {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: samplesDirPath)
                for file in files where file.hasSuffix(".gpx") {
                    let fileURL = URL(fileURLWithPath: samplesDirPath + "/" + file)
                    print("Loading sample from: \(fileURL.lastPathComponent)")
                    if let track = parseGPXFile(at: fileURL) {
                        tracks.append(track)
                    }
                }
            } catch {
                print("Error reading Samples directory: \(error)")
            }
        } else {
            print("Samples directory not found in bundle path")
        }
        
        // Try to find using resource URLs
        if let samplesURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) {
            print("Found \(samplesURLs.count) gpx files via Bundle.main.urls")
            for url in samplesURLs {
                print("Loading sample from: \(url.lastPathComponent)")
                if let track = parseGPXFile(at: url) {
                    tracks.append(track)
                }
            }
        }
        
        print("Loaded \(tracks.count) sample tracks from assets")
        return tracks
    }    
    static func parseGPXFile(at url: URL) -> GPXTrack? {
        guard let xmlData = try? Data(contentsOf: url) else {
            print("Failed to read GPX file at \(url)")
            return nil
        }
        
        return parseGPXData(xmlData)
    }
    
    static func parseGPXData(_ data: Data) -> GPXTrack? {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            return delegate.track
        } else {
            print("Failed to parse GPX data")
            return nil
        }
    }
}

class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var trackName = ""
    private var trackType = ""
    private var trackDate = Date()
    private var trackPoints: [CLLocation] = []
    
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    private var isTrackSegment = false
    private var isTrackPoint = false
    
    var track: GPXTrack? {
        if trackPoints.isEmpty {
            return nil
        }
        return GPXTrack(
            name: trackName,
            type: trackType,
            date: trackDate,
            locations: trackPoints
        )
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "trkseg":
            isTrackSegment = true
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
        guard isTrackSegment else { return }
        
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
                trackName = trimmedString
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
                trackPoints.append(location)
            }
            isTrackPoint = false
        } else if elementName == "trkseg" {
            isTrackSegment = false
        }
        
        currentElement = ""
    }
}
