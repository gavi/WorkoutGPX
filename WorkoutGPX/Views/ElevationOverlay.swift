import SwiftUI
import CoreLocation
import Charts

// Floating elevation-profile card: min/max/gain summary plus an interactive chart.
// Dragging across the chart reports the selected route point so the map can mark it.
struct ElevationOverlay: View {
    let trackSegments: [RouteSegment]
    @EnvironmentObject var settings: SettingsModel
    
    // Index (into the flattened locations) of the point under the user's finger
    @Binding var selectedPointIndex: Int?
    
    // Sampled chart data, rebuilt only when the route or the relevant settings change
    // (not on every hover-driven re-render)
    @State private var elevationData = ElevationData(points: [], min: 0, max: 0, gain: 0)
    
    private var totalPointCount: Int {
        trackSegments.reduce(0) { $0 + $1.locations.count }
    }
    
    init(trackSegments: [RouteSegment], selectedPointIndex: Binding<Int?> = .constant(nil)) {
        self.trackSegments = trackSegments
        self._selectedPointIndex = selectedPointIndex
    }
    
    // One sample in the chart
    struct ElevationPoint: Identifiable {
        let distance: Double      // in display units (km or mi)
        let elevation: Double     // in display units (m or ft)
        let index: Int            // index within the sampled chart points
        let originalIndex: Int    // index within the flattened locations
        
        var id: Int { index }
    }
    
    private struct ElevationData {
        let points: [ElevationPoint]
        let min: Double   // metres
        let max: Double   // metres
        let gain: Double  // metres
    }
    
    // Sample the route for the chart, converting to display units and striding
    // according to the chart-detail setting so huge tracks stay responsive
    private func prepareElevationData() -> ElevationData {
        let locations = trackSegments.flatMap { $0.locations }
        let rawElevations = locations.map { $0.altitude }
        
        let minElevation = rawElevations.min() ?? 0
        let maxElevation = rawElevations.max() ?? 0
        let elevationGain = calculateElevationGain(rawElevations)
        
        // Cumulative distance for every location, computed once
        var cumulative: [Double] = []
        cumulative.reserveCapacity(locations.count)
        var running = 0.0
        for (i, location) in locations.enumerated() {
            if i > 0 {
                running += locations[i - 1].distance(from: location)
            }
            cumulative.append(running)
        }
        
        let distanceScale = settings.useMetricSystem ? 1.0 / 1000 : 1.0 / 1609.34
        let elevationScale = settings.useMetricSystem ? 1.0 : 3.28084
        
        let strideSize = calculateStrideSize(for: rawElevations.count)
        var chartPoints: [ElevationPoint] = []
        
        for (i, originalIndex) in stride(from: 0, to: rawElevations.count, by: strideSize).enumerated() {
            chartPoints.append(ElevationPoint(
                distance: cumulative[originalIndex] * distanceScale,
                elevation: rawElevations[originalIndex] * elevationScale,
                index: i,
                originalIndex: originalIndex
            ))
        }
        
        // Always include the last point when striding
        if strideSize > 1, let last = chartPoints.last, last.originalIndex != rawElevations.count - 1, !rawElevations.isEmpty {
            let originalIndex = rawElevations.count - 1
            chartPoints.append(ElevationPoint(
                distance: cumulative[originalIndex] * distanceScale,
                elevation: rawElevations[originalIndex] * elevationScale,
                index: chartPoints.count,
                originalIndex: originalIndex
            ))
        }
        
        return ElevationData(points: chartPoints, min: minElevation, max: maxElevation, gain: elevationGain)
    }
    
