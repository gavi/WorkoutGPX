import SwiftUI
import HealthKit
import CoreLocation
import MapKit

// Detail view for a single workout with map preview and export functionality
struct WorkoutDetailView: View {
    let workout: HKWorkout
    let healthStore: HealthStore
    @EnvironmentObject var settings: SettingsModel
    
    @State private var isLoading = false
    @State private var trackSegments: [GPXTrackSegment] = []
    @State private var exportError: String?
    @State private var gpxURL: URL?
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading route data...")
            } else if let exportError = exportError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Error: \(exportError)")
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Try Again") {
                        loadRouteData()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else if trackSegments.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No route data available")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("This workout doesn't contain GPS data that can be exported")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else {
                // Full screen map with multiple segments
                MapView(trackSegments: trackSegments)
                    .environmentObject(settings)
                    .ignoresSafeArea(edges: .bottom)
                
                VStack {
                    // Floating workout info section with transparency
                    VStack(alignment: .leading, spacing: 8) {
                        // Calculate total points across all segments
                        let totalPoints = trackSegments.reduce(0) { $0 + $1.locations.count }
                        let segmentCount = trackSegments.count
                        
                        Text("Route with \(totalPoints) data points in \(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
                            .font(.headline)
                        
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
                        
                        // Add elevation data
                        if !trackSegments.isEmpty {
                            Divider()
                            
                            // Combine all locations to calculate overall elevation stats
                            let allLocations = trackSegments.flatMap { $0.locations }
                            let elevations = allLocations.map { $0.altitude }
                            
                            if let minElevation = elevations.min(), 
                               let maxElevation = elevations.max() {
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
                                    
                                    // Elevation color legend
                                    HStack(spacing: 8) {
                                        // Gradient color bar
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0, green: 0.3, blue: 1.0),  // Low - Blue
                                                Color(red: 0, green: 1.0, blue: 0.0),  // Medium - Green
                                                Color(red: 1.0, green: 0.2, blue: 0.0)   // High - Red
                                            ]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                        .frame(width: 8, height: 40)
                                        .cornerRadius(3)
                                        
                                        // Labels next to the gradient
                                        VStack(alignment: .leading) {
                                            Text("High")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Text("Low")
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
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground).opacity(0.8))
                    .cornerRadius(12)
                    .padding([.horizontal, .top])
                    
                    Spacer()
                }
            }
        }
        .navigationTitle(workoutActivityTypeString(workout.workoutActivityType))
        .navigationBarItems(trailing:
            Button(action: {
                // Always export fresh GPX file before sharing
                if let url = exportGPX(for: workout, trackSegments: trackSegments) {
                    shareFile(url: url)
                }
            }) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(trackSegments.isEmpty || isLoading)
        )
        .onAppear {
            loadRouteData()
        }
    }
    
    private func loadRouteData() {
        isLoading = true
        exportError = nil
        trackSegments = []
        
        healthStore.fetchRouteData(for: workout) { segments, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    exportError = error.localizedDescription
                    return
                }
                
                trackSegments = segments ?? []
                
                if trackSegments.isEmpty {
                    exportError = "No route data found for this workout"
                    return
                }
            }
        }
    }
    
    // Direct UIKit sharing method to avoid SwiftUI sheet issues
    private func shareFile(url: URL) {
        // Get the current window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // Find the topmost presented view controller
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        // Create and present the activity view controller
        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = topController.view
            popoverController.sourceRect = CGRect(x: topController.view.bounds.midX,
                                                 y: topController.view.bounds.midY,
                                                 width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        topController.present(activityViewController, animated: true)
    }
    
    // Format elevation in meters or feet based on user settings
    private func formatElevation(_ elevation: Double) -> String {
        if settings.useMetricSystem {
            // Meters
            return String(format: "%.0f m", elevation)
        } else {
            // Feet (1 meter = 3.28084 feet)
            let feet = elevation * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    // Calculate total elevation gain from a series of elevation points
    private func calculateElevationGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        
        var totalGain: Double = 0
        
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i-1]
            if diff > 0 {
                totalGain += diff
            }
        }
        
        return totalGain
    }
}