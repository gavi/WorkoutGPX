import SwiftUI
import MapKit
import CoreLocation

// Enhanced polyline object to store elevation data and gradients
class ElevationPolyline: MKPolyline {
    // Basic elevation data
    var elevations: [CLLocationDistance] = []
    var minElevation: CLLocationDistance = 0
    var maxElevation: CLLocationDistance = 0
    
    // Enhanced data for Garmin-like visualization
    var grades: [Double] = []        // Store the grade (steepness) between each point
    var maxGrade: Double = 0         // Maximum grade (uphill)
    var minGrade: Double = 0         // Minimum grade (downhill)
    var totalAscent: Double = 0      // Total elevation gain
    var totalDescent: Double = 0     // Total elevation loss
    
    // Calculate enhanced statistics after setting elevations
    func calculateGradeData(from locations: [CLLocation]) {
        guard locations.count > 1 && elevations.count == locations.count else { 
            print("ERROR: Cannot calculate grade data - invalid locations or elevations")
            return 
        }
        
        // First, smooth the elevation data to reduce GPS noise
        smoothElevationData()
        
        var currentAscent: Double = 0
        var currentDescent: Double = 0
        grades = Array(repeating: 0, count: elevations.count)
        
        // Use a sliding window for calculating grades to reduce noise
        let windowSize = min(5, locations.count / 10 + 1) // Adaptive window size
        print("Using window size \(windowSize) for \(locations.count) locations")
        
        for i in 0..<(locations.count - 1) {
            // Calculate start and end indices for the window
            let startIdx = max(0, i - windowSize)
            let endIdx = min(locations.count - 1, i + windowSize)
            
            if endIdx > startIdx {
                // Use points at the edges of the window for more stable grade calculation
                let elevation1 = elevations[startIdx]
                let elevation2 = elevations[endIdx]
                let location1 = locations[startIdx]
                let location2 = locations[endIdx]
                
                // Calculate horizontal distance over the window
                let horizontalDistance = location1.distance(from: location2)
                
                // Calculate grade (avoid division by zero)
                var grade = 0.0
                if horizontalDistance > 5.0 { // Require more substantial distance for good grade calculation
                    grade = (elevation2 - elevation1) / horizontalDistance
                    
                    // Apply realistic limits to grades (real-world trails rarely exceed 35%)
                    let originalGrade = grade
                    grade = min(max(grade, -0.45), 0.45)
                    
                    // Debug every 20th point to avoid console flood
                    if i % 20 == 0 {
                        print("Point \(i): window \(startIdx)-\(endIdx), elev diff: \(elevation2-elevation1)m, " +
                              "horiz dist: \(horizontalDistance)m, grade: \(originalGrade) → \(grade)")
                    }
                } else if i % 20 == 0 {
                    print("Point \(i): window \(startIdx)-\(endIdx), horizontal distance too small (\(horizontalDistance)m)")
                }
                
                // Preserve small grade changes rather than zeroing them out
                // This ensures subtle elevation changes are still visible on the map
                // (Previously we were setting grades < 0.005 to 0.0)
                
                // Store the grade
                grades[i] = grade
                
                // Update max/min grade
                if i == 0 || grade > maxGrade {
                    maxGrade = grade
                }
                if i == 0 || grade < minGrade {
                    minGrade = grade
                }
            }
            
            // Still calculate ascent/descent point-to-point for accuracy
            if i > 0 {
                let elevationDiff = elevations[i] - elevations[i-1]
                // Only count significant elevation changes (>1m) to avoid noise
                if elevationDiff > 1.0 {
                    currentAscent += elevationDiff
                } else if elevationDiff < -1.0 {
                    currentDescent += abs(elevationDiff)
                }
            }
        }
        
        // Store final values
        totalAscent = currentAscent
        totalDescent = currentDescent
        
        // Set the last grade to match the previous to avoid gaps
        if grades.count > 1 {
            grades[grades.count - 1] = grades[grades.count - 2]
        }
    }
    
