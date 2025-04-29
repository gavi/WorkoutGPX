import HealthKit
import CoreLocation

// Health Store for managing HealthKit data
class HealthStore: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var authorized = false
    @Published var workouts: [HKWorkout] = []
    
    // Store sample tracks for simulator use
    private var sampleTracks: [GPXTrack] = []
    // Store locations for sample workouts
    private var sampleLocations: [UUID: [CLLocation]] = [:]
    
    private let isRunningInSimulator: Bool = {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }()
    
    private let relevantWorkoutTypes: [HKWorkoutActivityType] = [
        .running,
        .walking,
        .hiking,
        .cycling
    ]
    
    init() {
        if isRunningInSimulator {
            loadSampleData()
            // Set authorized to true for simulator
            self.authorized = true
        }
    }
    
    private func loadSampleData() {
        sampleTracks = GPXParser.loadSampleTracks()
        
        // In simulator mode, directly populate the workouts array
        var simulatedWorkouts: [HKWorkout] = []
        
        // Store locations for each track
        for track in sampleTracks {
            let uuid = UUID()
            // Store locations with a generated UUID as key
            sampleLocations[uuid] = track.locations
            
            // Create a simulated workout
            let workout = HKWorkout(
                activityType: track.workoutType,
                start: Date().addingTimeInterval(-3600), // 1 hour ago
                end: Date(),
                duration: 3600,
                totalEnergyBurned: nil,
                totalDistance: nil,
                metadata: [
                    "name": track.name,
                    "source": "GPX Sample",
                    "trackUUID": uuid.uuidString
                ]
            )
            
            simulatedWorkouts.append(workout)
        }
        
        // Set the workouts array directly
        self.workouts = simulatedWorkouts
        
        print("Loaded \(sampleTracks.count) sample tracks for simulator use")
    }
    
    @MainActor
    func requestAuthorization() async {
        // If running in simulator, use sample data instead
        if isRunningInSimulator {
            print("Running in simulator, using sample data instead of HealthKit")
            self.authorized = true
            return
        }
        
        // Check if HealthKit is available on this device
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            self.authorized = false
            return
        }
        
        // Define the types to read
        let typesToRead: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        
        do {
            // Request authorization using async/await
            try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: typesToRead)
            
            // After requesting authorization, we need to check if we actually have read access
            // We'll try to do a test query to confirm access
            await checkAuthorization()
            
        } catch {
            print("Authorization request failed: \(error.localizedDescription)")
            self.authorized = false
        }
    }
    
    @MainActor
    func checkAuthorization() async {
        // If running in simulator, use sample data instead
        if isRunningInSimulator {
            self.authorized = true
            return
        }
        
        // First check the reported status
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        
        print("HealthKit authorization status for workouts: \(status)")
        
        if status == .notDetermined {
            // If status is not determined, we definitely don't have access
            print("HealthKit access not determined yet")
            self.authorized = false
            return
        }
        
        // Even if status is sharingDenied, we might still have read access
        // Let's test with a sample query to be sure
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: lastMonth, end: Date(), options: [])
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    continuation.resume(returning: samples ?? [])
                }
                
                self.healthStore.execute(query)
            }
            
            // If we get here without error, we have read access
            // Note: This can return an empty array even if we have access
            print("Successfully queried HealthKit, found \(samples.count) samples")
            self.authorized = true
            
        } catch {
            print("Error testing HealthKit access: \(error.localizedDescription)")
            // If we get an error performing the query, we likely don't have access
            self.authorized = false
        }
    }
    
    @MainActor
    func fetchWorkouts() async {
        // Default to fetching last 3 years of workouts
        let calendar = Calendar.current
        let threeYearsAgo = calendar.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        
        await fetchWorkouts(
            startDate: threeYearsAgo,
            endDate: Date(),
            workoutTypes: Set(relevantWorkoutTypes),
            limit: 500
        )
    }
    
    @MainActor
    func fetchWorkouts(
        startDate: Date,
        endDate: Date,
        workoutTypes: Set<HKWorkoutActivityType>,
        limit: Int = 500
    ) async {
        // If running in simulator, we already loaded the workouts in init
        if isRunningInSimulator {
            // In simulator mode, we'll ignore filters and just use all samples
            // This ensures we always show data regardless of filter settings
            
            // Just make sure workouts are sorted by date (most recent first)
            self.workouts = self.workouts.sorted { $0.startDate > $1.startDate }
            
            print("Using all \(self.workouts.count) sample workouts for simulator (ignoring filters)")
            return
        }
        
        // For device, verify we still have access
        await checkAuthorization()
        
        guard authorized else {
            print("Not authorized to fetch workouts")
            self.workouts = []
            return
        }
        
        // Time range predicate
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        // Workout type predicates
        let typesPredicates = workoutTypes.map { type in
            HKQuery.predicateForWorkouts(with: type)
        }
        
        // Combine all predicates
        var predicates: [NSPredicate] = [datePredicate]
        if !typesPredicates.isEmpty {
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typesPredicates))
        }
        
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        do {
            // Using async/await pattern for the query
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: finalPredicate,
                    limit: limit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let samples = samples else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    continuation.resume(returning: samples)
                }
                
                self.healthStore.execute(query)
            }
            
            // Update the workouts on the main actor
            self.workouts = samples as? [HKWorkout] ?? []
            print("Successfully fetched \(self.workouts.count) workouts")
            
        } catch {
            print("Error fetching workouts: \(error.localizedDescription)")
            self.workouts = []
        }
    }
    
    func fetchRouteData(for workout: HKWorkout, completion: @escaping ([CLLocation]?, Error?) -> Void) {
        // If running in simulator, use sample data
        if isRunningInSimulator {
            // Try to find GPX track that matches this workout by UUID in metadata
            if let metadata = workout.metadata, 
               let trackUUIDString = metadata["trackUUID"] as? String,
               let trackUUID = UUID(uuidString: trackUUIDString),
               let locations = sampleLocations[trackUUID] {
                print("Found matching locations by UUID for simulator workout")
                completion(locations, nil)
                return
            }
            
            // If no exact match by UUID, try the first track with matching activity type
            // This is a fallback for simulators
            for track in sampleTracks {
                if track.workoutType == workout.workoutActivityType {
                    print("Found matching track by activity type for simulator workout")
                    completion(track.locations, nil)
                    return
                }
            }
            
            // Last resort: just use the first available track
            if let firstTrack = sampleTracks.first {
                print("Using first available track as fallback for simulator workout")
                completion(firstTrack.locations, nil)
                return
            }
            
            // If no match found, return empty array
            print("No tracks found for simulator workout")
            completion([], nil)
            return
        }
        
        // Fetch route data for a specific workout from HealthKit
        let routeType = HKSeriesType.workoutRoute()
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let routeQuery = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { (query, samples, error) in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let routeSamples = samples as? [HKWorkoutRoute], let route = routeSamples.first else {
                completion([], nil)
                return
            }
            
            var allLocations: [CLLocation] = []
            
            let routeDataQuery = HKWorkoutRouteQuery(route: route) { (query, locations, done, error) in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let locations = locations {
                    allLocations.append(contentsOf: locations)
                }
                
                if done {
                    completion(allLocations, nil)
                }
            }
            
            self.healthStore.execute(routeDataQuery)
        }
        
        self.healthStore.execute(routeQuery)
    }
}
