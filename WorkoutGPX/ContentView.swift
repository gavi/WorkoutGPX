import SwiftUI
import HealthKit

// Main content view
struct ContentView: View {
    @StateObject private var healthStore = HealthStore()
    @State private var showFilters = false
    @State private var selectedWorkoutTypes: Set<HKWorkoutActivityType> = [.running, .walking, .hiking, .cycling]
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isLoading = true
    @Environment(\.scenePhase) private var scenePhase

    var filteredWorkouts: [HKWorkout] {
        healthStore.workouts.filter { workout in
            let matchesType = selectedWorkoutTypes.contains(workout.workoutActivityType)
            let isInDateRange = (workout.startDate >= startDate && workout.startDate <= endDate)
            return matchesType && isInDateRange
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading workouts...")
                    }
                    .frame(maxHeight: .infinity)
                } else if !healthStore.authorized {
                    // Unauthorized state (after loading)
                    VStack(spacing: 20) {
                        Image(systemName: "xmark.shield")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        
                        Text("Health access not authorized")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text("This app needs access to your Health data to export workout information.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Button("Request Health Permission") {
                                Task {
                                    await healthStore.requestAuthorization()
                                    // Force UI update
                                    isLoading = true
                                    try? await Task.sleep(nanoseconds: 500_000_000) // Half second delay
                                    isLoading = false
                                }
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            
                            Button("Open Health Settings") {
                                openAppSettings()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                } else {
                    // Authorized state (after loading)
                    
                    // Filter section always at the top
                    VStack(spacing: 4) {
                        WorkoutFilterView(
                            selectedWorkoutTypes: $selectedWorkoutTypes,
                            startDate: $startDate,
                            endDate: $endDate,
                            showFilters: $showFilters,
                            refreshWorkouts: refreshWorkouts
                        )
                        .padding(.horizontal)
                        
                        Text("\(filteredWorkouts.count) workouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Content section 
                    if filteredWorkouts.isEmpty {
                        // Empty state
                        VStack(spacing: 20) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No workouts found")
                                .font(.headline)
                            
                            Text("Try adjusting your filters or timeframe")
                                .foregroundColor(.secondary)
                                
                            // Small link to check permissions
                            Button("Check Health permissions") {
                                openAppSettings()
                            }
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                        }
                        .padding()
                        .frame(maxHeight: .infinity)
                    } else {
                        // Workout list
                        List {
                            ForEach(filteredWorkouts, id: \.uuid) { workout in
                                NavigationLink(destination: WorkoutDetailView(workout: workout, healthStore: healthStore)) {
                                    WorkoutRow(workout: workout)
                                }
                            }
                        }
                        .refreshable {
                            await refreshWorkouts()
                        }
                    }
                }
            }
            .navigationTitle("Workout GPX Exporter")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showFilters.toggle()
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")")
                    }
                    .disabled(isLoading || !healthStore.authorized)
                }
            }
            .onAppear {
                Task {
                    // Initialize with a clean state
                    isLoading = true
                    
                    // Request authorization and check access
                    await healthStore.requestAuthorization()
                    
                    // Only fetch workouts if authorized
                    if healthStore.authorized {
                        await healthStore.fetchWorkouts(
                            startDate: startDate,
                            endDate: endDate,
                            workoutTypes: selectedWorkoutTypes
                        )
                    }
                    
                    // Finish loading
                    isLoading = false
                }
            }
        }.onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    // Re-check authorization every time the app becomes active
                    await healthStore.requestAuthorization()
                    
                    // Update end date to current time when app becomes active
                    endDate = Date()
                    
                    // Only refresh workouts if authorized
                    if healthStore.authorized {
                        await refreshWorkouts()
                    } else {
                        // Ensure loading is complete
                        isLoading = false
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    @MainActor
    private func refreshWorkouts() async {
        isLoading = true
        
        // Update endDate to current time when refreshing
        endDate = Date()
        
        // First verify authorization status
        await healthStore.requestAuthorization()
        
        // Only fetch if authorized
        if healthStore.authorized {
            await healthStore.fetchWorkouts(
                startDate: startDate,
                endDate: endDate,
                workoutTypes: selectedWorkoutTypes
            )
        }
        
        isLoading = false
    }
    
    // Function to open the app settings
    private func openAppSettings() {
        UIApplication.shared.open(URL(string: "App-Prefs:Privacy&path=HEALTH")!, completionHandler: { (success) in
                    print("Settings opened: \(success)")
                })
    }
}
