import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Units")) {
                Toggle("Use Metric System (km)", isOn: $settings.useMetricSystem)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}