import SwiftUI
import MapKit
import CoreLocation

// Custom polyline object to store elevation data for coloring
class ElevationPolyline: MKPolyline {
    var elevations: [CLLocationDistance] = []
    var minElevation: CLLocationDistance = 0
    var maxElevation: CLLocationDistance = 0
}

// Custom renderer for gradient polylines
class GradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    
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
        
        // Calculate a zoom-adjusted line width
        // As zoomScale gets smaller (zoomed out), the line width increases inversely
        // Sqrt relationship provides better scaling across different zoom levels
        let zoomAdjustedLineWidth = lineWidth / sqrt(zoomScale)
        
        // For very zoomed out views (e.g., when seeing the entire route), boost the width
        // The constant 0.1 represents a fairly zoomed out view
        let zoomBoostFactor = max(1.0, 0.2 / (zoomScale + 0.02))
        
        // Determine final line width with both adjustments
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
                // Prevent out of bounds
                let index = min(i, elevationPolyline.elevations.count - 1)
                
                // Get the elevation at this point
                let elevation = elevationPolyline.elevations[index]
                
                // Calculate normalized elevation (0-1)
                let elevationRange = elevationPolyline.maxElevation - elevationPolyline.minElevation
                let normalizedElevation = elevationRange > 0 ? 
                    (elevation - elevationPolyline.minElevation) / elevationRange : 0.5
                
                // Create a color gradient from blue (low) to green (middle) to red (high)
                // Use more saturated, vibrant colors for better visibility
                let color: UIColor
                if normalizedElevation < 0.5 {
                    // Low to medium: saturated blue to saturated green
                    let t = normalizedElevation * 2
                    color = UIColor(
                        red: 0,
                        green: 0.7 * t + 0.3, // Boost green component for visibility
                        blue: 1.0,            // Keep blue at max for low elevations
                        alpha: 1
                    )
                } else {
                    // Medium to high: saturated green to saturated red
                    let t = (normalizedElevation - 0.5) * 2
                    color = UIColor(
                        red: 0.7 * t + 0.3,   // Boost red component for visibility
                        green: 0.8 * (1 - t) + 0.2, // Boost green component for visibility
                        blue: 0,
                        alpha: 1
                    )
                }
                
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
}

// UIViewRepresentable for MapKit
struct MapView: UIViewRepresentable {
    let routeLocations: [CLLocation]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        // Add polyline with elevation data
        if !routeLocations.isEmpty {
            // Create a custom polyline that stores elevation data
            let elevationPolyline = createElevationPolyline(from: routeLocations)
            mapView.addOverlay(elevationPolyline)
            
            // Store elevation data in coordinator for renderer to use
            context.coordinator.elevationPolyline = elevationPolyline
            
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
        var elevationPolyline: ElevationPolyline?
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? ElevationPolyline {
                // Create a custom gradient polyline renderer
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                
                // Configure it to use our elevation data
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = 12  // Increased line width for better visibility at all zoom levels
                
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