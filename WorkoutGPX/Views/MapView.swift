import SwiftUI
import MapKit
import CoreLocation
import UIKit

// Map rendering for a workout route: gradient-coloured polylines (effort or pure
// elevation), start/end/peak/valley markers, and a hover marker driven by the
// elevation chart. Shared lineage with GPXExplore's MapView+Common / MapView+iOS.

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
                    grade = min(max(grade, -0.45), 0.45)
                    
                    // Debug every 20th point to avoid console flood
                    if i % 20 == 0 {
                        //print("Point \(i): window \(startIdx)-\(endIdx), elev diff: \(elevation2-elevation1)m, " +
                              //"horiz dist: \(horizontalDistance)m, grade: \(originalGrade) → \(grade)")
                    }
                } else if i % 20 == 0 {
                    //print("Point \(i): window \(startIdx)-\(endIdx), horizontal distance too small (\(horizontalDistance)m)")
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

// Original effort-based gradient polyline renderer
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
        let baseLineWidth = self.lineWidth // Use the lineWidth property set from outside
        let adjustedLineWidth = baseLineWidth / zoomScale

        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(adjustedLineWidth)
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
                    //print("Segment \(i): Using precomputed grade: \(grade)")
                }
                // If grade is zero or grades aren't available, calculate it
                else if horizontalDistance > 1.0 {  // Avoid division by very small numbers
                    grade = (elevationB - elevationA) / horizontalDistance
                    
                    // Debug elevation info
                    //print("Segment \(i): elevA=\(elevationA), elevB=\(elevationB), diff=\(elevationB-elevationA), horizDist=\(horizontalDistance), rawGrade=\(grade)")
                    
                    // Filter out unrealistic grades from GPS noise
                    // Real-world roads/trails rarely exceed 30-35% grade
                    if abs(grade) > 0.5 {  // 50% grade cutoff for realism
                        // Apply a more reasonable limit
                        grade = grade > 0 ? 0.35 : -0.35
                        //print("  Clamping grade from previous value to \(grade)")
                    }
                    
                    // Apply a minimum threshold to avoid flat line when elevation is changing
                    if abs(grade) < 0.01 && abs(elevationB - elevationA) > 0.5 {
                        grade = (elevationB > elevationA) ? 0.01 : -0.01
                        //print("  Boosting small grade to \(grade)")
                    }
                } else {
                    //print("Segment \(i): Horizontal distance too small (\(horizontalDistance)m), using grade=0")
                }
                
                // Apply color for this grade
                let color = colorForGrade(grade)
                
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
            //print("colorForGrade call #\(callCounter): input: \(grade), clamped: \(clampedGrade)")
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

