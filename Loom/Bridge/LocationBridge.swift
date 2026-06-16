import Foundation
import JavaScriptCore
import CoreLocation

// Implements Loom.location.current() → Promise<{lat, lng, accuracy}>
final class LocationBridge: NSObject, CLLocationManagerDelegate {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let capturedCtx = ctx
        let currentBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, reject in
                DispatchQueue.main.async {
                    let fetcher = LocationFetcher(resolve: resolve, reject: reject)
                    fetcher.start()
                }
            }
        }

        obj.setObject(currentBlock, forKeyedSubscript: "current" as NSString)
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

// One-shot location fetcher. Retains itself (via selfRef) until settled.
@MainActor
private final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let resolve: (Any?) -> Void
    private let reject: (String) -> Void
    private var settled = false
    private var selfRef: LocationFetcher?   // broken on settle

    init(resolve: @escaping (Any?) -> Void, reject: @escaping (String) -> Void) {
        self.resolve = resolve
        self.reject = reject
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        selfRef = self
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            settle { self.reject("Location permission denied") }
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            settle { self.reject("Location permission denied") }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let result: [String: Any] = [
            "lat":      loc.coordinate.latitude,
            "lng":      loc.coordinate.longitude,
            "accuracy": loc.horizontalAccuracy,
        ]
        settle { self.resolve(result as NSDictionary) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        settle { self.reject(error.localizedDescription) }
    }

    private func settle(_ block: () -> Void) {
        guard !settled else { return }
        settled = true
        block()
        selfRef = nil
    }
}
