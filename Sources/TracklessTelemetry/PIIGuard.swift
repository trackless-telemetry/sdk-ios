import Foundation

/// PII guard for generic event properties.
///
/// Key blocklist + value regex detection.
/// Strips properties that might contain personally identifiable information.
enum PIIGuard {

    private static let blockedKeys: Set<String> = [
        "email", "phone", "name", "address", "ssn", "password", "token", "secret",
        "credit_card", "creditcard", "card_number", "cardnumber",
        "first_name", "firstname", "last_name", "lastname", "full_name", "fullname",
        "username", "user_name", "user_id", "userid",
        "ip", "ip_address", "ipaddress", "device_id", "deviceid",
    ]

    private static let piiValuePatterns: [NSRegularExpression] = {
        let patterns = [
            "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",   // email
            "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b",               // phone
            "\\b\\d{3}-\\d{2}-\\d{4}\\b",                       // SSN
            "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b", // credit card
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    static let maxProperties = 10
    static let maxKeyLength = 50
    static let maxValueLength = 200

    /// Sanitize event properties by removing PII.
    ///
    /// - Returns: sanitized properties, or nil if all were stripped.
    static func sanitize(_ properties: [String: String]?) -> [String: String]? {
        guard let properties else { return nil }

        var result: [String: String] = [:]
        var count = 0

        for (key, value) in properties {
            if count >= maxProperties { break }

            let normalizedKey = key.lowercased()

            // Skip blocked keys
            if blockedKeys.contains(normalizedKey) { continue }

            // Skip if value matches PII patterns
            let range = NSRange(value.startIndex..., in: value)
            let matchesPII = piiValuePatterns.contains { regex in
                regex.firstMatch(in: value, range: range) != nil
            }
            if matchesPII { continue }

            // Truncate key and value
            let safeKey = String(normalizedKey.prefix(maxKeyLength))
            let safeValue = String(value.prefix(maxValueLength))

            result[safeKey] = safeValue
            count += 1
        }

        return result.isEmpty ? nil : result
    }
}
