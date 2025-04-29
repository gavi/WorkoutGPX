import SwiftUI
import HealthKit

// Workout filter view
struct WorkoutFilterView: View {
    @Binding var selectedWorkoutTypes: Set<HKWorkoutActivityType>
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var showFilters: Bool
    var applyFilters: () async -> Void
    
    private let workoutTypes: [(HKWorkoutActivityType, String, String)] = [
        (.running, "Running", "figure.run"),
        (.walking, "Walking", "figure.walk"),
        (.hiking, "Hiking", "mountain.2"),
        (.cycling, "Cycling", "figure.outdoor.cycle")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showFilters {
                Text("Filter Workouts")
                    .font(.headline)
                
                // Workout type selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout Types")
                        .font(.subheadline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(workoutTypes, id: \.0) { type, name, icon in
                                Button(action: {
                                    toggleWorkoutType(type)
                                }) {
                                    VStack {
                                        Image(systemName: icon)
                                            .font(.system(size: 20))
                                        Text(name)
                                            .font(.caption)
                                    }
                                    .frame(width: 70, height: 60)
                                    .background(selectedWorkoutTypes.contains(type) ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    .foregroundColor(selectedWorkoutTypes.contains(type) ? .blue : .primary)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedWorkoutTypes.contains(type) ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                                }
                            }
                        }
                    }
                }
                
                // Date range selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date Range")
                        .font(.subheadline)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start Date")
                                .font(.caption)
                            DatePicker("", selection: $startDate, displayedComponents: [.date])
                                .labelsHidden()
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading) {
                            Text("End Date")
                                .font(.caption)
                            DatePicker("", selection: $endDate, displayedComponents: [.date])
                                .labelsHidden()
                        }
                    }
                    
                    // Quick date presets
                    HStack {
                        QuickDateButton(title: "Last Week", action: {
                            setLastWeek()
                        })
                        
                        QuickDateButton(title: "Last Month", action: {
                            setLastMonth()
                        })
                        
                        QuickDateButton(title: "Last 3 Months", action: {
                            setLastThreeMonths()
                        })
                        
                        QuickDateButton(title: "Last Year", action: {
                            setLastYear()
                        })
                    }
                    
                    // Apply filters button
                    Button(action: {
                        Task {
                            await applyFilters()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Apply Filters")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.top)
                }
            }
        }
    }
    
    private func toggleWorkoutType(_ type: HKWorkoutActivityType) {
        if selectedWorkoutTypes.contains(type) {
            // Don't allow deselecting all types
            if selectedWorkoutTypes.count > 1 {
                selectedWorkoutTypes.remove(type)
            }
        } else {
            selectedWorkoutTypes.insert(type)
        }
    }
    
    private func setLastWeek() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
    }
    
    private func setLastMonth() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
    }
    
    private func setLastThreeMonths() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate) ?? endDate
    }
    
    private func setLastYear() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .year, value: -1, to: endDate) ?? endDate
    }
}