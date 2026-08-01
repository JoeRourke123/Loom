import Foundation

// Statically-extracted shape of the config object passed as loom()'s 2nd argument.
// See ConfigExtractor for how this is derived from main.ts source without running the script.
struct LoomConfig: Codable, Equatable {
    var name: String
    var description: String
    var permissions: [String] = []
    var returnsResult: Bool = false
    var triggers = Triggers()
    var intent: IntentConfig? = nil
    var entities: [String: EntityType]? = nil
    var health: HealthConfig? = nil
    var widget: WidgetConfig? = nil
    var ai: AIConfig? = nil

    struct Triggers: Codable, Equatable {
        var backgroundRefresh = false
        var backgroundProcessing = false
    }

    struct IntentConfig: Codable, Equatable {
        var inputs: [IntentParam] = []
    }

    struct IntentParam: Codable, Equatable {
        var name: String
        var type: ParamType
        var description: String?
        var optional: Bool = false

        enum ParamType: String, Codable {
            case string, number, boolean, date
        }
    }

    struct EntityType: Codable, Equatable {
        var displayName: String
        var fields: [String: FieldSpec] = [:]
        var provider: String   // named export identifier in the same main.ts

        struct FieldSpec: Codable, Equatable {
            var type: String
            var optional: Bool = false
        }
    }

    struct HealthConfig: Codable, Equatable {
        var read: [String] = []
        var write: [String] = []
    }

    struct WidgetConfig: Codable, Equatable {
        var refreshAfter: Double? = nil
    }

    struct AIConfig: Codable, Equatable {
        var provider: String = "auto"
    }
}
