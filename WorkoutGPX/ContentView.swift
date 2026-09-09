import SwiftUI
import HealthKit

// Main content view
struct ContentView: View {
    @StateObject private var healthStore = HealthStore()
    @State private var showFilters = false
    
    // Activity types to show; an empty set means "All"
    @State private var selectedWorkoutTypes: Set<HKWorkoutActivityType> = []
    // Workouts without route data (indoor, strength, yoga…) have nothing to export,
    // so they are hidden unless the user asks to see them
    @State private var showWorkoutsWithoutRoutes = false
    
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isLoading = true
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settings: SettingsModel
    
    // Multi-select export: the list enters edit mode, the user ticks workouts,
    // and one share sheet carries every GPX file
    @State private var editMode: EditMode = .inactive
    @State private var selectedWorkoutIDs: Set<UUID> = []
    @StateObject private var bulkExporter = BulkExporter()
    @State private var skippedReport: BulkExportResult?
    
    // Workouts in the date range, before activity-type filtering
    private var workoutsInRange: [HKWorkout] {
        // The simulator's sample workouts are not dated realistically, so skip the date filter there
        #if targetEnvironment(simulator)
            return healthStore.workouts
        #else
            return healthStore.workouts.filter { workout in
                workout.startDate >= startDate && workout.startDate <= endDate
            }
        #endif
    }
    
    // Workouts in range that have GPS data (or all of them, when the user opts in)
    private var exportableWorkouts: [HKWorkout] {
        guard !showWorkoutsWithoutRoutes else { return workoutsInRange }
        return workoutsInRange.filter { healthStore.workoutsWithRoutes.contains($0.uuid) }
    }
    
    // How many workouts in range are currently hidden for lacking route data
    private var hiddenWithoutRouteCount: Int {
        showWorkoutsWithoutRoutes ? 0 : workoutsInRange.count - exportableWorkouts.count
    }
    
    // Exportable workouts narrowed by the selected activity types.
    // Type filtering happens in memory so the chips reflect everything in the range.
    var filteredWorkouts: [HKWorkout] {
        guard !selectedWorkoutTypes.isEmpty else { return exportableWorkouts }
        return exportableWorkouts.filter { selectedWorkoutTypes.contains($0.workoutActivityType) }
    }
    
