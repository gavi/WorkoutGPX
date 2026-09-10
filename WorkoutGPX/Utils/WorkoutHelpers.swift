import HealthKit
import Foundation

// Human-readable name for a workout activity type
func workoutActivityTypeString(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running: return String(localized: "Running")
    case .walking: return String(localized: "Walking")
    case .hiking: return String(localized: "Hiking")
    case .cycling: return String(localized: "Cycling")
    case .handCycling: return String(localized: "Hand Cycling")
    case .wheelchairWalkPace: return String(localized: "Wheelchair Walk")
    case .wheelchairRunPace: return String(localized: "Wheelchair Run")
    case .swimming: return String(localized: "Swimming")
    case .paddleSports: return String(localized: "Paddling")
    case .rowing: return String(localized: "Rowing")
    case .sailing: return String(localized: "Sailing")
    case .surfingSports: return String(localized: "Surfing")
    case .waterFitness: return String(localized: "Water Fitness")
    case .waterPolo: return String(localized: "Water Polo")
    case .waterSports: return String(localized: "Water Sports")
    case .downhillSkiing: return String(localized: "Downhill Skiing")
    case .crossCountrySkiing: return String(localized: "Cross-Country Skiing")
    case .snowboarding: return String(localized: "Snowboarding")
    case .snowSports: return String(localized: "Snow Sports")
    case .skatingSports: return String(localized: "Skating")
    case .golf: return String(localized: "Golf")
    case .equestrianSports: return String(localized: "Equestrian")
    case .fishing: return String(localized: "Fishing")
    case .hunting: return String(localized: "Hunting")
    case .climbing: return String(localized: "Climbing")
    case .elliptical: return String(localized: "Elliptical")
    case .stairClimbing: return String(localized: "Stair Climbing")
    case .stairs: return String(localized: "Stairs")
    case .stepTraining: return String(localized: "Step Training")
    case .jumpRope: return String(localized: "Jump Rope")
    case .functionalStrengthTraining: return String(localized: "Functional Strength")
    case .traditionalStrengthTraining: return String(localized: "Strength Training")
    case .coreTraining: return String(localized: "Core Training")
    case .crossTraining: return String(localized: "Cross Training")
    case .mixedCardio: return String(localized: "Mixed Cardio")
    case .highIntensityIntervalTraining: return String(localized: "HIIT")
    case .yoga: return String(localized: "Yoga")
    case .pilates: return String(localized: "Pilates")
    case .taiChi: return String(localized: "Tai Chi")
    case .flexibility: return String(localized: "Flexibility")
    case .cooldown: return String(localized: "Cooldown")
    case .preparationAndRecovery: return String(localized: "Recovery")
    case .mindAndBody: return String(localized: "Mind & Body")
    case .barre: return String(localized: "Barre")
    case .dance: return String(localized: "Dance")
    case .socialDance: return String(localized: "Social Dance")
    case .cardioDance: return String(localized: "Cardio Dance")
    case .boxing: return String(localized: "Boxing")
    case .kickboxing: return String(localized: "Kickboxing")
    case .martialArts: return String(localized: "Martial Arts")
    case .wrestling: return String(localized: "Wrestling")
    case .fencing: return String(localized: "Fencing")
    case .archery: return String(localized: "Archery")
    case .soccer: return String(localized: "Soccer")
    case .americanFootball: return String(localized: "American Football")
    case .australianFootball: return String(localized: "Australian Football")
    case .rugby: return String(localized: "Rugby")
    case .basketball: return String(localized: "Basketball")
    case .baseball: return String(localized: "Baseball")
    case .softball: return String(localized: "Softball")
    case .cricket: return String(localized: "Cricket")
    case .hockey: return String(localized: "Hockey")
    case .lacrosse: return String(localized: "Lacrosse")
    case .volleyball: return String(localized: "Volleyball")
    case .handball: return String(localized: "Handball")
    case .tennis: return String(localized: "Tennis")
    case .tableTennis: return String(localized: "Table Tennis")
    case .badminton: return String(localized: "Badminton")
    case .squash: return String(localized: "Squash")
    case .racquetball: return String(localized: "Racquetball")
    case .pickleball: return String(localized: "Pickleball")
    case .discSports: return String(localized: "Disc Sports")
    case .bowling: return String(localized: "Bowling")
    case .curling: return String(localized: "Curling")
    case .gymnastics: return String(localized: "Gymnastics")
    case .trackAndField: return String(localized: "Track & Field")
    case .play: return String(localized: "Play")
    case .fitnessGaming: return String(localized: "Fitness Gaming")
    case .other: return String(localized: "Other")
    default: return String(localized: "Workout")
    }
}

