import HealthKit
import CoreLocation

// Health Store for managing HealthKit data
class HealthStore: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var authorized = false
    @Published var workouts: [HKWorkout] = []
    
    private let relevantWorkoutTypes: [HKWorkoutActivityType] = [
        .running,
        .walking,
        .hiking,
        .cycling
    ]
    
    init() {}
    
    @MainActor
    func requestAuthorization() async {
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
        // First, verify we still have access
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
        // Fetch route data for a specific workout
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
