import Foundation
import JavaScriptCore
import HealthKit

// Implements Loom.health.read / .stats / .profile / .saveWorkout.
//
// One polymorphic read() covers every HealthKit sample family — quantity, category,
// workout, state of mind, correlation, ECG, scored assessment — because which family a
// type belongs to is HealthKit's business, not a script author's. Type names resolve
// through HealthTypes, which probes HealthKit's own constructors instead of a table.
// See ADR-012.
//
// healthStore is nil on devices that don't support HealthKit (iPads without Health app).
//
// nonisolated throughout: bridges run on the dedicated script thread, never the main actor.
nonisolated final class HealthBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let healthStore: HKHealthStore?
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Whether loom()'s declared health.read types have been folded into an auth request yet.
    // Only ever touched from inside makePromise's executor, which the semaphore serialises.
    private var declaredTypesRequested = false

    nonisolated init(ctx: JSContext, project: LoomProject) {
        self.ctx = ctx
        self.project = project
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        // read(type, {from, to, limit, unit}) -> Promise<Sample[]>
        let readBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] typeVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let name = typeVal.toString() ?? ""
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                guard let store = self.healthStore else { reject("HealthKit not available"); return }
                guard let objType = HealthTypes.resolve(name) else {
                    reject("Unknown health type: \(name)"); return
                }
                if objType is HKClinicalType {
                    reject("Clinical records are not enabled in this build (requires the health-records entitlement)")
                    return
                }
                guard let sampleType = objType as? HKSampleType else {
                    reject("\(name) is not a sample type — read it with Loom.health.profile()")
                    return
                }
                var explicitUnit: HKUnit? = nil
                if let unitName = opts["unit"] as? String {
                    guard let u = HealthTypes.unit(named: unitName) else {
                        reject("Unsupported unit: \(unitName) — omit `unit` to use your Health app's preferred unit")
                        return
                    }
                    explicitUnit = u
                }
                let (from, to) = self.range(opts)
                let limit = (opts["limit"] as? Double).map { Int($0) } ?? HKObjectQueryNoLimit

                Task.detached {
                    do {
                        try await self.authorize([sampleType], store: store)
                        let samples: [HKSample] = try await withCheckedThrowingContinuation { cont in
                            let pred = HKQuery.predicateForSamples(withStart: from, end: to)
                            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
                            let query = HKSampleQuery(sampleType: sampleType, predicate: pred, limit: limit, sortDescriptors: sort) { _, samples, error in
                                if let error { cont.resume(throwing: error); return }
                                cont.resume(returning: samples ?? [])
                            }
                            store.execute(query)
                        }
                        var unit = explicitUnit
                        if unit == nil, let qType = sampleType as? HKQuantityType {
                            unit = await self.preferredUnit(for: qType, store: store)
                        }
                        resolve(samples.map { self.encode($0, unit: unit) } as NSArray)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        // stats(type, {from, to, op, bucket, unit}) -> Promise<Bucket | Bucket[]>
        // Uses HKStatistics rather than summing in JS: HealthKit de-duplicates overlapping
        // samples by source, so an iPhone and a Watch logging the same steps count once.
        let statsBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] typeVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let name = typeVal.toString() ?? ""
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                guard let store = self.healthStore else { reject("HealthKit not available"); return }
                guard let objType = HealthTypes.resolve(name) else {
                    reject("Unknown health type: \(name)"); return
                }
                guard let qType = objType as? HKQuantityType else {
                    reject("Loom.health.stats() needs a quantity type — \(name) is not one. Use Loom.health.read() instead.")
                    return
                }
                var explicitUnit: HKUnit? = nil
                if let unitName = opts["unit"] as? String {
                    guard let u = HealthTypes.unit(named: unitName) else {
                        reject("Unsupported unit: \(unitName)"); return
                    }
                    explicitUnit = u
                }
                // Cumulative types (steps, energy) sum; discrete ones (heart rate, weight) average.
                let opName = (opts["op"] as? String) ?? (qType.aggregationStyle == .cumulative ? "sum" : "average")
                guard let op = Self.statsOp(opName) else {
                    reject("Unknown op: \(opName) — use sum, average, min or max"); return
                }
                var interval: DateComponents? = nil
                if let bucket = opts["bucket"] as? String {
                    guard let i = Self.bucketInterval(bucket) else {
                        reject("Unknown bucket: \(bucket) — use hour, day, week or month"); return
                    }
                    interval = i
                }
                let (from, to) = self.range(opts)

                Task.detached {
                    do {
                        try await self.authorize([qType], store: store)
                        let unit: HKUnit
                        if let explicitUnit { unit = explicitUnit }
                        else { unit = await self.preferredUnit(for: qType, store: store) }
                        let pred = HKQuery.predicateForSamples(withStart: from, end: to)

                        if let interval {
                            let anchor = Calendar.current.startOfDay(for: from)
                            let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
                                let query = HKStatisticsCollectionQuery(quantityType: qType, quantitySamplePredicate: pred,
                                                                        options: op.options, anchorDate: anchor,
                                                                        intervalComponents: interval)
                                query.initialResultsHandler = { _, result, error in
                                    if let error { cont.resume(throwing: error); return }
                                    guard let result else { cont.resume(throwing: HealthError.noResult); return }
                                    cont.resume(returning: result)
                                }
                                store.execute(query)
                            }
                            var out: [[String: Any]] = []
                            collection.enumerateStatistics(from: from, to: to) { stats, _ in
                                out.append(self.encode(stats, op: op, unit: unit))
                            }
                            resolve(out as NSArray)
                        } else {
                            let stats: HKStatistics = try await withCheckedThrowingContinuation { cont in
                                let query = HKStatisticsQuery(quantityType: qType, quantitySamplePredicate: pred, options: op.options) { _, result, error in
                                    if let error { cont.resume(throwing: error); return }
                                    guard let result else { cont.resume(throwing: HealthError.noResult); return }
                                    cont.resume(returning: result)
                                }
                                store.execute(query)
                            }
                            resolve(self.encode(stats, op: op, unit: unit) as NSDictionary)
                        }
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        // profile() -> Promise<{biologicalSex, bloodType, dateOfBirth, ...}>
        // Characteristics aren't samples — they have no date range, so they don't belong in read().
        let profileBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                guard let store = self.healthStore else { reject("HealthKit not available"); return }
                let names = ["biologicalSex", "bloodType", "dateOfBirth", "fitzpatrickSkinType", "wheelchairUse", "activityMoveMode"]
                let types = Set(names.compactMap { HealthTypes.resolve($0) })
                Task.detached {
                    do {
                        try await self.authorize(types, store: store)
                        var out: [String: Any] = [:]
                        // Each getter throws when the user hasn't granted or hasn't set that
                        // value; a missing characteristic is absent from the result, not an error.
                        if let v = try? store.biologicalSex().biologicalSex, v != .notSet { out["biologicalSex"] = HealthNames.biologicalSex[v.rawValue] }
                        if let v = try? store.bloodType().bloodType, v != .notSet { out["bloodType"] = HealthNames.bloodType[v.rawValue] }
                        if let v = try? store.fitzpatrickSkinType().skinType, v != .notSet { out["fitzpatrickSkinType"] = HealthNames.fitzpatrickSkinType[v.rawValue] }
                        if let v = try? store.wheelchairUse().wheelchairUse, v != .notSet { out["wheelchairUse"] = HealthNames.wheelchairUse[v.rawValue] }
                        if let v = try? store.activityMoveMode().activityMoveMode { out["activityMoveMode"] = HealthNames.activityMoveMode[v.rawValue] }
                        if let c = try? store.dateOfBirthComponents(), let d = Calendar.current.date(from: c) {
                            out["dateOfBirth"] = self.iso.string(from: d)
                        }
                        resolve(out as NSDictionary)
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

        obj.setObject(readBlock,        forKeyedSubscript: "read"        as NSString)
        obj.setObject(statsBlock,       forKeyedSubscript: "stats"       as NSString)
        obj.setObject(profileBlock,     forKeyedSubscript: "profile"     as NSString)
        obj.setObject(saveWorkoutBlock, forKeyedSubscript: "saveWorkout" as NSString)
        return obj
    }

    // MARK: - Authorization

    /// Requests read access, folding in everything loom() declared in health.read on the
    /// first call so a script reading ten types gets one prompt rather than ten.
    /// Undeclared types still work — they're simply requested as they're used.
    nonisolated private func authorize(_ types: Set<HKObjectType>, store: HKHealthStore) async throws {
        var all = types
        if !declaredTypesRequested {
            declaredTypesRequested = true
            let declared = ConfigExtractor.extract(for: project).health?.read ?? []
            all.formUnion(declared.compactMap { HealthTypes.resolve($0) })
        }
        try await store.requestAuthorization(toShare: [], read: all)
    }

    // MARK: - Units

    /// The user's own choice in the Health app (kg vs lb, °C vs °F), or the locale default.
    /// Falls back to a dimensional probe for types HealthKit has no preference for.
    nonisolated private func preferredUnit(for type: HKQuantityType, store: HKHealthStore) async -> HKUnit {
        if let preferred = try? await store.preferredUnits(for: [type])[type] { return preferred }
        return HealthTypes.probeUnit(for: type)
    }

    // MARK: - Encoding

    /// Shared envelope plus per-family fields. `family` is the discriminator a caller
    /// switches on when reading a type it doesn't know statically.
    nonisolated private func encode(_ sample: HKSample, unit: HKUnit?) -> [String: Any] {
        var out: [String: Any] = [
            "type":   HealthTypes.shortName(sample.sampleType),
            "start":  iso.string(from: sample.startDate),
            "end":    iso.string(from: sample.endDate),
            "source": sample.sourceRevision.source.name,
        ]
        switch sample {
        case let s as HKQuantitySample:
            let u = unit ?? HealthTypes.probeUnit(for: s.quantityType)
            out["family"] = "quantity"
            out["value"]  = s.quantity.doubleValue(for: u)
            out["unit"]   = u.unitString

        case let s as HKCategorySample:
            out["family"] = "category"
            out["value"]  = s.value
            if let name = HealthTypes.categoryValueName(s.categoryType, s.value) { out["valueName"] = name }

        case let s as HKWorkout:
            out["family"]   = "workout"
            out["activity"] = HealthNames.workoutActivity[Int(s.workoutActivityType.rawValue)] ?? "other"
            out["duration"] = s.duration
            if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
               let q = s.statistics(for: t)?.sumQuantity() {
                out["distance"] = q.doubleValue(for: .meter())
            }
            if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
               let q = s.statistics(for: t)?.sumQuantity() {
                out["energy"] = q.doubleValue(for: .kilocalorie())
            }

        case let s as HKStateOfMind:
            out["family"]                = "stateOfMind"
            out["kind"]                  = HealthNames.stateOfMindKind[s.kind.rawValue] ?? s.kind.rawValue
            out["valence"]               = s.valence
            out["valenceClassification"] = HealthNames.valenceClassification[s.valenceClassification.rawValue] ?? "unknown"
            out["labels"]                = s.labels.compactMap { HealthNames.stateOfMindLabel[$0.rawValue] }
            out["associations"]          = s.associations.compactMap { HealthNames.stateOfMindAssociation[$0.rawValue] }

        case let s as HKCorrelation:
            out["family"]  = "correlation"
            out["objects"] = s.objects.map { self.encode($0, unit: nil) }

        case let s as HKElectrocardiogram:
            out["family"]         = "electrocardiogram"
            out["classification"] = HealthNames.ecgClassification[s.classification.rawValue] ?? "unknown"
            out["symptomsStatus"] = HealthNames.ecgSymptomsStatus[s.symptomsStatus.rawValue] ?? "unknown"
            out["voltageMeasurements"] = s.numberOfVoltageMeasurements
            if let hr = s.averageHeartRate {
                out["averageHeartRate"] = hr.doubleValue(for: .count().unitDivided(by: .minute()))
            }

        case let s as HKScoredAssessment:
            out["family"] = "scoredAssessment"
            out["score"]  = s.score
            if let a = s as? HKGAD7Assessment { out["risk"] = HealthNames.gad7Risk[a.risk.rawValue] }
            if let a = s as? HKPHQ9Assessment { out["risk"] = HealthNames.phq9Risk[a.risk.rawValue] }

        default:
            // Audiogram, vision prescription, medication dose events and anything a future
            // OS adds still return the shared envelope rather than failing.
            out["family"] = "sample"
        }
        return out
    }

    nonisolated private func encode(_ stats: HKStatistics, op: StatsOp, unit: HKUnit) -> [String: Any] {
        var out: [String: Any] = [
            "start": iso.string(from: stats.startDate),
            "end":   iso.string(from: stats.endDate),
            "unit":  unit.unitString,
        ]
        // nil when a bucket has no samples in it — reported as null, not dropped, so a
        // bucketed series stays aligned to its date range.
        out["value"] = op.quantity(stats).map { $0.doubleValue(for: unit) } ?? NSNull()
        return out
    }

    // MARK: - Options

    struct StatsOp {
        let options: HKStatisticsOptions
        let quantity: (HKStatistics) -> HKQuantity?
    }

    nonisolated private static func statsOp(_ name: String) -> StatsOp? {
        switch name {
        case "sum":     return StatsOp(options: .cumulativeSum,   quantity: { $0.sumQuantity() })
        case "average": return StatsOp(options: .discreteAverage, quantity: { $0.averageQuantity() })
        case "min":     return StatsOp(options: .discreteMin,     quantity: { $0.minimumQuantity() })
        case "max":     return StatsOp(options: .discreteMax,     quantity: { $0.maximumQuantity() })
        default:        return nil
        }
    }

    nonisolated private static func bucketInterval(_ name: String) -> DateComponents? {
        switch name {
        case "hour":  return DateComponents(hour: 1)
        case "day":   return DateComponents(day: 1)
        case "week":  return DateComponents(day: 7)
        case "month": return DateComponents(month: 1)
        default:      return nil
        }
    }

    /// Defaults to the last 24 hours, matching the previous getQuantity() behaviour.
    nonisolated private func range(_ opts: [String: Any]) -> (Date, Date) {
        let from = (opts["from"] as? String).flatMap { iso.date(from: $0) } ?? Date().addingTimeInterval(-86400)
        let to   = (opts["to"]   as? String).flatMap { iso.date(from: $0) } ?? Date()
        return (from, to)
    }

    enum HealthError: LocalizedError {
        case noResult
        var errorDescription: String? { "HealthKit returned no result" }
    }

    // MARK: - Promise

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

private nonisolated func workoutActivity(for name: String) -> HKWorkoutActivityType? {
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
