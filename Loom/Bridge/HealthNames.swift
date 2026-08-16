import Foundation

// Value-enum case names for HealthKit's NS_ENUMs.
//
// HealthKit's enums import into Swift as RawRepresentable structs, not true enums, so
// String(describing:) yields "HKCategoryValueSleepAnalysis(rawValue: 5)" rather than a
// case name — there is no runtime reflection to lean on. These tables are the irreducible
// remainder of ADR-012's no-table design, and they are *generated from the iOS 27 SDK
// headers*, not hand-typed. A value with no entry is returned to JS as its raw integer.
nonisolated enum HealthNames {
    static let sleepAnalysis: [Int: String] = [
        0: "inBed", 1: "asleepUnspecified", 2: "awake", 3: "asleepCore", 4: "asleepDeep", 5: "asleepREM"
    ]
    static let stateOfMindKind: [Int: String] = [
        1: "momentaryEmotion", 2: "dailyMood"
    ]
    static let valenceClassification: [Int: String] = [
        1: "veryUnpleasant", 2: "unpleasant", 3: "slightlyUnpleasant", 4: "neutral", 5: "slightlyPleasant", 6: "pleasant", 7: "veryPleasant"
    ]
    static let stateOfMindLabel: [Int: String] = [
        1: "amazed", 2: "amused", 3: "angry", 4: "anxious", 5: "ashamed", 6: "brave", 7: "calm", 8: "content", 9: "disappointed", 10: "discouraged", 11: "disgusted", 12: "embarrassed", 13: "excited", 14: "frustrated", 15: "grateful", 16: "guilty", 17: "happy", 18: "hopeless", 19: "irritated", 20: "jealous", 21: "joyful", 22: "lonely", 23: "passionate", 24: "peaceful", 25: "proud", 26: "relieved", 27: "sad", 28: "scared", 29: "stressed", 30: "surprised", 31: "worried", 32: "annoyed", 33: "confident", 34: "drained", 35: "hopeful", 36: "indifferent", 37: "overwhelmed", 38: "satisfied"
    ]
    static let stateOfMindAssociation: [Int: String] = [
        1: "community", 2: "currentEvents", 3: "dating", 4: "education", 5: "family", 6: "fitness", 7: "friends", 8: "health", 9: "hobbies", 10: "identity", 11: "money", 12: "partner", 13: "selfCare", 14: "spirituality", 15: "tasks", 16: "travel", 17: "work", 18: "weather"
    ]
    static let workoutActivity: [Int: String] = [
        1: "americanFootball", 2: "archery", 3: "australianFootball", 4: "badminton", 5: "baseball", 6: "basketball", 7: "bowling", 8: "boxing", 9: "climbing", 10: "cricket", 11: "crossTraining", 12: "curling", 13: "cycling", 14: "dance", 15: "danceInspiredTraining", 16: "elliptical", 17: "equestrianSports", 18: "fencing", 19: "fishing", 20: "functionalStrengthTraining", 21: "golf", 22: "gymnastics", 23: "handball", 24: "hiking", 25: "hockey", 26: "hunting", 27: "lacrosse", 28: "martialArts", 29: "mindAndBody", 30: "mixedMetabolicCardioTraining", 31: "paddleSports", 32: "play", 33: "preparationAndRecovery", 34: "racquetball", 35: "rowing", 36: "rugby", 37: "running", 38: "sailing", 39: "skatingSports", 40: "snowSports", 41: "soccer", 42: "softball", 43: "squash", 44: "stairClimbing", 45: "surfingSports", 46: "swimming", 47: "tableTennis", 48: "tennis", 49: "trackAndField", 50: "traditionalStrengthTraining", 51: "volleyball", 52: "walking", 53: "waterFitness", 54: "waterPolo", 55: "waterSports", 56: "wrestling", 57: "yoga", 58: "barre", 59: "coreTraining", 60: "crossCountrySkiing", 61: "downhillSkiing", 62: "flexibility", 63: "highIntensityIntervalTraining", 64: "jumpRope", 65: "kickboxing", 66: "pilates", 67: "snowboarding", 68: "stairs", 69: "stepTraining", 70: "wheelchairWalkPace", 71: "wheelchairRunPace", 72: "taiChi", 73: "mixedCardio", 74: "handCycling", 75: "discSports", 76: "fitnessGaming", 77: "cardioDance", 78: "socialDance", 79: "pickleball", 80: "cooldown", 82: "swimBikeRun", 83: "transition", 84: "underwaterDiving", 2998: "rest", 2999: "group", 3000: "other"
    ]
    static let biologicalSex: [Int: String] = [
        0: "notSet", 1: "female", 2: "male", 3: "other"
    ]
    static let bloodType: [Int: String] = [
        0: "notSet", 1: "aPositive", 2: "aNegative", 3: "bPositive", 4: "bNegative", 5: "aBPositive", 6: "aBNegative", 7: "oPositive", 8: "oNegative"
    ]
    static let fitzpatrickSkinType: [Int: String] = [
        0: "notSet", 1: "i", 2: "iI", 3: "iII", 4: "iV", 5: "v", 6: "vI"
    ]
    static let wheelchairUse: [Int: String] = [
        0: "notSet", 1: "no", 2: "yes"
    ]
    static let activityMoveMode: [Int: String] = [
        1: "activeEnergy", 2: "appleMoveTime"
    ]
    static let ecgClassification: [Int: String] = [
        0: "notSet", 1: "sinusRhythm", 2: "atrialFibrillation", 3: "inconclusiveLowHeartRate", 4: "inconclusiveHighHeartRate", 5: "inconclusivePoorReading", 6: "inconclusiveOther", 100: "unrecognized"
    ]
    static let ecgSymptomsStatus: [Int: String] = [
        0: "notSet", 1: "none", 2: "present"
    ]
    static let gad7Risk: [Int: String] = [
        1: "noneToMinimal", 2: "mild", 3: "moderate", 4: "severe"
    ]
    static let phq9Risk: [Int: String] = [
        1: "noneToMinimal", 2: "mild", 3: "moderate", 4: "moderatelySevere", 5: "severe"
    ]
    static let appetiteChanges: [Int: String] = [
        0: "unspecified", 1: "noChange", 2: "decreased", 3: "increased"
    ]
    static let appleStandHour: [Int: String] = [
        0: "stood", 1: "idle"
    ]
    static let appleWalkingSteadinessEvent: [Int: String] = [
        1: "initialLow", 2: "initialVeryLow", 3: "repeatLow", 4: "repeatVeryLow"
    ]
    static let cervicalMucusQuality: [Int: String] = [
        1: "dry", 2: "sticky", 3: "creamy", 4: "watery", 5: "eggWhite"
    ]
    static let contraceptive: [Int: String] = [
        1: "unspecified", 2: "implant", 3: "injection", 4: "intrauterineDevice", 5: "intravaginalRing", 6: "oral", 7: "patch"
    ]
    static let environmentalAudioExposureEvent: [Int: String] = [
        1: "momentaryLimit"
    ]
    static let headphoneAudioExposureEvent: [Int: String] = [
        1: "sevenDayLimit"
    ]
    static let lowCardioFitnessEvent: [Int: String] = [
        1: "lowFitness"
    ]
    static let menopausalState: [Int: String] = [
        1: "menopause", 2: "perimenopause", 3: "none"
    ]
    static let ovulationTestResult: [Int: String] = [
        1: "negative", 2: "luteinizingHormoneSurge", 3: "indeterminate", 4: "estrogenSurge"
    ]
    static let pregnancyTestResult: [Int: String] = [
        1: "negative", 2: "positive", 3: "indeterminate"
    ]
    static let presence: [Int: String] = [
        0: "present", 1: "notPresent"
    ]
    static let progesteroneTestResult: [Int: String] = [
        1: "negative", 2: "positive", 3: "indeterminate"
    ]
    static let severity: [Int: String] = [
        0: "unspecified", 1: "notPresent", 2: "mild", 3: "moderate", 4: "severe"
    ]
    static let vaginalBleeding: [Int: String] = [
        1: "unspecified", 2: "light", 3: "medium", 4: "heavy", 5: "none"
    ]
}
