import SwiftUI
import HealthKit

// An activity type together with how many workouts of that type are in the current range
struct WorkoutTypeCount: Identifiable {
    let type: HKWorkoutActivityType
    let count: Int
    var id: UInt { type.rawValue }
}

// Workout filter view
struct WorkoutFilterView: View {
    // Selected activity types; empty means "All"
    @Binding var selectedWorkoutTypes: Set<HKWorkoutActivityType>
    // Types present in the fetched date range, most common first
    var availableWorkoutTypes: [WorkoutTypeCount]
    // Whether workouts with no route data are listed at all
    @Binding var showWorkoutsWithoutRoutes: Bool
    // How many workouts in range are currently hidden for lacking route data
    var hiddenWithoutRouteCount: Int
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var showFilters: Bool
    var applyFilters: () async -> Void
    
    // Chips to show: every type in the range, plus any selected type that has
    // dropped out of the range (so the user can still see and clear it)
    private var chipTypes: [WorkoutTypeCount] {
        let present = Set(availableWorkoutTypes.map(\.type))
        let missingSelected = selectedWorkoutTypes
            .filter { !present.contains($0) }
            .map { WorkoutTypeCount(type: $0, count: 0) }
            .sorted { workoutActivityTypeString($0.type) < workoutActivityTypeString($1.type) }
        return availableWorkoutTypes + missingSelected
    }
    
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
                            // "All" chip: selected whenever no specific type is chosen
                            WorkoutTypeChip(
                                title: "All",
                                icon: "star.circle",
                                count: availableWorkoutTypes.reduce(0) { $0 + $1.count },
                                isSelected: selectedWorkoutTypes.isEmpty
                            ) {
                                selectedWorkoutTypes.removeAll()
                            }
                            
                            // One chip per activity type present in the current range
                            ForEach(chipTypes) { entry in
                                WorkoutTypeChip(
                                    title: workoutActivityTypeString(entry.type),
                                    icon: workoutIcon(for: entry.type),
                                    count: entry.count,
                                    isSelected: selectedWorkoutTypes.contains(entry.type)
                                ) {
                                    toggleWorkoutType(entry.type)
                                }
                            }
                        }
                    }
                    
                    if availableWorkoutTypes.isEmpty {
                        Text("No workouts in this date range yet — adjust the dates and apply.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Workouts without GPS (indoor, strength, yoga…) have nothing to export
                    Toggle(isOn: $showWorkoutsWithoutRoutes) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show workouts without GPS")
                                .font(.subheadline)
                            if hiddenWithoutRouteCount > 0 {
                                Text("\(hiddenWithoutRouteCount) hidden in this range")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
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
    
    // Toggle a type in the selection; clearing the last one falls back to "All"
    private func toggleWorkoutType(_ type: HKWorkoutActivityType) {
        if selectedWorkoutTypes.contains(type) {
            selectedWorkoutTypes.remove(type)
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

// A selectable activity-type chip showing icon, name and workout count
struct WorkoutTypeChip: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 70, minHeight: 64)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
