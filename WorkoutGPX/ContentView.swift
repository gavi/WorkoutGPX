import SwiftUI
import HealthKit
import CoreLocation
import MapKit


// Main content view
struct ContentView: View {
    @StateObject private var healthStore = HealthStore()
    
    var body: some View {
        NavigationView {
            VStack {
                if healthStore.workouts.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading workouts...")
                        
                        if !healthStore.authorized {
                            VStack {
                                Text("Health access not authorized")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Button("Request Authorization") {
                                    healthStore.requestAuthorization()
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
                    List {
                        ForEach(healthStore.workouts, id: \.uuid) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout, healthStore: healthStore)) {
                                WorkoutRow(workout: workout)
                            }
                        }
                    }
                    .refreshable {
                        await healthStore.fetchWorkouts()
                    }
                }
            }
            .navigationTitle("Workout GPX Exporter")
            .onAppear {
                healthStore.requestAuthorization()
            }
        }
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
    @State private var exportSuccess = false
    @State private var exportError: String?
    @State private var showShareSheet = false
    @State private var gpxURL: URL?
    
    var body: some View {
        VStack {
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
                // Workout info section
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
                .padding(.horizontal)
                
                // Map view
                if !routeData.isEmpty {
                    MapView(routeLocations: routeData)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .padding()
                }
                
                if exportSuccess {
                    VStack {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 30))
                            .foregroundColor(.green)
                        
                        Text("GPX File Created Successfully!")
                            .font(.headline)
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
        .navigationTitle(workoutActivityTypeString(workout.workoutActivityType))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    if !routeData.isEmpty && gpxURL == nil {
                        exportGPX()
                    } else if let _ = gpxURL {
                        showShareSheet = true
                    }
                }) {
                    Image(systemName: gpxURL == nil ? "square.and.arrow.down" : "square.and.arrow.up")
                }
                .disabled(routeData.isEmpty || isLoading)
            }
        }
        .onAppear {
            loadRouteData()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = gpxURL {
                ShareSheet(items: [url])
            }
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
            exportSuccess = true
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
}

// Share sheet for sharing GPX files
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
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
    
    func requestAuthorization() {
        // Define the types to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        
        // Request authorization
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.authorized = success
                if success {
                    Task {
                        await self?.fetchWorkouts()
                    }
                }
            }
        }
    }
    
    @MainActor
    func fetchWorkouts() async {
        let predicate = HKQuery.predicateForWorkouts(with: .greaterThanOrEqualTo, duration: 1.0)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let workouts = samples as? [HKWorkout], error == nil else {
                return
            }
            
            // Filter to relevant workout types
            let filteredWorkouts = workouts.filter { workout in
                self?.relevantWorkoutTypes.contains(workout.workoutActivityType) ?? false
            }
            
            DispatchQueue.main.async {
                self?.workouts = filteredWorkouts
            }
        }
        
        healthStore.execute(query)
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
        
        healthStore.execute(routeQuery)
    }
}
