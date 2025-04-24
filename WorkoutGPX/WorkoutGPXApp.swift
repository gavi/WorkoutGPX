//
//  WorkoutGPXApp.swift
//  WorkoutGPX
//
//  Created by Gavi Narra on 3/27/25.
//

import SwiftUI

@main
struct WorkoutGPXApp: App {
    @StateObject private var settings = SettingsModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