    // Smooth elevation data using a moving average
    private func smoothElevationData() {
        guard elevations.count > 3 else { return }
        
        // Create a copy of the original elevations
        let originalElevations = elevations
        
        // Window size for smoothing (adaptive to route length)
        let windowSize = min(5, elevations.count / 20 + 2)
        
        // Apply moving average smoothing
        for i in 0..<elevations.count {
            var sum: Double = 0
            var count: Double = 0
            
            // Calculate window boundaries
            let windowStart = max(0, i - windowSize)
            let windowEnd = min(originalElevations.count - 1, i + windowSize)
            
            // Sum elevations in window
            for j in windowStart...windowEnd {
                sum += originalElevations[j]
                count += 1
            }
            
            // Set smoothed elevation
            if count > 0 {
                elevations[i] = sum / count
            }
        }
    }
    
    // Helper method to get statistics formatted for display
    func getStatisticsDescription() -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        
        let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
        let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
        
        let maxGradePercent = abs(maxGrade * 100)
        let minGradePercent = abs(minGrade * 100)
        
        return """
        Total Ascent: \(formatter.string(from: ascentMeasurement))
        Total Descent: \(formatter.string(from: descentMeasurement))
        Max Uphill Grade: \(String(format: "%.1f", maxGradePercent))%
        Max Downhill Grade: \(String(format: "%.1f", minGradePercent))%
        """
    }
}

