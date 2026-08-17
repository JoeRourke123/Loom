import Foundation
import CryptoKit

// Makes `w.image` work in a widget at all.
//
// WidgetKit renders a timeline entry to a static snapshot. `AsyncImage` starts a network load and
// returns its placeholder immediately, and the snapshot is taken long before that load finishes —
// so a remote image in a widget is permanently the placeholder, which in WidgetView's case is a
// flat `Color(.secondarySystemBackground)`. A grey box, every time, on every device.
//
// The bytes therefore have to be resident before the extension ever runs. The main app downloads
// them at the end of a run, writes them into the shared App Group container, and rewrites the
// payload's image URLs to local file paths; the extension then loads them synchronously off disk.
//
// ponytail: no downscaling, no format conversion, no expiry beyond "not referenced by the current
// payload". A poem article references ~7 images a day at a few hundred KB each. Add a size budget
// if a project ever points this at something bigger.
enum WidgetImageCache {
    private static let appGroupID = "group.uk.co.joerourke.loom"
    private static let folderName = "WidgetImages"

    // Bounded so a slow host cannot stall the end of a run — and the end of a *background* run is
    // inside a ~30s window shared with every other project. Anything that misses the deadline is
    // simply left remote and picked up on the next run, since by then it is already cached.
    private static let deadline: TimeInterval = 8
    private static let maxConcurrent = 4

    // One directory PER PROJECT. This is not tidiness — prune() deletes everything the current
    // payload does not reference, so a single shared folder means every run wipes every other
    // project's images. With two Loom widgets in a home screen stack that shows up as "only one of
    // them can display a picture at a time": running either script blanks the other.
    static func directory(for projectName: String) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        // Project names are iCloud folder names, so already filesystem-safe — but a stray "/" or a
        // leading dot would silently write outside the intended directory.
        var safe = projectName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if safe.hasPrefix(".") || safe.isEmpty { safe = "_" + safe }

        let dir = container
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func filename(for url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads every remote image the payload references and returns the payload with those URLs
    /// rewritten to local file paths. Returns the input unchanged if anything about it is
    /// unparseable — a widget that renders remote-and-grey beats one that renders nothing.
    static func materialise(json: String, projectName: String) -> String {
        guard let dir = directory(for: projectName),
              let data = json.data(using: .utf8),
              var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        sweepLegacyFlatFiles(besides: dir)

        var remote: Set<String> = []
        for (_, value) in payload {
            collectImageURLs(value, into: &remote)
        }
        guard !remote.isEmpty else { return json }

        var localPath: [String: String] = [:]
        var missing: [String] = []
        for url in remote {
            let file = dir.appendingPathComponent(filename(for: url))
            if FileManager.default.fileExists(atPath: file.path) {
                localPath[url] = file.path
            } else {
                missing.append(url)
            }
        }

        if !missing.isEmpty {
            for (url, path) in download(missing, into: dir) { localPath[url] = path }
        }

        for (key, value) in payload {
            payload[key] = rewrite(value, using: localPath)
        }
        prune(dir, keeping: Set(localPath.values.map { ($0 as NSString).lastPathComponent }))

        guard let out = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: out, encoding: .utf8)
        else { return json }
        return string
    }

    // MARK: - Tree walking

    private static func collectImageURLs(_ value: Any, into set: inout Set<String>) {
        if let node = value as? [String: Any] {
            if node["type"] as? String == "image",
               let props = node["props"] as? [String: Any],
               let url = props["url"] as? String,
               url.hasPrefix("http") {
                set.insert(url)
            }
            for (_, child) in node { collectImageURLs(child, into: &set) }
        } else if let array = value as? [Any] {
            for element in array { collectImageURLs(element, into: &set) }
        }
    }

    private static func rewrite(_ value: Any, using map: [String: String]) -> Any {
        if var node = value as? [String: Any] {
            if node["type"] as? String == "image",
               var props = node["props"] as? [String: Any],
               let url = props["url"] as? String,
               let path = map[url] {
                props["url"] = path
                node["props"] = props
            }
            for (key, child) in node where key != "props" {
                node[key] = rewrite(child, using: map)
            }
            return node
        }
        if let array = value as? [Any] {
            return array.map { rewrite($0, using: map) }
        }
        return value
    }

    // MARK: - Fetching

    private static func download(_ urls: [String], into dir: URL) -> [String: String] {
        var result: [String: String] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: maxConcurrent)

