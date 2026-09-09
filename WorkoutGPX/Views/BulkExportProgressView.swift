import SwiftUI

// Modal progress card shown over the list while several workouts are being exported
struct BulkExportProgressView: View {
    @ObservedObject var exporter: BulkExporter
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: Double(exporter.completed), total: Double(max(exporter.total, 1)))
                    .progressViewStyle(.linear)
                
                Text("Exporting \(min(exporter.completed + 1, exporter.total)) of \(exporter.total)")
                    .font(.headline)
                
                if let workout = exporter.currentWorkout {
                    Text("\(workoutActivityTypeString(workout.workoutActivityType)) · \(dateFormatter.string(from: workout.startDate))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Button("Cancel", role: .cancel) {
                    exporter.cancel()
                }
                .accessibilityIdentifier("cancel-export-button")
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
        .accessibilityIdentifier("bulk-export-progress")
    }
}
