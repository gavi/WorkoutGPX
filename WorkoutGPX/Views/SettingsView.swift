import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    // Human-readable label for the chart density slider
    private var densityLabel: String {
        let value = settings.chartDataDensity
        if value <= 0.0 { return "Lowest" }
        if value <= 0.3 { return "Low" }
        if value <= 0.6 { return "Medium" }
        if value <= 0.9 { return "High" }
        return "Maximum"
    }
    
    var body: some View {
        Form {
            Section(header: Text("Units")) {
                Toggle("Use Metric System (km)", isOn: $settings.useMetricSystem)
            }
            
            Section(header: Text("Map")) {
                Picker("Map Style", selection: $settings.mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Track Line Width: \(Int(settings.trackLineWidth))")
                    Slider(value: $settings.trackLineWidth, in: 2...10, step: 1) {
                        Text("Track Line Width")
                    } minimumValueLabel: {
                        Text("2").font(.caption)
                    } maximumValueLabel: {
                        Text("10").font(.caption)
                    }
                }
            }
            
            Section(
                header: Text("Elevation"),
                footer: Text(settings.elevationVisualizationMode.description)
            ) {
                Picker("Route Coloring", selection: $settings.elevationVisualizationMode) {
                    ForEach(ElevationVisualizationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Toggle("Show Elevation Chart by Default", isOn: $settings.defaultShowElevationOverlay)
                Toggle("Show Route Info by Default", isOn: $settings.defaultShowRouteInfoOverlay)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chart Detail: \(densityLabel)")
                    Slider(value: $settings.chartDataDensity, in: 0...1, step: 0.1) {
                        Text("Chart Detail")
                    } minimumValueLabel: {
                        Text("Low").font(.caption)
                    } maximumValueLabel: {
                        Text("High").font(.caption)
                    }
                    Text("More detail shows every point in the elevation chart; less is faster on very long routes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(
                header: Text("GPX Export"),
                footer: Text("Adds heart rate, cadence and power from Health to each track point using the Garmin TrackPointExtension, which Strava, Garmin Connect and Komoot understand.")
            ) {
                Toggle("Include Sensor Data", isOn: $settings.includeSensorData)
            }
            
            Section(header: Text("Privacy")) {
                Text("All processing happens on this device. WorkoutGPX reads Health data only to build the files you export and never connects to the network.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}