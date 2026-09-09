import Foundation
import HealthKit

extension HealthStore {
    // Async form of fetchRouteData(for:completion:). An empty array means the workout
    // has no GPS route; errors from HealthKit are thrown as-is. The completion-based
    // method can report an error more than once when several routes fail, so only the
    // first callback resumes the continuation.
    func fetchRouteData(for workout: HKWorkout) async throws -> [RouteSegment] {
        let lock = NSLock()
        var resumed = false
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[RouteSegment], Error>) in
            fetchRouteData(for: workout) { segments, error in
                lock.lock()
                let first = !resumed
                resumed = true
                lock.unlock()
                guard first else { return }
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: segments ?? [])
                }
            }
        }
    }
}
