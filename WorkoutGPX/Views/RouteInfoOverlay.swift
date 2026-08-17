import SwiftUI
import HealthKit
import CoreLocation

// Floating summary card for a workout route: points/segments, times, distance and
// elevation stats with a legend for the map's colour scale
struct RouteInfoOverlay: View {
    let workout: HKWorkout
    let trackSegments: [RouteSegment]
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let totalPoints = trackSegments.reduce(0) { $0 + $1.locations.count }
            let segmentCount = trackSegments.count
            
            Text("\(totalPoints) data points in \(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Started: \(workout.startDate, style: .date) \(workout.startDate, style: .time)")
                        .font(.subheadline)
                    Text("Ended: \(workout.endDate, style: .date) \(workout.endDate, style: .time)")
                        .font(.subheadline)
                }
                
                Spacer()
                
                if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                    Text(settings.formatDistance(distance))
                        .font(.headline)
                }
            }
            
            if !trackSegments.isEmpty {
                Divider()
                
                let elevations = trackSegments.flatMap { $0.locations }.map { $0.altitude }
                
                if let minElevation = elevations.min(), let maxElevation = elevations.max() {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Elevation")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Min: \(formatElevation(minElevation))")
                                .font(.caption)
                            Text("Max: \(formatElevation(maxElevation))")
                                .font(.caption)
                            Text("Gain: \(formatElevation(calculateElevationGain(elevations)))")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        ElevationLegend(mode: settings.elevationVisualizationMode)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.85))
        .cornerRadius(12)
        .padding([.horizontal, .top])
    }
    
    private func formatElevation(_ elevation: Double) -> String {
        settings.useMetricSystem
            ? String(format: "%.0f m", elevation)
            : String(format: "%.0f ft", elevation * 3.28084)
    }
    
    private func calculateElevationGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i - 1]
            if diff > 0 { gain += diff }
        }
        return gain
    }
}

// Colour legend matching the polyline renderer in use
struct ElevationLegend: View {
    let mode: ElevationVisualizationMode
    
    private var colors: [Color] {
        switch mode {
        case .gradient:
            return [Color(red: 0, green: 0, blue: 0.8), Color(red: 0.1, green: 0.8, blue: 0.1), Color(red: 1.0, green: 0, blue: 0)]
        case .effort:
            return [Color(red: 0, green: 0.3, blue: 1.0), Color(red: 0.2, green: 0.8, blue: 0.2), Color(red: 1.0, green: 0.2, blue: 0)]
        }
    }
    
    private var labels: (top: String, bottom: String) {
        switch mode {
        case .gradient: return ("High", "Low")
        case .effort: return ("Climb", "Descent")
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            LinearGradient(gradient: Gradient(colors: colors), startPoint: .bottom, endPoint: .top)
                .frame(width: 8, height: 40)
                .cornerRadius(3)
            
            VStack(alignment: .leading) {
                Text(labels.top)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Spacer()
                Text(labels.bottom)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .frame(height: 44)
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(Color(UIColor.systemBackground).opacity(0.7))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        )
    }
}
