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
        // Define the types to read
        let typesToRead: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        
        do {
            // Request authorization using async/await
            try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: typesToRead)
            self.authorized = true
            // Fetch workouts immediately after authorization
            await self.fetchWorkouts()
        } catch {
            print("Authorization failed: \(error.localizedDescription)")
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
        guard authorized else {
            print("Not authorized to fetch workouts")
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
            
        } catch {
            print("Error fetching workouts: \(error.localizedDescription)")
            // Ensure we don't leave the workouts array empty if there's an error
            if self.workouts.isEmpty {
                self.workouts = []
            }
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