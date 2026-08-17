import Foundation
import SwiftUI
import MapKit

enum MapStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe"
        case .hybrid: return "map.fill"
        }
    }
    
    var mapConfiguration: MKMapConfiguration {
        switch self {
        case .standard: return MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        case .satellite: return MKImageryMapConfiguration()
        case .hybrid: return MKHybridMapConfiguration()
        }
    }
    
    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

// How the route polyline is coloured on the map
enum ElevationVisualizationMode: String, CaseIterable, Identifiable {
    case effort = "Effort"     // Grade-based: steep climbs red, descents blue
    case gradient = "Gradient" // Absolute elevation: low blue → high red
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .effort:
            return "Colors based on combined effort (grade and distance)"
        case .gradient:
            return "Colors based purely on elevation gradient"
        }
    }
}

class SettingsModel: ObservableObject {
    @Published var useMetricSystem: Bool {
        didSet {
            UserDefaults.standard.set(useMetricSystem, forKey: "useMetricSystem")
        }
    }
    
    @Published var mapStyle: MapStyle {
        didSet {
            UserDefaults.standard.set(mapStyle.rawValue, forKey: "mapStyle")
        }
    }
    
    // Whether exported GPX files carry heart rate, cadence and power alongside the route
    @Published var includeSensorData: Bool {
        didSet {
            UserDefaults.standard.set(includeSensorData, forKey: "includeSensorData")
        }
    }
    
    // MARK: Route viewer
    
    @Published var elevationVisualizationMode: ElevationVisualizationMode {
        didSet {
            UserDefaults.standard.set(elevationVisualizationMode.rawValue, forKey: "elevationVisualizationMode")
        }
    }
    
    // Track line width in points (2…10)
    @Published var trackLineWidth: Double {
        didSet {
            UserDefaults.standard.set(trackLineWidth, forKey: "trackLineWidth")
        }
    }
    
    @Published var defaultShowElevationOverlay: Bool {
        didSet {
            UserDefaults.standard.set(defaultShowElevationOverlay, forKey: "defaultShowElevationOverlay")
        }
    }
    
    @Published var defaultShowRouteInfoOverlay: Bool {
        didSet {
            UserDefaults.standard.set(defaultShowRouteInfoOverlay, forKey: "defaultShowRouteInfoOverlay")
        }
    }
    
    // 0 = fewest chart points (fast), 1 = every point
    @Published var chartDataDensity: Double {
        didSet {
            UserDefaults.standard.set(chartDataDensity, forKey: "chartDataDensity")
        }
    }
    
    // Stride used when sampling elevation chart data: 1 at full density, up to 10 at the lowest
    var chartDataStride: Int {
        if chartDataDensity >= 1.0 {
            return 1
        }
        let maxStride = 10
        return max(1, Int((1.0 - chartDataDensity) * Double(maxStride - 1) + 1))
    }
    
    init() {
        self.useMetricSystem = UserDefaults.standard.bool(forKey: "useMetricSystem", defaultValue: true)
        self.includeSensorData = UserDefaults.standard.bool(forKey: "includeSensorData", defaultValue: true)
        
        if let savedMode = UserDefaults.standard.string(forKey: "elevationVisualizationMode"),
           let mode = ElevationVisualizationMode(rawValue: savedMode) {
            self.elevationVisualizationMode = mode
        } else {
            self.elevationVisualizationMode = .effort
        }
        
        let lineWidth = UserDefaults.standard.double(forKey: "trackLineWidth")
        self.trackLineWidth = (2...10).contains(lineWidth) ? lineWidth : 4
        
        self.defaultShowElevationOverlay = UserDefaults.standard.bool(forKey: "defaultShowElevationOverlay", defaultValue: true)
        self.defaultShowRouteInfoOverlay = UserDefaults.standard.bool(forKey: "defaultShowRouteInfoOverlay", defaultValue: true)
        
        let density = UserDefaults.standard.double(forKey: "chartDataDensity")
        self.chartDataDensity = (UserDefaults.standard.object(forKey: "chartDataDensity") != nil && (0...1).contains(density)) ? density : 0.5
        
        if let savedMapStyle = UserDefaults.standard.string(forKey: "mapStyle"),
           let style = MapStyle(rawValue: savedMapStyle) {
            self.mapStyle = style
        } else {
            self.mapStyle = .standard
        }
    }
    
    func formatDistance(_ distanceInMeters: Double) -> String {
        if useMetricSystem {
            let kilometers = distanceInMeters / 1000
            return String(format: "%.2f km", kilometers)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.2f mi", miles)
        }
    }
}

extension UserDefaults {
    func bool(forKey defaultName: String, defaultValue: Bool) -> Bool {
        if object(forKey: defaultName) == nil {
            set(defaultValue, forKey: defaultName)
            return defaultValue
        }
        return bool(forKey: defaultName)
    }
}
