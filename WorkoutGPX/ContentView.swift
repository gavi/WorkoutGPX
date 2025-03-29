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
            VStack {
                if isLoading {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading workouts...")
                        
                        if !healthStore.authorized {
                            VStack {
                                Text("Health access not authorized")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Button("Request Authorization") {
                                    Task {
                                        await healthStore.requestAuthorization()
                                    }
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding()
                        }
                    }
                } else if !healthStore.authorized {
                    // Unauthorized state (after loading)
                    VStack(spacing: 20) {
                        Image(systemName: "xmark.shield")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        
                        Text("Health access not authorized")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Button("Request Authorization") {
                            Task {
                                await healthStore.requestAuthorization()
                            }
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding()
                } else {
                    // Authorized state (after loading)
                    
                    // Filter section
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
                        }
                        .padding()
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
                    await healthStore.requestAuthorization()
                    isLoading = false
                }
            }
        }.onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    await refreshWorkouts()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    @MainActor
    private func refreshWorkouts() async {
        isLoading = true
        await healthStore.fetchWorkouts(
            startDate: startDate,
            endDate: endDate,
            workoutTypes: selectedWorkoutTypes
        )
        isLoading = false
    }
}