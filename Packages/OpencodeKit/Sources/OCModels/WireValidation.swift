import OCFoundation

/// Only validates fields understood by the selected case. Missing/null fields use defaults.
/// Future keys and union members remain available as raw JSON.
enum WireValidation {
    static func issue(_ raw: JSONValue, strings: [String] = [], numbers: [String] = [],
                      objects: [String] = [], arrays: [String] = [], bools: [String] = []) -> String? {
        for (keys, kind) in [(strings, 0), (numbers, 1), (objects, 2), (arrays, 3), (bools, 4)] {
            for key in keys {
                guard let value = raw[key], !value.isNull else { continue }
                let valid = switch kind {
                case 0: value.stringValue != nil
                case 1: value.wireNumber != nil
                case 2: value.objectValue != nil
                case 3: value.arrayValue != nil
                default: value.boolValue != nil
                }
                if !valid { return "Invalid field: \(key)" }
            }
        }
        return nil
    }
}
