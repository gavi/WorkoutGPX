import Foundation
import HealthKit
import CoreLocation
import SwiftUI

func generateGPX(for workout: HKWorkout, trackSegments: [GPXTrackSegment]) -> String {
    var gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" 
        creator="WorkoutGPX"
        xmlns="http://www.topografix.com/GPX/1/1"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
        <metadata>
            <time>\(ISO8601DateFormatter().string(from: workout.startDate))</time>
            <name>\(workoutActivityTypeString(workout.workoutActivityType))</name>
        </metadata>
        <trk>
            <name>\(workoutActivityTypeString(workout.workoutActivityType)) \(workout.startDate)</name>
    """
    
    // Add each segment separately
    for (index, segment) in trackSegments.enumerated() {
        gpx += """
            <trkseg>
        """
        
        for location in segment.locations {
            let timeString = ISO8601DateFormatter().string(from: location.timestamp)
            gpx += """
                    <trkpt lat="\(location.coordinate.latitude)" lon="\(location.coordinate.longitude)">
                        <ele>\(location.altitude)</ele>
                        <time>\(timeString)</time>
                    </trkpt>
            """
        }
        
        gpx += """
            </trkseg>
        """
    }
    
    gpx += """
        </trk>
    </gpx>
    """
    
    return gpx
}

// For backward compatibility - creates a single segment from locations
func generateGPX(for workout: HKWorkout, routeData: [CLLocation]) -> String {
    return generateGPX(for: workout, trackSegments: [GPXTrackSegment(locations: routeData)])
}

func exportGPX(for workout: HKWorkout, trackSegments: [GPXTrackSegment]) -> URL? {
    let gpxString = generateGPX(for: workout, trackSegments: trackSegments)
    
    do {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: workout.startDate)
        
        // Get the settings to include unit system in filename
        let useMetric = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? true
        let unitSystem = useMetric ? "km" : "mi"
        
        let activityType = workoutActivityTypeString(workout.workoutActivityType)
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

// For backward compatibility
func exportGPX(for workout: HKWorkout, routeData: [CLLocation]) -> URL? {
    return exportGPX(for: workout, trackSegments: [GPXTrackSegment(locations: routeData)])
}