// New pure elevation gradient polyline renderer
class ElevationGradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for color range
    private let minSignificantValue: Double = 0.05  // 5% of range - slight color change
    private let moderateValue: Double = 0.3        // 30% of range - moderate color change
    private let strongValue: Double = 0.6          // 60% of range - strong color change
    private let extremeValue: Double = 0.85        // 85% of range - extreme color change
    
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
        let baseLineWidth = self.lineWidth // Use the lineWidth property set from outside
        let adjustedLineWidth = baseLineWidth / zoomScale

        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(adjustedLineWidth)
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
                
                // Get current elevation
                let elevation = elevationPolyline.elevations[indexA]
                
                // Calculate normalized elevation (0 to 1 scale)
                var normalizedElevation = 0.5 // Default to middle (gray) if no elevation range
                
                if elevationPolyline.maxElevation > elevationPolyline.minElevation {
                    normalizedElevation = (elevation - elevationPolyline.minElevation) / 
                                         (elevationPolyline.maxElevation - elevationPolyline.minElevation)
                }
                
                // Get color based on normalized elevation
                let color = colorForNormalizedElevation(normalizedElevation)
                
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
    
    // Get color based on normalized elevation (0-1 scale)
    private func colorForNormalizedElevation(_ value: Double) -> UIColor {
        // Ensure value is in 0-1 range
        let clampedValue = min(max(value, 0.0), 1.0)
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            //print("colorForNormalizedElevation call #\(callCounter): input: \(value), clamped: \(clampedValue)")
        }
        self.callCounter = callCounter
        
        // Color scheme for elevation:
        // Low: Deep blue -> Medium blue -> Light blue
        // Middle: Green/Yellow
        // High: Yellow -> Orange -> Red
        
        if clampedValue < 0.5 {
            // Lower half of elevation range (0.0-0.5 mapped to 0.0-1.0)
            let scaledValue = clampedValue * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Deepest blue - lowest elevation
                return UIColor(
                    red: 0.0,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Medium blue
                return UIColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Light blue
                return UIColor(
                    red: 0.0,
                    green: 0.6,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else {
                // Cyan - approaching middle elevation
                return UIColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.8,
                    alpha: 1.0
                )
            }
        } else {
            // Upper half of elevation range (0.5-1.0 mapped to 0.0-1.0)
            let scaledValue = (clampedValue - 0.5) * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Green - just above middle elevation
                return UIColor(
                    red: 0.1,
                    green: 0.8,
                    blue: 0.1,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Yellow-green
                return UIColor(
                    red: 0.6,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Yellow/orange
                return UIColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < extremeValue {
                // Orange/red - high elevation
                return UIColor(
                    red: 1.0,
                    green: 0.3,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Bright red - highest elevation
                return UIColor(
                    red: 1.0,
                    green: 0.0,
                    blue: 0.0,
                    alpha: 1.0
                )
            }
        }
    }
}


// MARK: - SwiftUI map view

struct MapView: UIViewRepresentable {
    let trackSegments: [RouteSegment]
    // Set to true to re-fit the map to the whole route (reset by the caller afterwards)
    var spanAll: Bool = false
    // Index into the flattened route locations of the point selected in the elevation chart
    var hoveredPointIndex: Int? = nil
    @EnvironmentObject var settings: SettingsModel
    
    // Convenience init to maintain backward compatibility
    init(routeLocations: [CLLocation]) {
        self.trackSegments = [RouteSegment(locations: routeLocations)]
    }
    
    init(trackSegments: [RouteSegment], spanAll: Bool = false, hoveredPointIndex: Int? = nil) {
        self.trackSegments = trackSegments
        self.spanAll = spanAll
        self.hoveredPointIndex = hoveredPointIndex
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        context.coordinator.appliedMapStyle = settings.mapStyle
        
        context.coordinator.isInitialLoad = true
        
        guard !trackSegments.isEmpty else { return mapView }
        
        var allLocations: [CLLocation] = []
        var elevationPolylines: [ElevationPolyline] = []
        
        for segment in trackSegments {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            allLocations.append(contentsOf: locations)
            
            let elevationPolyline = MapView.createElevationPolyline(from: locations)
            elevationPolyline.calculateGradeData(from: locations)
            mapView.addOverlay(elevationPolyline)
            elevationPolylines.append(elevationPolyline)
        }
        
        context.coordinator.elevationPolylines = elevationPolylines
        context.coordinator.appliedSignature = RouteSignature(
            segmentPointCounts: trackSegments.map { $0.locations.count },
            visualizationMode: settings.elevationVisualizationMode,
            lineWidth: settings.trackLineWidth
        )
        
        if !allLocations.isEmpty {
            MapView.addElevationMarkers(to: mapView, routeLocations: allLocations)
            MapView.setRegion(for: mapView, from: allLocations)
            MapView.addStartEndAnnotations(to: mapView, trackSegments: trackSegments)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        
        // Only touch the map configuration when the style actually changes
        if coordinator.appliedMapStyle != settings.mapStyle {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
            coordinator.appliedMapStyle = settings.mapStyle
        }
        
        let existingHoverAnnotations = mapView.annotations.filter { $0.title == "Hover Point" }
        
        // Overlays (and their grade calculations) are expensive: rebuild them only when the
        // segments or the renderer settings change, not on every hover update
        let signature = MapView.RouteSignature(
            segmentPointCounts: trackSegments.map { $0.locations.count },
            visualizationMode: settings.elevationVisualizationMode,
            lineWidth: settings.trackLineWidth
        )
        let routeChanged = coordinator.appliedSignature?.segmentPointCounts != signature.segmentPointCounts
        let overlaysNeedRebuild = coordinator.appliedSignature != signature
        
        if overlaysNeedRebuild {
            coordinator.clearOverlays(from: mapView)
            
            var newElevationPolylines: [ElevationPolyline] = []
            for segment in trackSegments where !segment.locations.isEmpty {
                let elevationPolyline = MapView.createElevationPolyline(from: segment.locations)
                elevationPolyline.calculateGradeData(from: segment.locations)
                mapView.addOverlay(elevationPolyline)
                newElevationPolylines.append(elevationPolyline)
            }
            coordinator.elevationPolylines = newElevationPolylines
            coordinator.appliedSignature = signature
        }
        
        guard !trackSegments.isEmpty else {
            coordinator.elevationPolylines = []
            return
        }
        
        let allLocations = trackSegments.flatMap { $0.locations }
        
        // Markers only need rebuilding when the route itself changes
        if routeChanged {
            let existingMarkerAnnotations = mapView.annotations.filter {
                $0.title == "Start" || $0.title == "End" || $0.title == "Peak" || $0.title == "Valley"
            }
            mapView.removeAnnotations(existingMarkerAnnotations)
            if !allLocations.isEmpty {
                MapView.addElevationMarkers(to: mapView, routeLocations: allLocations)
                MapView.addStartEndAnnotations(to: mapView, trackSegments: trackSegments)
            }
        }
        
        // Hover marker from the elevation chart, throttled to avoid map churn
        if let hoveredIndex = hoveredPointIndex, hoveredIndex >= 0 && hoveredIndex < allLocations.count {
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(context.coordinator.lastHoverUpdateTime)
            let isDifferentIndex = hoveredIndex != context.coordinator.lastHoveredIndex
            
            if timeSinceLastUpdate >= context.coordinator.hoverThrottleInterval || isDifferentIndex {
                let hoverLocation = allLocations[hoveredIndex]
                let elevation = hoverLocation.altitude
                let formattedElevation = settings.useMetricSystem
                    ? String(format: "%.0f m", elevation)
                    : String(format: "%.0f ft", elevation * 3.28084)
                let subtitle = "Elevation: \(formattedElevation)"
                
                if let existingPoint = existingHoverAnnotations.first as? MKPointAnnotation {
                    let existingCoord = existingPoint.coordinate
                    let newCoord = hoverLocation.coordinate
                    let significantMove = abs(existingCoord.latitude - newCoord.latitude) > 0.0001
                        || abs(existingCoord.longitude - newCoord.longitude) > 0.0001
                    if significantMove {
                        existingPoint.coordinate = newCoord
                    }
                    if existingPoint.subtitle != subtitle {
                        existingPoint.subtitle = subtitle
                    }
                } else {
                    if !existingHoverAnnotations.isEmpty {
                        mapView.removeAnnotations(existingHoverAnnotations)
                    }
                    let hoverPoint = MKPointAnnotation()
                    hoverPoint.coordinate = hoverLocation.coordinate
                    hoverPoint.title = "Hover Point"
                    hoverPoint.subtitle = subtitle
                    mapView.addAnnotation(hoverPoint)
                }
                
                context.coordinator.lastHoverUpdateTime = now
                context.coordinator.lastHoveredIndex = hoveredIndex
            }
        } else if !existingHoverAnnotations.isEmpty {
            mapView.removeAnnotations(existingHoverAnnotations)
            context.coordinator.lastHoveredIndex = nil
        }
        
        if spanAll {
            // Fit to the whole route on request (only once per trigger)
            if !coordinator.didConsumeSpanRequest && !allLocations.isEmpty {
                MapView.setRegion(for: mapView, from: allLocations, animated: true)
                coordinator.didConsumeSpanRequest = true
            }
        } else {
            coordinator.didConsumeSpanRequest = false
            if coordinator.isInitialLoad {
                if !allLocations.isEmpty {
                    coordinator.performDelayedZoom(mapView: mapView, locations: allLocations)
                }
            } else if routeChanged && !allLocations.isEmpty {
                // Segments appeared or changed: refit
                MapView.setRegion(for: mapView, from: allLocations)
            }
        }
    }
    
    // What the overlays were last built from; a change means they must be rebuilt
    struct RouteSignature: Equatable {
        let segmentPointCounts: [Int]
        let visualizationMode: ElevationVisualizationMode
        let lineWidth: Double
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: Helpers
    
    static func createElevationPolyline(from locations: [CLLocation]) -> ElevationPolyline {
        let coordinates = locations.map { $0.coordinate }
        let elevations = locations.map { $0.altitude }
        
        let elevationPolyline = ElevationPolyline(coordinates: coordinates, count: coordinates.count)
        elevationPolyline.elevations = elevations
        
        if let minEle = elevations.min(), let maxEle = elevations.max() {
            elevationPolyline.minElevation = minEle
            elevationPolyline.maxElevation = maxEle
        }
        
        return elevationPolyline
    }
    
    static func addStartEndAnnotations(to mapView: MKMapView, trackSegments: [RouteSegment]) {
        guard let firstLocation = trackSegments.first?.locations.first,
              let lastLocation = trackSegments.last?.locations.last else { return }
        
        let startPoint = MKPointAnnotation()
        startPoint.coordinate = firstLocation.coordinate
        startPoint.title = "Start"
        
        let endPoint = MKPointAnnotation()
        endPoint.coordinate = lastLocation.coordinate
        endPoint.title = "End"
        
        mapView.addAnnotations([startPoint, endPoint])
    }
    
    // Garmin-style peak/valley markers for significant local extremes
    static func addElevationMarkers(to mapView: MKMapView, routeLocations: [CLLocation]) {
        guard routeLocations.count > 10 else { return }
        
        let elevations = routeLocations.map { $0.altitude }
        var significantPoints: [(index: Int, elevation: Double, isMax: Bool)] = []
        let windowSize = max(routeLocations.count / 20, 5)
        
        for i in windowSize..<(routeLocations.count - windowSize) {
            let currentElev = elevations[i]
            var isLocalMax = true
            var isLocalMin = true
            var sum = 0.0
            
            for j in (i-windowSize)...(i+windowSize) {
                sum += elevations[j]
                if j != i {
                    if elevations[j] > currentElev { isLocalMax = false }
                    if elevations[j] < currentElev { isLocalMin = false }
                }
            }
            
            if isLocalMax || isLocalMin {
                let avgElev = sum / Double(2 * windowSize + 1)
                if abs(currentElev - avgElev) >= 10 {
                    significantPoints.append((i, currentElev, isLocalMax))
                }
            }
        }
        
        let maxMarkers = 5
        if significantPoints.count > maxMarkers {
            significantPoints.sort { abs($0.elevation) > abs($1.elevation) }
            significantPoints = Array(significantPoints.prefix(maxMarkers))
        }
        
        for point in significantPoints {
            let annotation = MKPointAnnotation()
            annotation.coordinate = routeLocations[point.index].coordinate
            annotation.title = point.isMax ? "Peak" : "Valley"
            annotation.subtitle = "\(Int(round(point.elevation)))m"
            mapView.addAnnotation(annotation)
        }
    }
    
    static func setRegion(for mapView: MKMapView, from locations: [CLLocation], animated: Bool = false) {
        guard !locations.isEmpty else { return }
        
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
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
            )
        )
        
        mapView.setRegion(region, animated: animated)
    }
    
    // MARK: Coordinator
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var elevationPolylines: [ElevationPolyline] = []
        var isInitialLoad = false
        var delayedZoomTimer: Timer?
        var lastHoverUpdateTime = Date.distantPast
        var lastHoveredIndex: Int?
        let hoverThrottleInterval: TimeInterval = 0.25
        var appliedSignature: RouteSignature?
        var appliedMapStyle: MapStyle?
        var didConsumeSpanRequest = false
        
        deinit {
            delayedZoomTimer?.invalidate()
        }
        
        func clearOverlays(from mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
        }
        
        // Initial fit happens after a short delay so the map has laid out
        func performDelayedZoom(mapView: MKMapView, locations: [CLLocation]) {
            delayedZoomTimer?.invalidate()
            delayedZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MapView.setRegion(for: mapView, from: locations)
                self?.isInitialLoad = false
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? ElevationPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            
            // Renderer choice and width come from user settings
            let modeString = UserDefaults.standard.string(forKey: "elevationVisualizationMode") ?? ""
            let mode = ElevationVisualizationMode(rawValue: modeString) ?? .effort
            let storedWidth = UserDefaults.standard.double(forKey: "trackLineWidth")
            let lineWidth = (2...10).contains(storedWidth) ? storedWidth : 4
            
            switch mode {
            case .effort:
                let renderer = GradientPolylineRenderer(polyline: polyline)
                renderer.elevationPolyline = polyline
                renderer.lineWidth = lineWidth
                return renderer
            case .gradient:
                let renderer = ElevationGradientPolylineRenderer(polyline: polyline)
                renderer.elevationPolyline = polyline
                renderer.lineWidth = lineWidth
                return renderer
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
            
            let isHover = annotation.title == "Hover Point"
            let identifier = isHover ? "HoverPin" : "WorkoutPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            guard let markerView = annotationView as? MKMarkerAnnotationView else { return annotationView }
            
            switch annotation.title ?? nil {
            case "Hover Point":
                markerView.markerTintColor = .systemRed
                markerView.glyphImage = UIImage(systemName: "location.fill")
                markerView.animatesWhenAdded = true
                markerView.displayPriority = .required
            case "Start":
                markerView.markerTintColor = .green
                markerView.glyphImage = UIImage(systemName: "flag.fill")
            case "End":
                markerView.markerTintColor = .red
                markerView.glyphImage = UIImage(systemName: "flag.checkered")
            case "Peak":
                markerView.markerTintColor = .orange
                markerView.glyphImage = UIImage(systemName: "arrow.up")
                markerView.displayPriority = .defaultLow
            case "Valley":
                markerView.markerTintColor = .blue
                markerView.glyphImage = UIImage(systemName: "arrow.down")
                markerView.displayPriority = .defaultLow
            default:
                break
            }
            
            return annotationView
        }
    }
}