// Custom renderer for gradient polylines
class GradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for grade calculation - reduced to show more color variation
    private let minSignificantGrade: Double = 0.005  // 0.5% grade - flat/slight
    private let moderateGrade: Double = 0.03        // 3% grade - moderate
    private let steepGrade: Double = 0.08          // 8% grade - steep
    private let verysteepGrade: Double = 0.15      // 15% grade - very steep
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let elevationPolyline = elevationPolyline else {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }

        // Start by getting the polyline's points in map coordinates
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        // We need at least 2 points to draw a line
        if pointCount < 2 {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }
        
        // Calculate line width with zoom adjustments
        let zoomAdjustedLineWidth = lineWidth / sqrt(zoomScale)
        let zoomBoostFactor = max(1.0, 0.2 / (zoomScale + 0.02))
        let actualLineWidth = min(zoomAdjustedLineWidth * zoomBoostFactor, lineWidth * 25)
        
        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(actualLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        
        // Draw each segment with its corresponding color
        for i in 0..<(pointCount-1) {
            // Get map points for the segment
            let pointA = points[i]
            let pointB = points[i+1]
            
            // Convert to points in the renderer's coordinate system
            let pixelPointA = point(for: MKMapPoint(x: pointA.x, y: pointA.y))
            let pixelPointB = point(for: MKMapPoint(x: pointB.x, y: pointB.y))
            
            // Check if this segment is visible in the current map rect
            let segmentRect = MKMapRect(x: min(pointA.x, pointB.x),
                                       y: min(pointA.y, pointB.y),
                                       width: abs(pointB.x - pointA.x),
                                       height: abs(pointB.y - pointA.y))
            
            // Only draw if segment is visible
            if mapRect.intersects(segmentRect) {
                // Prevent out of bounds access
                let indexA = min(i, elevationPolyline.elevations.count - 1)
                let indexB = min(i+1, elevationPolyline.elevations.count - 1)
                
                // Get elevations at both points
                let elevationA = elevationPolyline.elevations[indexA]
                let elevationB = elevationPolyline.elevations[indexB]
                
                // Calculate the horizontal distance between points (in meters)
                let metersPerMapPoint = MKMetersPerMapPointAtLatitude(pointA.y)
                let dx = (pointB.x - pointA.x) * metersPerMapPoint
                let dy = (pointB.y - pointA.y) * metersPerMapPoint
                let horizontalDistance = sqrt(dx*dx + dy*dy)
                
                // Calculate grade (rise/run) if we have a significant horizontal distance
                var grade = 0.0
                
                // Try to use precomputed grades first if available
                if !elevationPolyline.grades.isEmpty && indexA < elevationPolyline.grades.count {
                    grade = elevationPolyline.grades[indexA]
                    print("Segment \(i): Using precomputed grade: \(grade)")
                }
                // If grade is zero or grades aren't available, calculate it
                else if horizontalDistance > 1.0 {  // Avoid division by very small numbers
                    grade = (elevationB - elevationA) / horizontalDistance
                    
                    // Debug elevation info
                    print("Segment \(i): elevA=\(elevationA), elevB=\(elevationB), diff=\(elevationB-elevationA), horizDist=\(horizontalDistance), rawGrade=\(grade)")
                    
                    // Filter out unrealistic grades from GPS noise
                    // Real-world roads/trails rarely exceed 30-35% grade
                    if abs(grade) > 0.5 {  // 50% grade cutoff for realism
                        // Apply a more reasonable limit
                        let oldGrade = grade
                        grade = grade > 0 ? 0.35 : -0.35
                        print("  Clamping grade from \(oldGrade) to \(grade)")
                    }
                    
                    // Apply a minimum threshold to avoid flat line when elevation is changing
                    if abs(grade) < 0.01 && abs(elevationB - elevationA) > 0.5 {
                        grade = (elevationB > elevationA) ? 0.01 : -0.01
                        print("  Boosting small grade to \(grade)")
                    }
                } else {
                    print("Segment \(i): Horizontal distance too small (\(horizontalDistance)m), using grade=0")
                }
                
                // Get color based on grade rather than absolute elevation
                // Use actual grade for coloring
                let debugForcedGradient = false
                var colorGrade = grade
                
                if debugForcedGradient {
                    // Force different colors by varying grades artificially based on location
                    let cycle = Double(i % 5)
                    if cycle < 1 {
                        colorGrade = 0.03  // slight uphill - yellow-green
                    } else if cycle < 2 {
                        colorGrade = 0.09  // moderate uphill - orange
                    } else if cycle < 3 {
                        colorGrade = 0.18  // steep uphill - red
                    } else if cycle < 4 {
                        colorGrade = -0.03 // slight downhill - light blue
                    } else {
                        colorGrade = -0.09 // moderate downhill - medium blue
                    }
                    // Print every 10th segment for debugging
                    if i % 10 == 0 {
                        print("DEBUG FORCED GRADIENT: Segment \(i) forced grade \(colorGrade)")
                    }
                }
                
                let color = colorForGrade(colorGrade)
                
                // Set stroke color for this segment
                ctx.setStrokeColor(color.cgColor)
                
                // Draw the segment
                ctx.beginPath()
                ctx.move(to: pixelPointA)
                ctx.addLine(to: pixelPointB)
                ctx.strokePath()
            }
        }
        
        ctx.restoreGState()
    }
    
    // Get color based on grade (Garmin-like)
    private func colorForGrade(_ grade: Double) -> UIColor {
        // Ensure grade is in a reasonable range
        let clampedGrade = min(max(grade, -verysteepGrade), verysteepGrade)
        
        // Enable non-gray colors for flat sections
        // Set to true to show flat sections as colored
        let forceNonGrayColors = true
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            print("colorForGrade call #\(callCounter): input: \(grade), clamped: \(clampedGrade)")
        }
        self.callCounter = callCounter
        
        // Color schemes based on Garmin's approach
        // Uphill: green to yellow to orange to red
        // Downhill: light blue to darker blue
        // Flat: gray
        
        if clampedGrade > 0 || (forceNonGrayColors && grade >= 0) {
            // Uphill or flat treated as slight uphill
            if clampedGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight uphill: gray (only if not forcing colors)
                return UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if clampedGrade < moderateGrade {
                // Force more vibrant colors rather than subtle gradient
                // Use multiple distinct colors instead of blending
                
                // Slight uphill: vibrant green
                return UIColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < steepGrade {
                // Moderate uphill: bright orange
                return UIColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < verysteepGrade {
                // Steep uphill: bright red
                return UIColor(
                    red: 1.0,
                    green: 0.1,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Very steep uphill: bright red
                return UIColor(red: 1.0, green: 0.1, blue: 0, alpha: 1.0)
            }
        } else {
            // Downhill (using absolute value of grade for calculations)
            let absGrade = abs(clampedGrade)
            
            if absGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight downhill: gray (only if not forcing colors)
                return UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if absGrade < moderateGrade {
                // Light blue for slight downhill
                return UIColor(
                    red: 0.0,
                    green: 0.5,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else if absGrade < steepGrade {
                // Medium blue for moderate downhill
                return UIColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if absGrade < verysteepGrade {
                // Deep blue/purple for steep downhill
                return UIColor(
                    red: 0.3,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else {
                // Very steep downhill: purple
                return UIColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0)
            }
        }
    }
}

// UIViewRepresentable for MapKit
struct MapView: UIViewRepresentable {
    let trackSegments: [GPXTrackSegment]
    @EnvironmentObject var settings: SettingsModel
    
    // Convenience init to maintain backward compatibility
    init(routeLocations: [CLLocation]) {
        self.trackSegments = [GPXTrackSegment(locations: routeLocations)]
    }
    
    // New initializer for multiple segments
    init(trackSegments: [GPXTrackSegment]) {
        self.trackSegments = trackSegments
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        #if swift(>=5.7) && canImport(MapKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Skip if no segments
        if trackSegments.isEmpty {
            return mapView
        }
        
        // Collect all locations for region setting
        var allLocations: [CLLocation] = []
        
        // Store all polylines for the coordinator
        var elevationPolylines: [ElevationPolyline] = []
        
        // Process each segment separately
        for (index, segment) in trackSegments.enumerated() {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            // Add locations for region calculation later
            allLocations.append(contentsOf: locations)
            
            // Create the enhanced elevation polyline for this segment
            let elevationPolyline = createElevationPolyline(from: locations)
            
            // Calculate grade data (this will smooth and process elevation data)
            elevationPolyline.calculateGradeData(from: locations)
            
            // Debug elevation data
            print("=== SEGMENT \(index+1) ELEVATION DATA SUMMARY ===")
            print("Total points: \(elevationPolyline.elevations.count)")
            print("Min elevation: \(elevationPolyline.minElevation)m")
            print("Max elevation: \(elevationPolyline.maxElevation)m")
            print("Total ascent: \(elevationPolyline.totalAscent)m")
            print("Total descent: \(elevationPolyline.totalDescent)m")
            print("Grade range: \(elevationPolyline.minGrade) to \(elevationPolyline.maxGrade)")
            if !elevationPolyline.grades.isEmpty {
                let nonZeroGrades = elevationPolyline.grades.filter { abs($0) > 0.005 }
                print("Non-zero grades count: \(nonZeroGrades.count) of \(elevationPolyline.grades.count)")
                
                // Sample some grades
                if nonZeroGrades.count > 0 {
                    let sampleCount = min(5, nonZeroGrades.count)
                    print("Sample grades: \(nonZeroGrades.prefix(sampleCount))")
                }
            }
            print("==============================")
            
            // Add to map
            mapView.addOverlay(elevationPolyline)
            
            // Store the polyline for the coordinator
            elevationPolylines.append(elevationPolyline)
        }
        
        // Store elevation polylines in coordinator for renderer to use
        context.coordinator.elevationPolylines = elevationPolylines
        
        // Set the visible region to show all tracks
        if !allLocations.isEmpty {
            // Add significant elevation markers (Garmin-like)
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Set the region to show all segments
            setRegion(for: mapView, from: allLocations)
            
            // Add start and end annotations using the first and last segments
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
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
        // Update map configuration if settings changed
        #if swift(>=5.7) && canImport(MapKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
    }
    
    private func createElevationPolyline(from locations: [CLLocation]) -> ElevationPolyline {
        let coordinates = locations.map { $0.coordinate }
        let elevations = locations.map { $0.altitude }
        
        // Create the polyline with coordinates
        let elevationPolyline = ElevationPolyline(coordinates: coordinates, count: coordinates.count)
        
        // Store the elevations
        elevationPolyline.elevations = elevations
        
        // Calculate min and max elevations for scaling the gradient
        if let minEle = elevations.min(), let maxEle = elevations.max() {
            elevationPolyline.minElevation = minEle
            elevationPolyline.maxElevation = maxEle
        }
        
        return elevationPolyline
    }
    
    private func addElevationMarkers(to mapView: MKMapView, routeLocations: [CLLocation]) {
        guard routeLocations.count > 10 else { return }
        
        let elevations = routeLocations.map { $0.altitude }
        
        // Find local maxima and minima that are significant
        var significantPoints: [(index: Int, elevation: Double, isMax: Bool)] = []
        let windowSize = max(routeLocations.count / 20, 5) // Adaptive window size
        
        for i in windowSize..<(routeLocations.count - windowSize) {
            let currentElev = elevations[i]
            
            // Check if this is a local maximum
            var isLocalMax = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] > currentElev {
                    isLocalMax = false
                    break
                }
            }
            
            // Check if this is a local minimum
            var isLocalMin = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] < currentElev {
                    isLocalMin = false
                    break
                }
            }
            
            // Only add points that are significantly different from their surroundings
            if isLocalMax || isLocalMin {
                // Calculate average elevation in the window
                var sum = 0.0
                for j in (i-windowSize)...(i+windowSize) {
                    sum += elevations[j]
                }
                let avgElev = sum / Double(2 * windowSize + 1)
                
                // Check if the difference is significant (>= 10 meters)
                let elevDiff = abs(currentElev - avgElev)
                if elevDiff >= 10 {
                    significantPoints.append((i, currentElev, isLocalMax))
                }
            }
        }
        
        // Add elevation markers for significant points (limit to avoid clutter)
        let maxMarkers = 5
        if significantPoints.count > maxMarkers {
            // Sort by elevation difference and take top ones
            significantPoints.sort { abs($0.elevation) > abs($1.elevation) }
            significantPoints = Array(significantPoints.prefix(maxMarkers))
        }
        
        // Create annotations for these points
        for point in significantPoints {
            let annotation = MKPointAnnotation()
            annotation.coordinate = routeLocations[point.index].coordinate
            
            let elevationFormatted = Int(round(point.elevation))
            annotation.title = point.isMax ? "Peak" : "Valley"
            annotation.subtitle = "\(elevationFormatted)m"
            
            mapView.addAnnotation(annotation)
        }
    }
    
    private func setRegion(for mapView: MKMapView, from locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        
        // Find min/max coordinates
        var minLat = locations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = locations[0].coordinate.longitude
        var maxLon = minLon
        
        for location in locations {
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
        var elevationPolylines: [ElevationPolyline] = []
        
        // Keep the single polyline property for backward compatibility
        var elevationPolyline: ElevationPolyline? {
            get {
                return elevationPolylines.first
            }
            set {
                if let newValue = newValue {
                    elevationPolylines = [newValue]
                } else {
                    elevationPolylines = []
                }
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? ElevationPolyline {
                // Create a custom gradient polyline renderer
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                
                // Configure it to use our elevation data
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = 12  // Increased line width for better visibility
                
                return gradientRenderer
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
                // Set appearance based on annotation type
                if annotation.title == "Start" {
                    markerView.markerTintColor = .green
                    markerView.glyphImage = UIImage(systemName: "flag.fill")
                } else if annotation.title == "End" {
                    markerView.markerTintColor = .red
                    markerView.glyphImage = UIImage(systemName: "flag.checkered")
                } else if annotation.title == "Peak" {
                    markerView.markerTintColor = .orange
                    markerView.glyphImage = UIImage(systemName: "arrow.up")
                    markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
                } else if annotation.title == "Valley" {
                    markerView.markerTintColor = .blue
                    markerView.glyphImage = UIImage(systemName: "arrow.down")
                    markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
                }
            }
            
            return annotationView
        }
    }
}