    var body: some View {
        let elevationScale = settings.useMetricSystem ? 1.0 : 3.28084
        
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Elevation Profile")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.blue)
                        Text("Min: \(formatElevation(elevationData.min))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.red)
                        Text("Max: \(formatElevation(elevationData.max))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mountain.2")
                            .foregroundColor(.green)
                        Text("Gain: \(formatElevation(elevationData.gain))")
                            .font(.caption)
                    }
                }
            }
            
            if !elevationData.points.isEmpty {
                ElevationChartView(
                    points: elevationData.points,
                    minValue: elevationData.min * elevationScale,
                    maxValue: elevationData.max * elevationScale,
                    yUnit: settings.useMetricSystem ? "m" : "ft",
                    xUnit: settings.useMetricSystem ? "km" : "mi",
                    onSelect: { chartIndex in
                        guard let chartIndex = chartIndex,
                              let point = elevationData.points.first(where: { $0.index == chartIndex }) else {
                            selectedPointIndex = nil
                            return
                        }
                        if selectedPointIndex != point.originalIndex {
                            selectedPointIndex = point.originalIndex
                        }
                    }
                )
                .frame(height: 120)
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.85))
        .cornerRadius(12)
        .padding([.horizontal, .bottom])
        .onAppear { elevationData = prepareElevationData() }
        .onChange(of: totalPointCount) { _ in elevationData = prepareElevationData() }
        .onChange(of: settings.useMetricSystem) { _ in elevationData = prepareElevationData() }
        .onChange(of: settings.chartDataDensity) { _ in elevationData = prepareElevationData() }
    }
    
    // Sum of positive elevation changes
    private func calculateElevationGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i - 1]
            if diff > 0 { gain += diff }
        }
        return gain
    }
    
    private func formatElevation(_ elevation: Double) -> String {
        settings.useMetricSystem
            ? String(format: "%.0f m", elevation)
            : String(format: "%.0f ft", elevation * 3.28084)
    }
    
    // Small routes are drawn in full; larger ones are strided by the chart-detail setting
    private func calculateStrideSize(for dataPointCount: Int) -> Int {
        let strideFactor = settings.chartDataStride
        if dataPointCount <= 500 {
            return 1
        }
        if dataPointCount <= 2000 {
            return settings.chartDataDensity >= 1.0 ? 1 : strideFactor
        }
        return max(1, dataPointCount / 2000) * strideFactor
    }
}

// The chart itself: area + line, a marker for the touched point, and drag-to-scrub
struct ElevationChartView: View {
    let points: [ElevationOverlay.ElevationPoint]
    let minValue: Double
    let maxValue: Double
    let yUnit: String
    let xUnit: String
    // Called with the chart index under the finger, or nil when the gesture ends
    var onSelect: ((Int?) -> Void)? = nil
    
    @State private var selectedPoint: ElevationOverlay.ElevationPoint? = nil
    
    private var yScaleDomain: ClosedRange<Double> {
        let padding = max((maxValue - minValue) * 0.05, 1)
        return (minValue - padding)...(maxValue + padding)
    }
    
    private var xScaleDomain: ClosedRange<Double> {
        (points.first?.distance ?? 0)...(max(points.last?.distance ?? 1, (points.first?.distance ?? 0) + 0.01))
    }
    
    // Binary search for the sample nearest to a distance along the route
    private func findClosestPoint(to distance: Double) -> ElevationOverlay.ElevationPoint? {
        guard let first = points.first, let last = points.last else { return nil }
        if distance <= first.distance { return first }
        if distance >= last.distance { return last }
        
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].distance < distance {
                low = mid
            } else {
                high = mid
            }
        }
        return abs(points[low].distance - distance) < abs(points[high].distance - distance) ? points[low] : points[high]
    }
    
    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Distance", point.distance),
                    y: .value("Elevation", point.elevation)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.green.opacity(0.3), Color.red.opacity(0.3)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
            
            ForEach(points) { point in
                LineMark(
                    x: .value("Distance", point.distance),
                    y: .value("Elevation", point.elevation)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .green, .red], startPoint: .bottom, endPoint: .top)
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            
            if let selectedPoint = selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.distance))
                    .foregroundStyle(Color.gray.opacity(0.3))
                    .annotation(position: .top, alignment: .center) {
                        Text("\(Int(selectedPoint.elevation)) \(yUnit)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(4)
                    }
                
                PointMark(
                    x: .value("Distance", selectedPoint.distance),
                    y: .value("Elevation", selectedPoint.elevation)
                )
                .foregroundStyle(Color.white)
                .symbolSize(150)
                
                PointMark(
                    x: .value("Distance", selectedPoint.distance),
                    y: .value("Elevation", selectedPoint.elevation)
                )
                .foregroundStyle(Color.red)
                .symbolSize(100)
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXScale(domain: xScaleDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text("\(Int(yValue)) \(yUnit)")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let xValue = value.as(Double.self) {
                        Text(String(format: "%.1f \(xUnit)", xValue))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let distance = proxy.value(atX: value.location.x, as: Double.self),
                                   let closest = findClosestPoint(to: distance) {
                                    selectedPoint = closest
                                    onSelect?(closest.index)
                                }
                            }
                            .onEnded { _ in
                                // Keep the marker on the chart; the map marker is released
                                onSelect?(nil)
                            }
                    )
            }
        }
    }
}