        for _ in urls { group.enter() }
        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                gate.wait()
                guard let parsed = URL(string: url) else {
                    gate.signal(); group.leave(); continue
                }
                var request = URLRequest(url: parsed)
                // Wikimedia 403s a default user agent, and an image that 403s is indistinguishable
                // from one that simply never arrives.
                request.setValue(
                    "Loom/1.0 (widget image cache; +https://github.com/joerourke/loom)",
                    forHTTPHeaderField: "User-Agent"
                )
                URLSession.shared.dataTask(with: request) { data, response, _ in
                    defer { gate.signal(); group.leave() }
                    guard let data, !data.isEmpty,
                          let http = response as? HTTPURLResponse, http.statusCode == 200
                    else { return }
                    let file = dir.appendingPathComponent(filename(for: url))
                    guard (try? data.write(to: file, options: .atomic)) != nil else { return }
                    lock.lock(); result[url] = file.path; lock.unlock()
                }.resume()
            }
        }

        _ = group.wait(timeout: .now() + deadline)
        lock.lock(); defer { lock.unlock() }
        return result
    }

    // Only files the current payload points at survive — scoped to THIS project's directory, which
    // is the whole reason directory(for:) takes a name. A daily article rotates its whole image set,
    // so without this the container grows forever.
    private static func prune(_ dir: URL, keeping: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files where !keeping.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    // Images cached before the per-project split lived loose in WidgetImages/. Nothing points at
    // them any more and prune() no longer looks there, so they would leak forever. Directories are
    // left alone — those are the per-project folders.
    private static func sweepLegacyFlatFiles(besides projectDir: URL) {
        let root = projectDir.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { try? FileManager.default.removeItem(at: entry) }
        }
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        // Tree walking is the part that silently does nothing when it is wrong: a missed node
        // means the image stays remote and the widget stays grey, with no error anywhere.
        let payload = """
        {"large":{"type":"vstack","props":{},"children":[
          {"type":"image","props":{"url":"https://example.com/a.jpg"}},
          {"type":"hstack","props":{},"children":[
            {"type":"image","props":{"url":"https://example.com/b.jpg"}},
            {"type":"text","props":{"content":"not an image"}}]}]},
         "small":{"type":"image","props":{"url":"https://example.com/a.jpg"}}}
        """
        let value = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        var found: Set<String> = []
        for (_, v) in value ?? [:] { collectImageURLs(v, into: &found) }
        check("collect.findsNested", found.contains("https://example.com/b.jpg"))
        check("collect.dedupesAcrossSizes", found.count == 2)

        let rewritten = rewrite(value as Any, using: ["https://example.com/a.jpg": "/tmp/a.img"])
        var afterURLs: Set<String> = []
        collectImageURLs(rewritten, into: &afterURLs)
        check("rewrite.replacesMapped", !afterURLs.contains("https://example.com/a.jpg"))
        check("rewrite.leavesUnmapped", afterURLs.contains("https://example.com/b.jpg"))

        // A local path must survive a second pass untouched — materialise runs on every write.
        var stable: Set<String> = []
        collectImageURLs(rewrite(rewritten, using: [:]), into: &stable)
        check("rewrite.idempotent", stable == afterURLs)

        check("filename.stable", filename(for: "https://x/y") == filename(for: "https://x/y"))
        check("filename.distinct", filename(for: "https://x/y") != filename(for: "https://x/z"))

        // The bug this split exists to prevent: two projects with widgets in the same home screen
        // stack. A shared directory meant whichever ran last pruned the other's images away, so
        // only one widget could ever show a picture. Reproduced here against the real filesystem.
        if let a = directory(for: "Daily Poem"), let b = directory(for: "Daily Artwork") {
            check("dir.perProjectIsolation", a.path != b.path)
            let fileA = a.appendingPathComponent(filename(for: "https://example.com/poem.jpg"))
            let fileB = b.appendingPathComponent(filename(for: "https://example.com/art.jpg"))
            try? Data("a".utf8).write(to: fileA)
            try? Data("b".utf8).write(to: fileB)
            // Daily Artwork writes a payload referencing only its own image, exactly as a run does.
            prune(b, keeping: [fileB.lastPathComponent])
            check("prune.keepsOwn", FileManager.default.fileExists(atPath: fileB.path))
            check("prune.doesNotTouchOtherProject", FileManager.default.fileExists(atPath: fileA.path))
            try? FileManager.default.removeItem(at: fileA)
            try? FileManager.default.removeItem(at: fileB)
        }

        if failures.isEmpty {
            print("[WidgetImageCache] self-check passed")
        } else {
            print("[WidgetImageCache] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
