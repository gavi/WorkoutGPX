import SwiftUI
import HealthKit

// Row showing workout information
struct WorkoutRow: View {
    let workout: HKWorkout
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: workoutIcon(for: workout.workoutActivityType))
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading) {
                    Text(workoutActivityTypeString(workout.workoutActivityType))
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
}