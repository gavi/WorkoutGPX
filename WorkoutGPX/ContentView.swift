import SwiftUI
import HealthKit
import CoreLocation
import MapKit


// Workout filter view
struct WorkoutFilterView: View {
    @Binding var selectedWorkoutTypes: Set<HKWorkoutActivityType>
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var showFilters: Bool
    var refreshWorkouts: () async -> Void
    
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
                            await refreshWorkouts()
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

// Quick date selection button
struct QuickDateButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}

// Main content view
struct ContentView: View {
    @StateObject private var healthStore = HealthStore()
    @State private var showFilters = false
    @State private var selectedWorkoutTypes: Set<HKWorkoutActivityType> = [.running, .walking, .hiking, .cycling]
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isLoading = true
    
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
                } else {
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
                    
                    if filteredWorkouts.isEmpty {
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
                    .disabled(isLoading)
                }
            }
            .onAppear {
                Task {
                    await healthStore.requestAuthorization()
                    isLoading = false
                }
            }
        }
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

// Row showing workout information
struct WorkoutRow: View {
    let workout: HKWorkout
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: workoutIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text(workoutTitle)
                        .font(.headline)
                    Text(dateFormatter.string(from: workout.startDate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(durationFormatter.string(from: workout.duration) ?? "")
                        .font(.subheadline)
                    
                    if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                        Text(String(format: "%.2f km", distance / 1000))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
    
    private var workoutTitle: String {
        switch workout.workoutActivityType {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .hiking:
            return "Hiking"
        case .cycling:
            return "Cycling"
        default:
            return "Workout"
        }
    }
    
    private var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .hiking:
            return "mountain.2"
        case .cycling:
            return "figure.outdoor.cycle"
        default:
            return "figure.mixed.cardio"
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

// Detail view for a single workout with map preview and export functionality
struct WorkoutDetailView: View {
    let workout: HKWorkout
    let healthStore: HealthStore
    
    @State private var isLoading = false
    @State private var routeData: [CLLocation] = []
    @State private var exportError: String?
    @State private var gpxURL: URL?
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading route data...")
            } else if let exportError = exportError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Error: \(exportError)")
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Button("Try Again") {
                        loadRouteData()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else if routeData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No route data available")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("This workout doesn't contain GPS data that can be exported")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                }
            } else {
                // Full screen map
                MapView(routeLocations: routeData)
                    .ignoresSafeArea(edges: .bottom)
                
                VStack {
                    // Floating workout info section with transparency
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route with \(routeData.count) data points")
                            .font(.headline)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Started: \(workout.startDate, style: .date) \(workout.startDate, style: .time)")
                                    .font(.subheadline)
                                
                                Text("Ended: \(workout.endDate, style: .date) \(workout.endDate, style: .time)")
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                                Text(String(format: "%.2f km", distance / 1000))
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground).opacity(0.8))
                    .cornerRadius(12)
                    .padding([.horizontal, .top])
                    
                    Spacer()
                }
            }
        }
        .navigationTitle(workoutActivityTypeString(workout.workoutActivityType))
        .navigationBarItems(trailing:
            Button(action: {
                // Always export fresh GPX file before sharing
                exportGPX()
                
                // Share the file using direct UIKit approach
                if let url = gpxURL {
                    shareFile(url: url)
                }
            }) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(routeData.isEmpty || isLoading)
        )
        .onAppear {
            loadRouteData()
        }
    }
    
    private func loadRouteData() {
        isLoading = true
        exportError = nil
        routeData = []
        
        healthStore.fetchRouteData(for: workout) { locations, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    exportError = error.localizedDescription
                    return
                }
                
                routeData = locations ?? []
                
                if routeData.isEmpty {
                    exportError = "No route data found for this workout"
                    return
                }
            }
        }
    }
    
    private func exportGPX() {
        let gpxString = generateGPX()
        
        do {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = formatter.string(from: workout.startDate)
            
            let activityType = workoutActivityTypeString(workout.workoutActivityType)
            let filename = "\(activityType)_\(dateString).gpx"
            let fileURL = documentsDirectory.appendingPathComponent(filename)
            
            try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
            
            self.gpxURL = fileURL
        } catch {
            exportError = "Failed to save GPX file: \(error.localizedDescription)"
        }
    }
    
    private func generateGPX() -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" 
            creator="WorkoutGPX"
            xmlns="http://www.topografix.com/GPX/1/1"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
            <metadata>
                <time>\(ISO8601DateFormatter().string(from: workout.startDate))</time>
                <name>\(workoutActivityTypeString(workout.workoutActivityType))</name>
            </metadata>
            <trk>
                <name>\(workoutActivityTypeString(workout.workoutActivityType)) \(workout.startDate)</name>
                <trkseg>
        """
        
        for location in routeData {
            let timeString = ISO8601DateFormatter().string(from: location.timestamp)
            gpx += """
                    <trkpt lat="\(location.coordinate.latitude)" lon="\(location.coordinate.longitude)">
                        <ele>\(location.altitude)</ele>
                        <time>\(timeString)</time>
                    </trkpt>
            """
        }
        
        gpx += """
                </trkseg>
            </trk>
        </gpx>
        """
        
        return gpx
    }
    
    private func workoutActivityTypeString(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .hiking:
            return "Hiking"
        case .cycling:
            return "Cycling"
        default:
            return "Workout"
        }
    }
    
    // Direct UIKit sharing method to avoid SwiftUI sheet issues
    private func shareFile(url: URL) {
        // Get the current window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        // Find the topmost presented view controller
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        // Create and present the activity view controller
        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = topController.view
            popoverController.sourceRect = CGRect(x: topController.view.bounds.midX,
                                                 y: topController.view.bounds.midY,
                                                 width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        topController.present(activityViewController, animated: true)
    }
}

// Share sheet for sharing GPX files
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Prevent dismissal of activity view controller
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // This ensures the sharing sheet stays visible until user completes their action
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// UIViewRepresentable for MapKit
struct MapView: UIViewRepresentable {
    let routeLocations: [CLLocation]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        // Add polyline
        if !routeLocations.isEmpty {
            let coordinates = routeLocations.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
            
            // Set the visible region to show the route
            setRegion(for: mapView)
            
            // Add start and end annotations
            if let firstLocation = routeLocations.first,
               let lastLocation = routeLocations.last {
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Updates handled in makeUIView
    }
    
    private func setRegion(for mapView: MKMapView) {
        guard !routeLocations.isEmpty else { return }
        
        // Find min/max coordinates
        var minLat = routeLocations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = routeLocations[0].coordinate.longitude
        var maxLon = minLon
        
        for location in routeLocations {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }
        
        // Create region with padding
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )
        
        // Ensure minimum zoom level
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(span.latitudeDelta, 0.01),
                longitudeDelta: max(span.longitudeDelta, 0.01)
            )
        )
        
        mapView.setRegion(region, animated: false)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
            
            let identifier = "WorkoutPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            if let markerView = annotationView as? MKMarkerAnnotationView {
                if annotation.title == "Start" {
                    markerView.markerTintColor = .green
                    markerView.glyphImage = UIImage(systemName: "flag.fill")
                } else if annotation.title == "End" {
                    markerView.markerTintColor = .red
                    markerView.glyphImage = UIImage(systemName: "flag.checkered")
                }
            }
            
            return annotationView
        }
    }
}


// Health Store for managing HealthKit data
class HealthStore: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var authorized = false
    @Published var workouts: [HKWorkout] = []
    
    private let relevantWorkoutTypes: [HKWorkoutActivityType] = [
        .running,
        .walking,
        .hiking,
        .cycling
    ]
    
    init() {}
    
    @MainActor
       func requestAuthorization() async {
           // Define the types to read
           let typesToRead: Set<HKSampleType> = [
               HKObjectType.workoutType(),
               HKSeriesType.workoutRoute()
           ]
           
           do {
               // Request authorization using async/await
               try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: typesToRead)
               self.authorized = true
               // Fetch workouts immediately after authorization
               await self.fetchWorkouts()
           } catch {
               print("Authorization failed: \(error.localizedDescription)")
               self.authorized = false
           }
       }
    
    @MainActor
    func fetchWorkouts() async {
        // Default to fetching last 3 years of workouts
        let calendar = Calendar.current
        let threeYearsAgo = calendar.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        
        await fetchWorkouts(
            startDate: threeYearsAgo,
            endDate: Date(),
            workoutTypes: Set(relevantWorkoutTypes),
            limit: 500
        )
    }
    
    @MainActor
    func fetchWorkouts(
        startDate: Date,
        endDate: Date,
        workoutTypes: Set<HKWorkoutActivityType>,
        limit: Int = 500
    ) async {
        guard authorized else {
            print("Not authorized to fetch workouts")
            return
        }
        
        // Time range predicate
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        // Workout type predicates
        let typesPredicates = workoutTypes.map { type in
            HKQuery.predicateForWorkouts(with: type)
        }
        
        // Combine all predicates
        var predicates: [NSPredicate] = [datePredicate]
        if !typesPredicates.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typesPredicates))
        }
        
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        do {
            // Using async/await pattern for the query
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: finalPredicate,
                    limit: limit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let samples = samples else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    continuation.resume(returning: samples)
                }
                
                self.healthStore.execute(query)
            }
            
            // Update the workouts on the main actor
            self.workouts = samples as? [HKWorkout] ?? []
            
        } catch {
            print("Error fetching workouts: \(error.localizedDescription)")
            // Ensure we don't leave the workouts array empty if there's an error
            if self.workouts.isEmpty {
                self.workouts = []
            }
        }
    }
    
    func fetchRouteData(for workout: HKWorkout, completion: @escaping ([CLLocation]?, Error?) -> Void) {
        // Fetch route data for a specific workout
        let routeType = HKSeriesType.workoutRoute()
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let routeQuery = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { (query, samples, error) in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let routeSamples = samples as? [HKWorkoutRoute], let route = routeSamples.first else {
                completion([], nil)
                return
            }
            
            var allLocations: [CLLocation] = []
            
            let routeDataQuery = HKWorkoutRouteQuery(route: route) { (query, locations, done, error) in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let locations = locations {
                    allLocations.append(contentsOf: locations)
                }
                
                if done {
                    completion(allLocations, nil)
                }
            }
            
            self.healthStore.execute(routeDataQuery)
        }
        
        self.healthStore.execute(routeQuery)
    }
}
