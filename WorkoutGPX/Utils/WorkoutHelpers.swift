import HealthKit
import Foundation

func workoutActivityTypeString(_ type: HKWorkoutActivityType) -> String {
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

func workoutIcon(for type: HKWorkoutActivityType) -> String {
    switch type {
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

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

let durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter
}()