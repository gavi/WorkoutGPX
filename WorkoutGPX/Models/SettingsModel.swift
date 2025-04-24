import Foundation
import SwiftUI

class SettingsModel: ObservableObject {
    @Published var useMetricSystem: Bool {
        didSet {
            UserDefaults.standard.set(useMetricSystem, forKey: "useMetricSystem")
        }
    }
    
    init() {
        self.useMetricSystem = UserDefaults.standard.bool(forKey: "useMetricSystem", defaultValue: true)
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