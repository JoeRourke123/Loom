import Foundation
import JavaScriptCore
import HealthKit

// Implements Loom.health.getQuantity(type, {from, to}) and .saveWorkout({...})
// healthStore is nil on devices that don't support HealthKit (iPads without Health app).
final class HealthBridge {
    private let ctx: JSContext
    private let healthStore: HKHealthStore?
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let getQuantityBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] typeVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let typeStr = typeVal.toString() ?? ""
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                guard let store = self.healthStore else { reject("HealthKit not available"); return }
                guard let qType = quantityType(for: typeStr) else {
                    reject("Unknown quantity type: \(typeStr)"); return
                }
                let from = (opts["from"] as? String).flatMap { self.iso.date(from: $0) } ?? Date().addingTimeInterval(-86400)
                let to   = (opts["to"]   as? String).flatMap { self.iso.date(from: $0) } ?? Date()
                Task.detached {
                    do {
                        try await store.requestAuthorization(toShare: [], read: [qType])
                        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
                            let pred = HKQuery.predicateForSamples(withStart: from, end: to)
                            let query = HKSampleQuery(sampleType: qType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                                if let error { cont.resume(throwing: error); return }
                                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                            }
                            store.execute(query)
                        }
                        let unit = preferredUnit(for: qType)
                        let results: [[String: Any]] = samples.map { s in
                            ["value": s.quantity.doubleValue(for: unit), "unit": unit.unitString, "date": self.iso.string(from: s.startDate)]
                        }
                        resolve(results as NSArray)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        let saveWorkoutBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                guard let store = self.healthStore else { reject("HealthKit not available"); return }
                guard let activityStr = opts["type"] as? String,
                      let activity = workoutActivity(for: activityStr) else {
                    reject("Unknown workout type"); return
                }
                let duration = (opts["duration"] as? Double) ?? 0
                let start = (opts["start"] as? String).flatMap { self.iso.date(from: $0) } ?? Date().addingTimeInterval(-duration)
                let end   = (opts["end"]   as? String).flatMap { self.iso.date(from: $0) } ?? start.addingTimeInterval(duration)
                Task.detached {
                    do {
                        let workoutType = HKObjectType.workoutType()
                        try await store.requestAuthorization(toShare: [workoutType], read: [])
                        let workout: HKWorkout
                        if let dist = opts["distance"] as? Double {
                            workout = HKWorkout(activityType: activity, start: start, end: end,
                                               duration: end.timeIntervalSince(start),
                                               totalEnergyBurned: nil,
                                               totalDistance: HKQuantity(unit: .meter(), doubleValue: dist),
                                               metadata: nil)
                        } else {
                            workout = HKWorkout(activityType: activity, start: start, end: end)
                        }
                        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                            store.save(workout) { _, error in
                                if let error { cont.resume(throwing: error) } else { cont.resume() }
                            }
                        }
                        resolve(nil)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        obj.setObject(getQuantityBlock, forKeyedSubscript: "getQuantity"  as NSString)
        obj.setObject(saveWorkoutBlock, forKeyedSubscript: "saveWorkout"  as NSString)
        return obj
    }

    nonisolated private func makePromise(
        _ executor: (_ resolve: @escaping (Any?) -> Void, _ reject: @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolvedVal: Any? = nil
        var rejectMsg: String? = nil
        let sema = DispatchSemaphore(value: 0)
        executor(
            { val in resolvedVal = val; sema.signal() },
            { msg in rejectMsg = msg; sema.signal() }
        )
        sema.wait()
        if let msg = rejectMsg {
            return ctx.objectForKeyedSubscript("__loomReject")?
                .call(withArguments: [msg]) ?? JSValue(undefinedIn: ctx)
        } else if let v = resolvedVal {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: [v]) ?? JSValue(undefinedIn: ctx)
        } else {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: []) ?? JSValue(undefinedIn: ctx)
        }
    }
}

// Maps JS type strings to HKQuantityType identifiers.
private func quantityType(for name: String) -> HKQuantityType? {
    let map: [String: HKQuantityTypeIdentifier] = [
        "stepCount":            .stepCount,
        "heartRate":            .heartRate,
        "activeEnergyBurned":   .activeEnergyBurned,
        "distanceWalkingRunning": .distanceWalkingRunning,
        "bodyMass":             .bodyMass,
        "height":               .height,
        "bloodGlucose":         .bloodGlucose,
        "oxygenSaturation":     .oxygenSaturation,
        "respiratoryRate":      .respiratoryRate,
        "bodyTemperature":      .bodyTemperature,
        "sleepAnalysis":        .stepCount, // fallback — sleep is a category type, excluded
    ]
    guard let id = map[name] else { return nil }
    return HKObjectType.quantityType(forIdentifier: id)
}

// Returns the most natural unit for each quantity type.
private func preferredUnit(for type: HKQuantityType) -> HKUnit {
    switch type.identifier {
    case HKQuantityTypeIdentifier.heartRate.rawValue:            return .count().unitDivided(by: .minute())
    case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:  return .kilocalorie()
    case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue: return .meter()
    case HKQuantityTypeIdentifier.bodyMass.rawValue:            return .gramUnit(with: .kilo)
    case HKQuantityTypeIdentifier.height.rawValue:              return .meter()
    case HKQuantityTypeIdentifier.bloodGlucose.rawValue:        return HKUnit(from: "mg/dL")
    case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:    return .percent()
    case HKQuantityTypeIdentifier.respiratoryRate.rawValue:     return .count().unitDivided(by: .minute())
    case HKQuantityTypeIdentifier.bodyTemperature.rawValue:     return .degreeCelsius()
    default:                                                    return .count()
    }
}

private func workoutActivity(for name: String) -> HKWorkoutActivityType? {
    let map: [String: HKWorkoutActivityType] = [
        "running":   .running,
        "walking":   .walking,
        "cycling":   .cycling,
        "swimming":  .swimming,
        "yoga":      .yoga,
        "hiit":      .highIntensityIntervalTraining,
        "strength":  .traditionalStrengthTraining,
        "other":     .other,
    ]
    return map[name.lowercased()]
}
