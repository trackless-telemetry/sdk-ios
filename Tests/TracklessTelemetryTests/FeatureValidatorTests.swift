import Testing
@testable import TracklessTelemetry

@Suite("FeatureValidator Tests")
struct FeatureValidatorTests {

    // MARK: - Test 12: Feature name validation (valid names)

    @Test("Valid feature names pass validation")
    func validNames() {
        #expect(FeatureValidator.isValid("export_clicked") == true)
        #expect(FeatureValidator.isValid("settings-opened") == true)
        #expect(FeatureValidator.isValid("theme.dark") == true)
        #expect(FeatureValidator.isValid("distance_preset.1_mile") == true)
        #expect(FeatureValidator.isValid("a") == true)
        #expect(FeatureValidator.isValid("feature123") == true)
        #expect(FeatureValidator.isValid("page_view_home") == true)
        #expect(FeatureValidator.isValid("cafe_fade_added") == true)
        #expect(FeatureValidator.isValid("event_20260301") == true)
    }

    // MARK: - Test 13: Invalid feature name silently ignored

    @Test("Empty string is invalid")
    func emptyString() {
        #expect(FeatureValidator.isValid("") == false)
    }

    @Test("Name exceeding 100 characters is invalid")
    func tooLong() {
        let longName = String(repeating: "a", count: 101)
        #expect(FeatureValidator.isValid(longName) == false)
    }

    @Test("Name at exactly 100 characters is valid")
    func exactlyMaxLength() {
        // Use 'x' (not a hex char) to avoid triggering isEntirelyHexAndLong
        let name = String(repeating: "x", count: 100)
        #expect(FeatureValidator.isValid(name) == true)
    }

    @Test("Uppercase characters are invalid (validator only — client normalizes before calling)")
    func uppercaseInvalid() {
        // The validator itself still rejects uppercase — the client normalizes before calling
        #expect(FeatureValidator.isValid("Export_Clicked") == false)
        #expect(FeatureValidator.isValid("SETTINGS") == false)
    }

    @Test("Spaces are invalid")
    func spacesInvalid() {
        #expect(FeatureValidator.isValid("export clicked") == false)
    }

    @Test("Name starting with dot is invalid")
    func startsWithDot() {
        #expect(FeatureValidator.isValid(".settings") == false)
    }

    @Test("Name ending with dot is invalid")
    func endsWithDot() {
        #expect(FeatureValidator.isValid("settings.") == false)
    }

    @Test("Consecutive dots are invalid")
    func consecutiveDots() {
        #expect(FeatureValidator.isValid("settings..opened") == false)
    }

    @Test("Multiple dots for hierarchical grouping are valid")
    func multipleDots() {
        #expect(FeatureValidator.isValid("a.b.c") == true)
        #expect(FeatureValidator.isValid("settings.theme.dark") == true)
        #expect(FeatureValidator.isValid("nav.settings.display") == true)
    }

    @Test("Special characters are invalid")
    func specialChars() {
        #expect(FeatureValidator.isValid("export@clicked") == false)
        #expect(FeatureValidator.isValid("export#clicked") == false)
        #expect(FeatureValidator.isValid("export/clicked") == false)
    }

    // MARK: - Anti-identifier patterns

    @Test("UUID pattern is rejected")
    func uuidRejected() {
        #expect(FeatureValidator.isValid("550e8400-e29b-41d4-a716-446655440000") == false)
        // With underscores
        #expect(FeatureValidator.isValid("550e8400_e29b_41d4_a716_446655440000") == false)
    }

    @Test("Long hex sequence (>24 chars) is rejected")
    func longHexRejected() {
        let hex = String(repeating: "abcdef0123456789", count: 2).prefix(25)
        #expect(FeatureValidator.isValid(String(hex)) == false)
    }

    @Test("Short hex sequences are allowed")
    func shortHexAllowed() {
        // 16 chars, all hex but not > 16 for the entirely-hex check
        #expect(FeatureValidator.isValid("abcdef0123456789") == true)
    }

    @Test("Entirely hex and > 16 chars is rejected")
    func entirelyHexLongRejected() {
        // 17 hex-only characters
        #expect(FeatureValidator.isValid("abcdef01234567890") == false)
    }

    @Test("Long numeric-only string (>12) is rejected")
    func longNumericRejected() {
        #expect(FeatureValidator.isValid("1234567890123") == false)
    }

    @Test("Short numeric-only string (<=12) is allowed")
    func shortNumericAllowed() {
        #expect(FeatureValidator.isValid("123456789012") == true)
    }

    @Test("Hex chars mixed with non-hex letters are allowed")
    func hexWithNonHexAllowed() {
        // Contains 'g' which is not hex, so not entirely-hex
        #expect(FeatureValidator.isValid("abcdefg0123456789") == true)
    }

    // MARK: - PII Stripping

    @Test("stripPII replaces email addresses with [REDACTED]")
    func stripEmail() {
        #expect(FeatureValidator.stripPII("contact user@example.com now") == "contact [REDACTED] now")
    }

    @Test("stripPII replaces dashed SSN patterns with [REDACTED]")
    func stripSSNDashed() {
        #expect(FeatureValidator.stripPII("ssn 123-45-6789 here") == "ssn [REDACTED] here")
    }

    @Test("stripPII replaces 9-digit SSN patterns with [REDACTED]")
    func stripSSNPlain() {
        #expect(FeatureValidator.stripPII("id 123456789 entered") == "id [REDACTED] entered")
    }

    @Test("stripPII replaces phone numbers with [REDACTED]")
    func stripPhone() {
        #expect(FeatureValidator.stripPII("called +1 (555) 123-4567") == "called [REDACTED]")
    }

    @Test("stripPII replaces unformatted phone numbers with [REDACTED]")
    func stripPhoneUnformatted() {
        #expect(FeatureValidator.stripPII("number 5551234567") == "number [REDACTED]")
    }

    @Test("stripPII handles multiple PII patterns in one string")
    func stripMultiplePII() {
        let result = FeatureValidator.stripPII("email: a@b.com phone: 555-123-4567")
        #expect(!result.contains("a@b.com"))
        #expect(!result.contains("555-123-4567"))
    }

    @Test("stripPII leaves non-PII strings unchanged")
    func stripPIINoChange() {
        #expect(FeatureValidator.stripPII("dark_mode") == "dark_mode")
        #expect(FeatureValidator.stripPII("export_clicked") == "export_clicked")
    }
}
