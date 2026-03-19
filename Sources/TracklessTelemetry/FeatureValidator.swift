import Foundation

/// Validates feature names against the Trackless naming rules.
///
/// Rules (from Section 6.2):
/// - Lowercase alphanumeric, underscores, hyphens, and dots: [a-z0-9_.-]
/// - 1-100 characters
/// - Must not start or end with "."
/// - No consecutive dots ("..")
/// - No leading, trailing, or consecutive dots
/// - Must not look like a UUID, hash, or encoded identifier
enum FeatureValidator {

    /// Maximum allowed length for a feature name.
    static let maxLength = 100

    /// Returns `true` if the feature name is valid per Trackless rules.
    static func isValid(_ name: String) -> Bool {
        // Non-empty, within length
        guard !name.isEmpty, name.count <= maxLength else {
            return false
        }

        // Must not start or end with "."
        guard !name.hasPrefix("."), !name.hasSuffix(".") else {
            return false
        }

        // No consecutive dots
        guard !name.contains("..") else {
            return false
        }

        // Only allowed characters: [a-z0-9_.-]
        let allowedCharSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.-")
        guard name.unicodeScalars.allSatisfy({ allowedCharSet.contains($0) }) else {
            return false
        }

        // Reject UUID patterns: 8-4-4-4-12 hex with hyphens or underscores
        if matchesUUIDPattern(name) {
            return false
        }

        // Reject long hex sequences (>24 consecutive hex chars)
        if containsLongHexSequence(name) {
            return false
        }

        // Reject numeric-only strings > 12 characters
        if isLongNumericOnly(name) {
            return false
        }

        // Reject names that are entirely hex chars (no underscores, no [g-z]) and > 16 chars
        if isEntirelyHexAndLong(name) {
            return false
        }

        return true
    }

    // MARK: - PII Stripping

    /// Regex patterns for PII detection.
    private static let emailPattern = try! NSRegularExpression(
        pattern: "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b",
        options: [.caseInsensitive]
    )
    private static let ssnDashedPattern = try! NSRegularExpression(
        pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b",
        options: []
    )
    private static let ssnPlainPattern = try! NSRegularExpression(
        pattern: "\\b\\d{9}\\b",
        options: []
    )
    private static let phonePattern = try! NSRegularExpression(
        pattern: "\\+?\\d[\\d\\s\\-\\.\\(\\)]{8,}\\d",
        options: []
    )

    /// Strip PII patterns (emails, SSNs, phone numbers) from a string,
    /// replacing matches with [REDACTED].
    static func stripPII(_ value: String) -> String {
        var result = value

        // Email addresses
        result = emailPattern.stringByReplacingMatches(
            in: result, options: [], range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED]"
        )
        // SSN patterns (check before phone numbers to avoid false matches)
        result = ssnDashedPattern.stringByReplacingMatches(
            in: result, options: [], range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED]"
        )
        result = ssnPlainPattern.stringByReplacingMatches(
            in: result, options: [], range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED]"
        )
        // Phone numbers
        result = phonePattern.stringByReplacingMatches(
            in: result, options: [], range: NSRange(result.startIndex..., in: result),
            withTemplate: "[REDACTED]"
        )
        return result
    }

    // MARK: - Private Helpers

    /// Matches UUID format: [0-9a-f]{8}[-_][0-9a-f]{4}[-_][0-9a-f]{4}[-_][0-9a-f]{4}[-_][0-9a-f]{12}
    private static func matchesUUIDPattern(_ name: String) -> Bool {
        let pattern = "^[0-9a-f]{8}[-_][0-9a-f]{4}[-_][0-9a-f]{4}[-_][0-9a-f]{4}[-_][0-9a-f]{12}$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// Checks for sequences of hex characters ([0-9a-f]) longer than 24 consecutive characters.
    private static func containsLongHexSequence(_ name: String) -> Bool {
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        var consecutiveCount = 0
        for scalar in name.unicodeScalars {
            if hexChars.contains(scalar) {
                consecutiveCount += 1
                if consecutiveCount > 24 {
                    return true
                }
            } else {
                consecutiveCount = 0
            }
        }
        return false
    }

    /// Checks if the name is numeric-only (all digits) and longer than 12 characters.
    private static func isLongNumericOnly(_ name: String) -> Bool {
        guard name.count > 12 else { return false }
        return name.allSatisfy { $0.isNumber }
    }

    /// Checks if the name is entirely hex characters (no underscores, hyphens, dots,
    /// no letters g-z) and longer than 16 characters.
    private static func isEntirelyHexAndLong(_ name: String) -> Bool {
        guard name.count > 16 else { return false }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        return name.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }
}
