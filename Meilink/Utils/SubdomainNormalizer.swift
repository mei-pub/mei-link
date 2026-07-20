import Foundation

enum SubdomainNormalizer {
    static func normalize(_ value: String?, baseHost: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        guard let baseHost = baseHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseHost.isEmpty else {
            return value
        }

        let suffix = ".\(baseHost)"
        if value.hasSuffix(suffix) {
            let prefix = String(value.dropLast(suffix.count))
            return prefix.isEmpty ? nil : prefix
        }

        return value
    }
}
