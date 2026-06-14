import Foundation

enum VendorPackage: String, CaseIterable {
    case lodash
    case dateFns = "date-fns"
    case zod
    case cheerio
    case mathjs
    case marked
    case csvParse = "csv-parse"
    case yaml

    var resourceName: String { rawValue }

    // Global variable name injected by the IIFE bundle script
    var globalName: String { "__loom_vendor_\(rawValue.replacingOccurrences(of: "-", with: "_"))__" }

    static func package(for importName: String) -> VendorPackage? {
        allCases.first { $0.rawValue == importName }
    }

    func jsContent() -> String? {
        // Try Vendors subdirectory first, then bundle root.
        let url = Bundle.main.url(forResource: resourceName, withExtension: "js", subdirectory: "Vendors")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "js")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}
