import Foundation

// A time-ordered series of scalar sensor readings (heart rate, cadence, power…)
struct SensorSeries {
    struct Sample {
        let date: Date
        let value: Double
    }
    
    // Samples sorted by date ascending
    private(set) var samples: [Sample]
    
    init(samples: [Sample] = []) {
        self.samples = samples.sorted { $0.date < $1.date }
    }
    
    var isEmpty: Bool { samples.isEmpty }
    var count: Int { samples.count }
    
    var average: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }
    
    var maximum: Double? {
        samples.map(\.value).max()
    }
    
    // Value of the sample closest in time to `date`, if one exists within `tolerance` seconds
    func value(at date: Date, tolerance: TimeInterval) -> Double? {
        guard !samples.isEmpty else { return nil }
        
        // Binary search for the first sample at or after `date`
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        var best: Sample?
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        for index in [low - 1, low] where index >= 0 && index < samples.count {
            let distance = abs(samples[index].date.timeIntervalSince(date))
            if distance < bestDistance {
                bestDistance = distance
                best = samples[index]
            }
        }
        
        guard let match = best, bestDistance <= tolerance else { return nil }
        return match.value
    }
}

// Sensor data recorded during a workout, used to enrich GPX exports
struct WorkoutSensorData {
    var heartRate = SensorSeries()       // beats per minute
    var cyclingCadence = SensorSeries()  // revolutions per minute
    var power = SensorSeries()           // watts (running or cycling power)
    
    var isEmpty: Bool {
        heartRate.isEmpty && cyclingCadence.isEmpty && power.isEmpty
    }
}