// SF Symbol name for a workout activity type
func workoutIcon(for type: HKWorkoutActivityType) -> String {
    switch type {
    case .running: return "figure.run"
    case .walking: return "figure.walk"
    case .hiking: return "mountain.2"
    case .cycling, .handCycling: return "figure.outdoor.cycle"
    case .wheelchairWalkPace, .wheelchairRunPace: return "figure.roll"
    case .swimming, .waterFitness, .waterPolo, .waterSports: return "figure.open.water.swim"
    case .paddleSports: return "oar.2.crossed"
    case .rowing: return "figure.rower"
    case .sailing: return "sailboat"
    case .surfingSports: return "figure.surfing"
    case .downhillSkiing, .snowSports: return "figure.skiing.downhill"
    case .crossCountrySkiing: return "figure.skiing.crosscountry"
    case .snowboarding: return "figure.snowboarding"
    case .skatingSports: return "figure.skating"
    case .golf: return "figure.golf"
    case .equestrianSports: return "figure.equestrian.sports"
    case .fishing: return "figure.fishing"
    case .hunting: return "figure.hunting"
    case .climbing: return "figure.climbing"
    case .elliptical: return "figure.elliptical"
    case .stairClimbing, .stairs, .stepTraining: return "figure.stairs"
    case .jumpRope: return "figure.jumprope"
    case .functionalStrengthTraining, .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
    case .coreTraining: return "figure.core.training"
    case .crossTraining, .mixedCardio: return "figure.mixed.cardio"
    case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
    case .yoga: return "figure.yoga"
    case .pilates: return "figure.pilates"
    case .taiChi: return "figure.taichi"
    case .flexibility, .cooldown, .preparationAndRecovery: return "figure.cooldown"
    case .mindAndBody: return "figure.mind.and.body"
    case .barre: return "figure.barre"
    case .dance, .socialDance, .cardioDance: return "figure.dance"
    case .boxing: return "figure.boxing"
    case .kickboxing: return "figure.kickboxing"
    case .martialArts: return "figure.martial.arts"
    case .wrestling: return "figure.wrestling"
    case .fencing: return "figure.fencing"
    case .archery: return "figure.archery"
    case .soccer: return "figure.soccer"
    case .americanFootball: return "figure.american.football"
    case .australianFootball: return "figure.australian.football"
    case .rugby: return "figure.rugby"
    case .basketball: return "figure.basketball"
    case .baseball, .softball: return "figure.baseball"
    case .cricket: return "figure.cricket"
    case .hockey: return "figure.hockey"
    case .lacrosse: return "figure.lacrosse"
    case .volleyball: return "figure.volleyball"
    case .handball: return "figure.handball"
    case .tennis: return "figure.tennis"
    case .tableTennis: return "figure.table.tennis"
    case .badminton: return "figure.badminton"
    case .squash: return "figure.squash"
    case .racquetball: return "figure.racquetball"
    case .pickleball: return "figure.pickleball"
    case .discSports: return "figure.disc.sports"
    case .bowling: return "figure.bowling"
    case .curling: return "figure.curling"
    case .gymnastics: return "figure.gymnastics"
    case .trackAndField: return "figure.track.and.field"
    case .play: return "figure.play"
    case .fitnessGaming: return "gamecontroller"
    default: return "figure.mixed.cardio"
    }
}

// Lowercase activity string for the GPX <type> element (Garmin/Strava conventions where they exist)
func gpxActivityTypeString(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running, .wheelchairRunPace: return "running"
    case .walking, .wheelchairWalkPace: return "walking"
    case .hiking: return "hiking"
    case .cycling, .handCycling: return "cycling"
    case .swimming: return "swimming"
    case .rowing: return "rowing"
    case .paddleSports: return "paddling"
    case .downhillSkiing: return "alpine_skiing"
    case .crossCountrySkiing: return "cross_country_skiing"
    case .snowboarding: return "snowboarding"
    case .skatingSports: return "skating"
    case .sailing: return "sailing"
    case .golf: return "golf"
    default:
        return workoutActivityTypeString(type)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
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
