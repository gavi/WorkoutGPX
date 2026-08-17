import HealthKit
import CoreLocation

// Health Store for managing HealthKit data
class HealthStore: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var authorized = false
    @Published var workouts: [HKWorkout] = []
    // UUIDs of fetched workouts that have at least one HealthKit route (i.e. GPS data to export)
    @Published var workoutsWithRoutes: Set<UUID> = []
    
    // Store sample tracks for simulator use
    private var sampleTracks: [RouteTrack] = []
    // Store track data for sample workouts
    private var sampleTrackData: [UUID: RouteTrack] = [:]
    
    private let isRunningInSimulator: Bool = {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }()
    
    // Quantity types (and the units we read them in) that enrich GPX exports.
    // Newer identifiers are only included on OS versions that know about them.
    private var sensorQuantityTypes: [(type: HKQuantityType, unit: HKUnit, keyPath: WritableKeyPath<WorkoutSensorData, SensorSeries>)] {
        var types: [(HKQuantityType, HKUnit, WritableKeyPath<WorkoutSensorData, SensorSeries>)] = []
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.append((heartRate, perMinute, \.heartRate))
        }
        if #available(iOS 16.0, *), let runningPower = HKObjectType.quantityType(forIdentifier: .runningPower) {
            types.append((runningPower, .watt(), \.power))
        }
        if #available(iOS 17.0, *) {
            if let cyclingPower = HKObjectType.quantityType(forIdentifier: .cyclingPower) {
                types.append((cyclingPower, .watt(), \.power))
            }
            if let cyclingCadence = HKObjectType.quantityType(forIdentifier: .cyclingCadence) {
                types.append((cyclingCadence, perMinute, \.cyclingCadence))
            }
        }
        return types
    }
    
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
        
        // Store track data for each track
        for track in sampleTracks {
            let uuid = UUID()
            // Store track with a generated UUID as key
            sampleTrackData[uuid] = track
            
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
        
        // Define the types to read: workouts, their routes, and the sensor data used to enrich GPX
        var typesToRead: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        for sensor in sensorQuantityTypes {
            typesToRead.insert(sensor.type)
        }
        
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
            endDate: Date()
        )
    }
    
    // Fetches every workout in the date range. Pass `workoutTypes` to restrict by
    // activity type; nil (the default) fetches all types. There is deliberately no
    // result cap so long histories are never silently truncated.
    @MainActor
    func fetchWorkouts(
        startDate: Date,
        endDate: Date,
        workoutTypes: Set<HKWorkoutActivityType>? = nil,
        limit: Int = HKObjectQueryNoLimit
    ) async {
        // If running in simulator, we already loaded the workouts in init
        if isRunningInSimulator {
            // In simulator mode, we'll ignore filters and just use all samples
            // This ensures we always show data regardless of filter settings
            
            // Just make sure workouts are sorted by date (most recent first)
            self.workouts = self.workouts.sorted { $0.startDate > $1.startDate }
            // Every sample workout is backed by a GPX track
            self.workoutsWithRoutes = Set(self.workouts.map(\.uuid))
            
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
        
        // Workout type predicates (only when restricting to specific types)
        var predicates: [NSPredicate] = [datePredicate]
        if let workoutTypes = workoutTypes, !workoutTypes.isEmpty {
            let typesPredicates = workoutTypes.map { HKQuery.predicateForWorkouts(with: $0) }
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
            
            // Work out which of them actually have GPS routes
            self.workoutsWithRoutes = await fetchRouteAvailability(for: self.workouts, startDate: startDate, endDate: endDate)
            print("\(self.workoutsWithRoutes.count) of them have route data")
            
        } catch {
            print("Error fetching workouts: \(error.localizedDescription)")
            self.workouts = []
        }
    }
    
    func fetchRouteData(for workout: HKWorkout, completion: @escaping ([RouteSegment]?, Error?) -> Void) {
        // If running in simulator, use sample data
        if isRunningInSimulator {
            // Try to find GPX track that matches this workout by UUID in metadata
            if let metadata = workout.metadata, 
               let trackUUIDString = metadata["trackUUID"] as? String,
               let trackUUID = UUID(uuidString: trackUUIDString),
               let track = sampleTrackData[trackUUID] {
                print("Found matching track by UUID for simulator workout")
                completion(track.segments, nil)
                return
            }
            
            // If no exact match by UUID, try the first track with matching activity type
            // This is a fallback for simulators
            for track in sampleTracks {
                if track.workoutType == workout.workoutActivityType {
                    print("Found matching track by activity type for simulator workout")
                    completion(track.segments, nil)
                    return
                }
            }
            
            // Last resort: just use the first available track
            if let firstTrack = sampleTracks.first {
                print("Using first available track as fallback for simulator workout")
                completion(firstTrack.segments, nil)
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
            
            // Treat each route as a segment
            guard let routeSamples = samples as? [HKWorkoutRoute] else {
                completion([], nil)
                return
            }
            
            // Early return if no routes
            if routeSamples.isEmpty {
                completion([], nil)
                return
            }
            
            // Set up for multiple route processing
            var segments: [RouteSegment] = []
            var pendingRoutes = routeSamples.count
            
            // Process each route separately
            for route in routeSamples {
                var segmentLocations: [CLLocation] = []
                
                let routeDataQuery = HKWorkoutRouteQuery(route: route) { (query, locations, done, error) in
                    if let error = error {
                        pendingRoutes = 0  // Cancel everything on error
                        completion(nil, error)
                        return
                    }
                    
                    if let locations = locations {
                        segmentLocations.append(contentsOf: locations)
                    }
                    
                    if done {
                        // Create a segment from this route's locations
                        let segment = RouteSegment(locations: segmentLocations)
                        segments.append(segment)
                        
                        // Decrement pending routes counter
                        pendingRoutes -= 1
                        
                        // If all routes have been processed, return the segments
                        if pendingRoutes == 0 {
                            completion(segments, nil)
                        }
                    }
                }
                
                self.healthStore.execute(routeDataQuery)
            }
        }
        
        self.healthStore.execute(routeQuery)
    }

    // MARK: - Route availability
    
    // Determines which workouts have route (GPS) data using a single query for all
    // routes in the range, matched back to workouts by time containment and source.
    // HealthKit exposes no reverse link from a route to its workout, and querying
    // per workout would mean thousands of round trips for long histories.
    private func fetchRouteAvailability(for workouts: [HKWorkout], startDate: Date, endDate: Date) async -> Set<UUID> {
        guard !workouts.isEmpty else { return [] }
        
        // Routes overlapping the range (no strict options: a workout that starts inside
        // the range may end after it)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    print("Error fetching routes: \(error.localizedDescription)")
                }
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            self.healthStore.execute(query)
        }
        
        return HealthStore.matchRoutes(routes, to: workouts)
    }
    
    // Matches routes to workouts. A route belongs to a workout when it lies within the
    // workout's time span (with a small tolerance). If several workouts qualify (e.g. two
    // apps recorded the same run), the one written by the same source wins; failing that,
    // the workout with the largest time overlap.
    static func matchRoutes(_ routes: [HKWorkoutRoute], to workouts: [HKWorkout], tolerance: TimeInterval = 60) -> Set<UUID> {
        guard !routes.isEmpty, !workouts.isEmpty else { return [] }
        
        let sortedWorkouts = workouts.sorted { $0.startDate < $1.startDate }
        var matched = Set<UUID>()
        
        for route in routes {
            var candidates: [HKWorkout] = []
            for workout in sortedWorkouts {
                if workout.startDate > route.endDate.addingTimeInterval(tolerance) { break }
                let containsStart = workout.startDate.addingTimeInterval(-tolerance) <= route.startDate
                let containsEnd = route.endDate <= workout.endDate.addingTimeInterval(tolerance)
                if containsStart && containsEnd {
                    candidates.append(workout)
                }
            }
            
            guard !candidates.isEmpty else { continue }
            
            let routeSource = route.sourceRevision.source.bundleIdentifier
            let sameSource = candidates.filter { $0.sourceRevision.source.bundleIdentifier == routeSource }
            
            if !sameSource.isEmpty {
                sameSource.forEach { matched.insert($0.uuid) }
            } else if let best = candidates.max(by: { overlap($0, route) < overlap($1, route) }) {
                matched.insert(best.uuid)
            }
        }
        
        return matched
    }
    
    private static func overlap(_ workout: HKWorkout, _ route: HKWorkoutRoute) -> TimeInterval {
        let start = max(workout.startDate, route.startDate)
        let end = min(workout.endDate, route.endDate)
        return max(0, end.timeIntervalSince(start))
    }
    
    // MARK: - Sensor data
    
    // Fetches heart rate, cadence and power series recorded during a workout.
    // Samples associated with the workout are preferred; if the recording app did not
    // associate any, samples that overlap the workout's time range are used instead.
    func fetchSensorData(for workout: HKWorkout) async -> WorkoutSensorData {
        var data = WorkoutSensorData()
        
        // Sample workouts in the simulator carry no sensor data
        guard !isRunningInSimulator, HKHealthStore.isHealthDataAvailable() else {
            return data
        }
        
        for sensor in sensorQuantityTypes {
            var samples = await fetchQuantitySeries(
                of: sensor.type,
                unit: sensor.unit,
                predicate: HKQuery.predicateForObjects(from: workout)
            )
            
            if samples.isEmpty {
                samples = await fetchQuantitySeries(
                    of: sensor.type,
                    unit: sensor.unit,
                    predicate: HKQuery.predicateForSamples(
                        withStart: workout.startDate,
                        end: workout.endDate,
                        options: []
                    )
                )
            }
            
            guard !samples.isEmpty else { continue }
            
            // Merge into any existing series (e.g. running and cycling power share a slot)
            let existing = data[keyPath: sensor.keyPath].samples
            data[keyPath: sensor.keyPath] = SensorSeries(samples: existing + samples)
        }
        
        return data
    }
    
    // Enumerates every value in matching quantity samples, including series samples
    // (Apple Watch stores workout heart rate as series), as (date, value) pairs.
    private func fetchQuantitySeries(
        of quantityType: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> [SensorSeries.Sample] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[SensorSeries.Sample], Never>) in
            var collected: [SensorSeries.Sample] = []
            var finished = false
            
            let query = HKQuantitySeriesSampleQuery(quantityType: quantityType, predicate: predicate) { _, quantity, dateInterval, _, done, error in
                if finished { return }
                
                if let error = error {
                    print("Error reading \(quantityType.identifier): \(error.localizedDescription)")
                    finished = true
                    continuation.resume(returning: collected)
                    return
                }
                
                if let quantity = quantity, let dateInterval = dateInterval {
                    collected.append(SensorSeries.Sample(date: dateInterval.start, value: quantity.doubleValue(for: unit)))
                }
                
                if done {
                    finished = true
                    continuation.resume(returning: collected)
                }
            }
            
            self.healthStore.execute(query)
        }
    }
}