    // Activity types present in the exportable set with their counts, most common first
    var availableWorkoutTypes: [WorkoutTypeCount] {
        var counts: [HKWorkoutActivityType: Int] = [:]
        for workout in exportableWorkouts {
            counts[workout.workoutActivityType, default: 0] += 1
        }
        return counts
            .map { WorkoutTypeCount(type: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return workoutActivityTypeString($0.type) < workoutActivityTypeString($1.type)
            }
    }
    
    private var isSelecting: Bool { editMode == .active }
    
    // Selected workouts that are still visible under the current filters
    private var selectedWorkouts: [HKWorkout] {
        filteredWorkouts.filter { selectedWorkoutIDs.contains($0.uuid) }
    }
    
    private var allVisibleSelected: Bool {
        !filteredWorkouts.isEmpty && selectedWorkouts.count == filteredWorkouts.count
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
                            availableWorkoutTypes: availableWorkoutTypes,
                            showWorkoutsWithoutRoutes: $showWorkoutsWithoutRoutes,
                            hiddenWithoutRouteCount: hiddenWithoutRouteCount,
                            startDate: $startDate,
                            endDate: $endDate,
                            showFilters: $showFilters,
                            applyFilters: applyFilters
                        )
                        .padding(.horizontal)
                        
                        // Never hide data silently: say how many were left out and why
                        Text(isSelecting
                             ? "\(selectedWorkouts.count) of \(filteredWorkouts.count) selected"
                             : hiddenWithoutRouteCount > 0
                                ? "\(filteredWorkouts.count) workouts · \(hiddenWithoutRouteCount) without GPS hidden"
                                : "\(filteredWorkouts.count) workouts")
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
                        // Workout list; in edit mode a tap ticks the row instead of opening it
                        List(selection: $selectedWorkoutIDs) {
                            ForEach(filteredWorkouts, id: \.uuid) { workout in
                                NavigationLink(destination: WorkoutDetailView(workout: workout, healthStore: healthStore)) {
                                    WorkoutRow(
                                        workout: workout,
                                        hasRoute: healthStore.workoutsWithRoutes.contains(workout.uuid)
                                    )
                                }
                                .tag(workout.uuid)
                            }
                        }
                        .environment(\.editMode, $editMode)
                        .refreshable {
                            await refreshWorkouts()
                        }
                    }
                }
            }
            .navigationTitle("Workout GPX Exporter")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelecting {
                        Button(allVisibleSelected ? "Deselect All" : "Select All") {
                            toggleSelectAll()
                        }
                        .accessibilityIdentifier("select-all-button")
                    } else {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gear")
                        }
                        .accessibilityIdentifier("settings-button")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if isSelecting {
                        Button("Done") {
                            finishSelecting()
                        }
                        .accessibilityIdentifier("done-selecting-button")
                    } else {
                        Button("Select") {
                            startSelecting()
                        }
                        .accessibilityIdentifier("select-button")
                        .disabled(isLoading || !healthStore.authorized || filteredWorkouts.isEmpty)
                        
                        Button(action: {
                            showFilters.toggle()
                        }) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")")
                        }
                        .accessibilityIdentifier("filters-button")
                        .disabled(isLoading || !healthStore.authorized)
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        // A text button: bottom-bar Labels collapse to their icon, and this one is the whole point
                        Button(action: {
                            Task { await exportSelected() }
                        }) {
                            Text(selectedWorkouts.count == 1 ? "Export 1 Workout" : "Export \(selectedWorkouts.count) Workouts")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("export-selected-button")
                        .disabled(selectedWorkouts.isEmpty || bulkExporter.isRunning)
                        Spacer()
                    }
                }
            }
            .overlay {
                if bulkExporter.isRunning {
                    BulkExportProgressView(exporter: bulkExporter)
                }
            }
            .alert(
                skippedReportTitle,
                isPresented: Binding(
                    get: { skippedReport != nil },
                    set: { if !$0 { skippedReport = nil } }
                ),
                presenting: skippedReport
            ) { result in
                if !result.fileURLs.isEmpty {
                    Button(result.fileURLs.count == 1 ? "Share 1 File" : "Share \(result.fileURLs.count) Files") {
                        share(result.fileURLs)
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { result in
                Text(skippedReportMessage(for: result))
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                Task {
                    // Re-check authorization every time the app becomes active
                    await healthStore.requestAuthorization()
                    
                    // Keep the end date current only when it already points at today,
                    // so a historical date range chosen by the user survives exports
                    // (the share sheet makes the scene inactive and then active again)
                    if Calendar.current.isDateInToday(endDate) || endDate > Date() {
                        endDate = Date()
                    }
                    
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
    
    // MARK: - Multi-select export
    
    private func startSelecting() {
        selectedWorkoutIDs = []
        withAnimation { editMode = .active }
    }
    
    private func finishSelecting() {
        withAnimation { editMode = .inactive }
        selectedWorkoutIDs = []
    }
    
    private func toggleSelectAll() {
        if allVisibleSelected {
            selectedWorkoutIDs = []
        } else {
            selectedWorkoutIDs = Set(filteredWorkouts.map { $0.uuid })
        }
    }
    
    // Builds one GPX per selected workout, then opens a single share sheet with all of them.
    // Workouts without a route are skipped and reported, never silently dropped.
    @MainActor
    private func exportSelected() async {
        let workouts = selectedWorkouts
        guard !workouts.isEmpty else { return }
        
        let options = GPXExportOptions(
            useMetricSystem: settings.useMetricSystem,
            includeSensorData: settings.includeSensorData
        )
        let result = await bulkExporter.export(workouts, using: healthStore, options: options)
        
        if result.wasCancelled {
            return
        }
        if result.skipped.isEmpty {
            share(result.fileURLs)
        } else {
            skippedReport = result
        }
    }
    
    private func share(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        presentShareSheet(items: urls) { finished in
            // Leave edit mode once the files have gone somewhere; a dismissed sheet keeps the selection
            if finished {
                finishSelecting()
            }
        }
    }
    
    private var skippedReportTitle: String {
        guard let result = skippedReport else { return "" }
        return result.fileURLs.isEmpty ? "Nothing to Export" : "Some Workouts Were Skipped"
    }
    
    private func skippedReportMessage(for result: BulkExportResult) -> String {
        let exported = result.fileURLs.count
        let skipped = result.skipped.count
        var lines: [String] = []
        lines.append(exported == 0
                     ? (skipped == 1 ? "The selected workout has no GPS data." : "None of the \(skipped) selected workouts has GPS data.")
                     : "\(exported) of \(result.requested) exported. \(skipped) skipped:")
        for item in result.skipped.prefix(5) {
            lines.append("• \(workoutActivityTypeString(item.workout.workoutActivityType)), \(dateFormatter.string(from: item.workout.startDate)) — \(item.reason)")
        }
        if skipped > 5 {
            lines.append("• and \(skipped - 5) more")
        }
        return lines.joined(separator: "\n")
    }
    
    @MainActor
    private func refreshWorkouts() async {
        isLoading = true
        // First verify authorization status
        await healthStore.requestAuthorization()
        
        // Only fetch if authorized. Every activity type in the range is fetched;
        // the type chips filter in memory.
        if healthStore.authorized {
            await healthStore.fetchWorkouts(
                startDate: startDate,
                endDate: endDate
            )
        }
        
        isLoading = false
    }
    
    @MainActor
    private func applyFilters() async {
        isLoading = true
        
        // First verify authorization status
        await healthStore.requestAuthorization()
        
        // Only fetch if authorized. Every activity type in the range is fetched;
        // the type chips filter in memory.
        if healthStore.authorized {
            await healthStore.fetchWorkouts(
                startDate: startDate,
                endDate: endDate
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
