import Foundation
import HealthKit

// One workout that produced no file during a bulk export, with the reason shown to the user
struct SkippedWorkout: Identifiable {
    let workout: HKWorkout
    let reason: String
    var id: UUID { workout.uuid }
}

// What a bulk export produced
struct BulkExportResult {
    var fileURLs: [URL] = []
    var skipped: [SkippedWorkout] = []
    var requested: Int = 0
    var wasCancelled: Bool = false
}

// Exports several workouts one after another so the list can offer "select many, share once".
// Route and sensor fetches run sequentially: the share sheet needs every file before it
// opens, and HealthKit route queries are quick enough that parallelism buys nothing visible.
@MainActor
final class BulkExporter: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completed: Int = 0
    @Published private(set) var total: Int = 0
    @Published private(set) var currentWorkout: HKWorkout?
    
    private var task: Task<BulkExportResult, Never>?
    
    func export(_ workouts: [HKWorkout], using healthStore: HealthStore, options: GPXExportOptions) async -> BulkExportResult {
        if let running = task {
            return await running.value
        }
        
        isRunning = true
        completed = 0
        total = workouts.count
        currentWorkout = nil
        
        let work = Task<BulkExportResult, Never> { [weak self] in
            var result = BulkExportResult(requested: workouts.count)
            
            for workout in workouts {
                if Task.isCancelled {
                    result.wasCancelled = true
                    break
                }
                self?.currentWorkout = workout
                
                let segments: [RouteSegment]
                do {
                    segments = try await healthStore.fetchRouteData(for: workout)
                } catch {
                    result.skipped.append(SkippedWorkout(workout: workout, reason: error.localizedDescription))
                    self?.completed += 1
                    continue
                }
                
                if segments.isEmpty {
                    result.skipped.append(SkippedWorkout(workout: workout, reason: "No GPS data"))
                    self?.completed += 1
                    continue
                }
                
                let sensorData: WorkoutSensorData = options.includeSensorData
                    ? await healthStore.fetchSensorData(for: workout)
                    : WorkoutSensorData()
                
                // Serialising a long track is real work; keep it off the main actor
                let url: URL? = await Task.detached(priority: .userInitiated) {
                    exportGPX(for: workout, trackSegments: segments, sensorData: sensorData, options: options)
                }.value
                
                if let url = url {
                    result.fileURLs.append(url)
                } else {
                    result.skipped.append(SkippedWorkout(workout: workout, reason: "Could not write the file"))
                }
                self?.completed += 1
            }
            
            return result
        }
        
        task = work
        let result = await work.value
        task = nil
        isRunning = false
        currentWorkout = nil
        return result
    }
    
    func cancel() {
        task?.cancel()
    }
}
