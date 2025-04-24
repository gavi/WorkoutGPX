import Foundation
import HealthKit
import CoreLocation
import SwiftUI

func generateGPX(for workout: HKWorkout, routeData: [CLLocation]) -> String {
    var gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" 
        creator="WorkoutGPX"
        xmlns="http://www.topografix.com/GPX/1/1"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
        <metadata>
            <time>\(ISO8601DateFormatter().string(from: workout.startDate))</time>
            <n>\(workoutActivityTypeString(workout.workoutActivityType))</n>
        </metadata>
        <trk>
            <n>\(workoutActivityTypeString(workout.workoutActivityType)) \(workout.startDate)</n>
            <trkseg>
    """
    
    for location in routeData {
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
        </trk>
    </gpx>
    """
    
    return gpx
}

func exportGPX(for workout: HKWorkout, routeData: [CLLocation]) -> URL? {
    let gpxString = generateGPX(for: workout, routeData: routeData)
    
    do {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: workout.startDate)
        
        // Get the settings to include unit system in filename
        let useMetric = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? true
        let unitSystem = useMetric ? "km" : "mi"
        
        let activityType = workoutActivityTypeString(workout.workoutActivityType)
        let filename = "\(activityType)_\(dateString)_\(unitSystem).gpx"
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    } catch {
        print("Failed to save GPX file: \(error.localizedDescription)")
        return nil
    }
}

