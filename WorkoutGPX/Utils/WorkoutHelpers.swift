import HealthKit
import Foundation

// Human-readable name for a workout activity type
func workoutActivityTypeString(_ type: HKWorkoutActivityType) -> String {
    switch type {
    case .running: return "Running"
    case .walking: return "Walking"
    case .hiking: return "Hiking"
    case .cycling: return "Cycling"
    case .handCycling: return "Hand Cycling"
    case .wheelchairWalkPace: return "Wheelchair Walk"
    case .wheelchairRunPace: return "Wheelchair Run"
    case .swimming: return "Swimming"
    case .paddleSports: return "Paddling"
    case .rowing: return "Rowing"
    case .sailing: return "Sailing"
    case .surfingSports: return "Surfing"
    case .waterFitness: return "Water Fitness"
    case .waterPolo: return "Water Polo"
    case .waterSports: return "Water Sports"
    case .downhillSkiing: return "Downhill Skiing"
    case .crossCountrySkiing: return "Cross-Country Skiing"
    case .snowboarding: return "Snowboarding"
    case .snowSports: return "Snow Sports"
    case .skatingSports: return "Skating"
    case .golf: return "Golf"
    case .equestrianSports: return "Equestrian"
    case .fishing: return "Fishing"
    case .hunting: return "Hunting"
    case .climbing: return "Climbing"
    case .elliptical: return "Elliptical"
    case .stairClimbing: return "Stair Climbing"
    case .stairs: return "Stairs"
    case .stepTraining: return "Step Training"
    case .jumpRope: return "Jump Rope"
    case .functionalStrengthTraining: return "Functional Strength"
    case .traditionalStrengthTraining: return "Strength Training"
    case .coreTraining: return "Core Training"
    case .crossTraining: return "Cross Training"
    case .mixedCardio: return "Mixed Cardio"
    case .highIntensityIntervalTraining: return "HIIT"
    case .yoga: return "Yoga"
    case .pilates: return "Pilates"
    case .taiChi: return "Tai Chi"
    case .flexibility: return "Flexibility"
    case .cooldown: return "Cooldown"
    case .preparationAndRecovery: return "Recovery"
    case .mindAndBody: return "Mind & Body"
    case .barre: return "Barre"
    case .dance: return "Dance"
    case .socialDance: return "Social Dance"
    case .cardioDance: return "Cardio Dance"
    case .boxing: return "Boxing"
    case .kickboxing: return "Kickboxing"
    case .martialArts: return "Martial Arts"
    case .wrestling: return "Wrestling"
    case .fencing: return "Fencing"
    case .archery: return "Archery"
    case .soccer: return "Soccer"
    case .americanFootball: return "American Football"
    case .australianFootball: return "Australian Football"
    case .rugby: return "Rugby"
    case .basketball: return "Basketball"
    case .baseball: return "Baseball"
    case .softball: return "Softball"
    case .cricket: return "Cricket"
    case .hockey: return "Hockey"
    case .lacrosse: return "Lacrosse"
    case .volleyball: return "Volleyball"
    case .handball: return "Handball"
    case .tennis: return "Tennis"
    case .tableTennis: return "Table Tennis"
    case .badminton: return "Badminton"
    case .squash: return "Squash"
    case .racquetball: return "Racquetball"
    case .pickleball: return "Pickleball"
    case .discSports: return "Disc Sports"
    case .bowling: return "Bowling"
    case .curling: return "Curling"
    case .gymnastics: return "Gymnastics"
    case .trackAndField: return "Track & Field"
    case .play: return "Play"
    case .fitnessGaming: return "Fitness Gaming"
    case .other: return "Other"
    default: return "Workout"
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
