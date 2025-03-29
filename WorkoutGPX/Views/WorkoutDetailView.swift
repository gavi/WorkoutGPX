import SwiftUI
import HealthKit
import CoreLocation
import MapKit

// Detail view for a single workout with map preview and export functionality
struct WorkoutDetailView: View {
    let workout: HKWorkout
    let healthStore: HealthStore
    
    @State private var isLoading = false
    @State private var routeData: [CLLocation] = []
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
            } else if routeData.isEmpty {
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
                // Full screen map
                MapView(routeLocations: routeData)
                    .ignoresSafeArea(edges: .bottom)
                
                VStack {
                    // Floating workout info section with transparency
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route with \(routeData.count) data points")
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
                                Text(String(format: "%.2f km", distance / 1000))
                                    .font(.headline)
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
                if let url = exportGPX(for: workout, routeData: routeData) {
                    shareFile(url: url)
                }
            }) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(routeData.isEmpty || isLoading)
        )
        .onAppear {
            loadRouteData()
        }
    }
    
    private func loadRouteData() {
        isLoading = true
        exportError = nil
        routeData = []
        
        healthStore.fetchRouteData(for: workout) { locations, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    exportError = error.localizedDescription
                    return
                }
                
                routeData = locations ?? []
                
                if routeData.isEmpty {
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
}