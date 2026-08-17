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
    @State private var isExporting = false
    @State private var trackSegments: [RouteSegment] = []
    @State private var exportError: String?
    @State private var gpxURL: URL?
    
    // Viewer state
    @State private var isElevationOverlayVisible = true
    @State private var isRouteInfoOverlayVisible = true
    @State private var chartHoverPointIndex: Int? = nil   // route point selected in the chart
    @State private var fitToRoute = false                 // one-shot trigger to re-fit the map
    
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
                // Full screen map with route overlays
                MapView(
                    trackSegments: trackSegments,
                    spanAll: fitToRoute,
                    hoveredPointIndex: chartHoverPointIndex
                )
                .environmentObject(settings)
                .ignoresSafeArea(edges: .bottom)
                .onChange(of: fitToRoute) { newValue in
                    // Reset the one-shot trigger once the map has consumed it
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            fitToRoute = false
                        }
                    }
                }
                
                VStack {
                    if isRouteInfoOverlayVisible {
                        RouteInfoOverlay(workout: workout, trackSegments: trackSegments)
                            .environmentObject(settings)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    if isElevationOverlayVisible {
                        ElevationOverlay(
                            trackSegments: trackSegments,
                            selectedPointIndex: $chartHoverPointIndex
                        )
                        .environmentObject(settings)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isRouteInfoOverlayVisible)
                .animation(.easeInOut(duration: 0.2), value: isElevationOverlayVisible)
            }
        }
        .navigationTitle(workoutActivityTypeString(workout.workoutActivityType))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // View options: overlays, fit, map style
                Menu {
                    Toggle(isOn: $isElevationOverlayVisible) {
                        Label("Elevation Profile", systemImage: "mountain.2")
                    }
                    Toggle(isOn: $isRouteInfoOverlayVisible) {
                        Label("Route Info", systemImage: "info.circle")
                    }
                    
                    Button {
                        chartHoverPointIndex = nil
                        fitToRoute = true
                    } label: {
                        Label("Fit to Route", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    
                    Picker("Map Style", selection: $settings.mapStyle) {
                        ForEach(MapStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.iconName).tag(style)
                        }
                    }
                    
                    Picker("Route Coloring", selection: $settings.elevationVisualizationMode) {
                        ForEach(ElevationVisualizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(trackSegments.isEmpty || isLoading)
                
                Button(action: {
                    Task { await exportAndShare() }
                }) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(trackSegments.isEmpty || isLoading || isExporting)
            }
        }
        .onAppear {
            isElevationOverlayVisible = settings.defaultShowElevationOverlay
            isRouteInfoOverlayVisible = settings.defaultShowRouteInfoOverlay
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
    
    // Builds a fresh GPX file (with sensor data when enabled) and presents the share sheet
    @MainActor
    private func exportAndShare() async {
        isExporting = true
        defer { isExporting = false }
        
        let options = GPXExportOptions(
            useMetricSystem: settings.useMetricSystem,
            includeSensorData: settings.includeSensorData
        )
        
        let sensorData = options.includeSensorData
            ? await healthStore.fetchSensorData(for: workout)
            : WorkoutSensorData()
        
        if let url = exportGPX(for: workout, trackSegments: trackSegments, sensorData: sensorData, options: options) {
            shareFile(url: url)
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
