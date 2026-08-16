import Foundation
import HealthKit

// Name <-> HKObjectType, with no mapping table.
//
// Every HKObjectType.<family>Type(forIdentifier:) is nullable and returns nil for an
// unrecognised identifier, and identifier raw values are mechanically
// "HK<Family>TypeIdentifier" + PascalCase name. So probing each family in turn is a
// complete resolver for all ~215 types, and new OS releases add types for free.
// See ADR-012.
//
// nonisolated throughout: this is called from the script thread, never the main actor.
nonisolated enum HealthTypes {

    // The types that aren't reachable by identifier string.
    static let singletons: [String: HKObjectType] = [
        "workout":             HKObjectType.workoutType(),
        "stateOfMind":         HKObjectType.stateOfMindType(),
        "electrocardiogram":   HKObjectType.electrocardiogramType(),
        "audiogram":           HKObjectType.audiogramSampleType(),
        "visionPrescription":  HKObjectType.visionPrescriptionType(),
        "medicationDoseEvent": HKObjectType.medicationDoseEventType(),
    ]

    private static let prefixes = [
        "HKQuantityTypeIdentifier",
        "HKCategoryTypeIdentifier",
        "HKCharacteristicTypeIdentifier",
        "HKCorrelationTypeIdentifier",
        "HKClinicalTypeIdentifier",
        "HKDocumentTypeIdentifier",
    ]

    /// Accepts "stepCount", "StepCount", or the full "HKQuantityTypeIdentifierStepCount".
    /// Returns nil for anything HealthKit doesn't recognise.
    static func resolve(_ name: String) -> HKObjectType? {
        guard !name.isEmpty else { return nil }
        if let hit = singletons.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
            return hit.value
        }
        // Only the first character is ever recased, so leading-acronym names round-trip:
        // "vO2Max" -> "VO2Max". Capitalising the whole word would give "Vo2Max" and fail.
        let capitalized = name.prefix(1).uppercased() + name.dropFirst()
        for candidate in (name == capitalized) ? [name] : [name, capitalized] {
            if let t = lookUp(candidate) { return t }
        }
        return nil
    }

    private static func lookUp(_ name: String) -> HKObjectType? {
        func id(_ prefix: String) -> String { name.hasPrefix(prefix) ? name : prefix + name }
        if let t = HKObjectType.quantityType(forIdentifier: .init(rawValue: id(prefixes[0]))) { return t }
        if let t = HKObjectType.categoryType(forIdentifier: .init(rawValue: id(prefixes[1]))) { return t }
        if let t = HKObjectType.characteristicType(forIdentifier: .init(rawValue: id(prefixes[2]))) { return t }
        if let t = HKObjectType.correlationType(forIdentifier: .init(rawValue: id(prefixes[3]))) { return t }
        if let t = HKObjectType.clinicalType(forIdentifier: .init(rawValue: id(prefixes[4]))) { return t }
        if let t = HKObjectType.documentType(forIdentifier: .init(rawValue: id(prefixes[5]))) { return t }
        return nil
    }

    /// The inverse of `resolve` — always round-trips.
    static func shortName(_ type: HKObjectType) -> String {
        if let hit = singletons.first(where: { $0.value.identifier == type.identifier }) { return hit.key }
        let id = type.identifier
        guard let prefix = prefixes.first(where: { id.hasPrefix($0) }) else { return id }
        let suffix = id.dropFirst(prefix.count)
        return suffix.prefix(1).lowercased() + suffix.dropFirst()
    }

    // MARK: - Units

    /// Units a script may name explicitly, and the fallback probe list, in one place.
    ///
    /// HKUnit(from:) raises an uncatchable ObjC exception on an unknown string, so a
    /// JS-supplied unit name is matched against this list rather than passed through.
    /// Probe order matters: the first entry dimensionally compatible with a type wins,
    /// so where two units share a dimension the more common one is listed first.
    static let knownUnits: [HKUnit] = [
        .count(), .count().unitDivided(by: .minute()), .count().unitDivided(by: .second()),
        .percent(), .appleEffortScore(),
        .kilocalorie(), .largeCalorie(), .smallCalorie(), .joule(),
        .meter(), .meterUnit(with: .kilo), .meterUnit(with: .centi), .mile(), .foot(), .inch(), .yard(),
        .gramUnit(with: .kilo), .gram(), .gramUnit(with: .milli), .gramUnit(with: .micro),
        .pound(), .ounce(), .stone(),
        .second(), .secondUnit(with: .milli), .minute(), .hour(), .day(),
        .degreeCelsius(), .degreeFahrenheit(), .kelvin(),
        .millimeterOfMercury(), .pascal(), .atmosphere(), .inchesOfMercury(), .centimeterOfWater(),
        .liter(), .literUnit(with: .milli), .fluidOunceUS(), .cupUS(), .pintUS(),
        .decibelAWeightedSoundPressureLevel(), .decibelHearingLevel(),
        .internationalUnit(), .diopter(), .prismDiopter(), .lux(), .hertz(), .volt(), .watt(),
        .siemen(), .siemenUnit(with: .micro), .degreeAngle(), .radianAngle(),
        .meter().unitDivided(by: .second()),
    ]

    static func unit(named name: String) -> HKUnit? {
        knownUnits.first { $0.unitString == name }
    }

    /// Last-resort unit when the user has no Health-app preference for a type.
    /// ponytail: picks by dimension, so units sharing one (g vs kg) resolve by list order.
    /// The chosen unit is always echoed on the sample, and opts.unit overrides — add a
    /// per-type table only if a real script gets bitten.
    static func probeUnit(for type: HKQuantityType) -> HKUnit {
        knownUnits.first { type.is(compatibleWith: $0) } ?? .count()
    }

    // MARK: - Category values

    /// Decodes an HKCategorySample's Int value to its enum case name.
    /// Nothing at runtime maps a category type to its value enum, so the pairing is a
    /// switch; the names themselves come from HealthNames, generated from the SDK headers.
    /// ponytail: symptom-severity types aren't paired here and fall back to their raw
    /// integer (plus "notApplicable" for 0) — add identifiers if a script needs the names.
    static func categoryValueName(_ type: HKCategoryType, _ value: Int) -> String? {
        let table: [Int: String]?
        switch HKCategoryTypeIdentifier(rawValue: type.identifier) {
        case .sleepAnalysis:                   table = HealthNames.sleepAnalysis
        case .appleStandHour:                  table = HealthNames.appleStandHour
        case .cervicalMucusQuality:            table = HealthNames.cervicalMucusQuality
        case .menstrualFlow:                   table = HealthNames.vaginalBleeding
        case .ovulationTestResult:             table = HealthNames.ovulationTestResult
        case .pregnancyTestResult:             table = HealthNames.pregnancyTestResult
        case .progesteroneTestResult:          table = HealthNames.progesteroneTestResult
        case .contraceptive:                   table = HealthNames.contraceptive
        case .appetiteChanges:                 table = HealthNames.appetiteChanges
        case .appleWalkingSteadinessEvent:     table = HealthNames.appleWalkingSteadinessEvent
        case .environmentalAudioExposureEvent: table = HealthNames.environmentalAudioExposureEvent
        case .headphoneAudioExposureEvent:     table = HealthNames.headphoneAudioExposureEvent
        case .lowCardioFitnessEvent:           table = HealthNames.lowCardioFitnessEvent
        case .menopausalState:                 table = HealthNames.menopausalState
        case .pregnancy, .lactation:           table = HealthNames.presence
        case .bleedingAfterMenopause, .bleedingAfterPregnancy, .bleedingDuringPregnancy:
                                               table = HealthNames.vaginalBleeding
        default:                               table = nil
        }
        return table?[value] ?? (value == 0 ? "notApplicable" : nil)
    }

    // MARK: - Self-check

    #if DEBUG
    /// The whole resolver rests on an HK identifier constant's string value equalling its
    /// own name. That's a stable Apple convention, but it is a convention — pin it here so
    /// a change surfaces at launch rather than as a mystery "unknown type" in a script.
    static func runSelfCheck() {
        assert(HKQuantityTypeIdentifier.stepCount.rawValue == "HKQuantityTypeIdentifierStepCount",
               "HealthKit identifier raw-value convention changed — HealthTypes.resolve is broken")
        assert(HKCategoryTypeIdentifier.sleepAnalysis.rawValue == "HKCategoryTypeIdentifierSleepAnalysis")

        // One name per reachable family must survive resolve -> shortName -> resolve.
        for name in ["stepCount", "vO2Max", "sleepAnalysis", "biologicalSex", "bloodPressure", "workout", "stateOfMind"] {
            guard let type = resolve(name) else { assertionFailure("resolve failed: \(name)"); continue }
            let round = shortName(type)
            assert(round == name, "round-trip changed \(name) -> \(round)")
            assert(resolve(round)?.identifier == type.identifier, "re-resolve failed: \(round)")
        }
        // Capitalised and fully-qualified spellings reach the same type.
        assert(resolve("StepCount")?.identifier == resolve("stepCount")?.identifier)
        assert(resolve("HKQuantityTypeIdentifierStepCount")?.identifier == resolve("stepCount")?.identifier)
        assert(resolve("nonsenseType") == nil, "resolver accepted a bogus type")

        assert(unit(named: "kg") != nil && unit(named: "not-a-unit") == nil)

        // This assertion previously failed and was the thing that caught the real bug:
        // HealthKit's NS_ENUMs import as RawRepresentable structs, so "\(value)" produced
        // "HKCategoryValueSleepAnalysis(rawValue: 5)" and scripts were being handed that
        // string. Names now come from HealthNames (generated from the SDK headers), so the
        // check is back and meaningful — it pins the value tables, not Swift's description.
        assert(categoryValueName(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                                 HKCategoryValueSleepAnalysis.asleepREM.rawValue) == "asleepREM")
        assert(HealthNames.workoutActivity[Int(HKWorkoutActivityType.running.rawValue)] == "running")
        assert(HealthNames.stateOfMindLabel[HKStateOfMind.Label.grateful.rawValue] == "grateful")
        assert(HealthNames.biologicalSex[HKBiologicalSex.female.rawValue] == "female")
        // A type with no paired value table still reports 0 rather than dropping the sample.
        assert(categoryValueName(HKObjectType.categoryType(forIdentifier: .mindfulSession)!, 0) == "notApplicable")
    }
    #endif
}
