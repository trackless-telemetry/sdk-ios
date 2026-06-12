import Foundation
import Testing
@testable import TracklessTelemetry

@Suite("Warning Behavior Tests")
struct WarningBehaviorTests {

    /// Config pointing at an unreachable endpoint with a flush interval long
    /// enough that no network activity happens during a test.
    private func testConfig(suppressWarnings: Bool = false) -> TracklessConfig {
        TracklessConfig(
            apiKey: "tl_0123456789abcdef0123456789abcdef",
            endpoint: "http://127.0.0.1:9",
            environment: .production,
            enabled: true,
            onError: nil,
            flushIntervalSeconds: 3600,
            debugLogging: false,
            suppressWarnings: suppressWarnings
        )
    }

    // MARK: - Pre-Configure Drops

    @Test("Events recorded before configure() warn once")
    func preConfigureWarnsOnce() async {
        let state = TracklessState()
        let recorder = WarningRecorder()
        await state.setOnWarningForTesting { recorder.record($0) }

        await state.recordEvent(type: .feature, name: "early_feature")
        await state.recordEvent(type: .view, name: "early_view")
        await state.recordFunnel(funnelName: "checkout", stepIndex: 0, stepName: "cart")
        await state.recordPerformance(name: "load", durationSeconds: 1.0)
        await state.recordError(name: "boom", severity: .error, code: nil)

        #expect(recorder.messages.count == 1)
        #expect(recorder.messages.first?.contains("configure") == true)
    }

    @Test("Recording works after configure() with no further pre-configure warnings")
    func configureEnablesRecording() async {
        let state = TracklessState()
        let recorder = WarningRecorder()
        await state.setOnWarningForTesting { recorder.record($0) }

        await state.recordEvent(type: .feature, name: "early_feature")
        #expect(recorder.messages.count == 1)

        await state.configure(testConfig())
        await state.recordEvent(type: .feature, name: "later_feature")

        // Session start + the recorded feature
        let size = await state.bufferSizeForTesting()
        #expect(size == 2)
        #expect(recorder.messages.count == 1)
    }

    // MARK: - Buffer-Full Drops

    @Test("Buffer-full drops warn once per session")
    func bufferFullWarnsOnce() async {
        let state = TracklessState()
        let recorder = WarningRecorder()
        await state.setOnWarningForTesting { recorder.record($0) }
        await state.configure(testConfig())
        await state.replaceBufferForTesting(maxItems: 2)

        await state.recordEvent(type: .feature, name: "one")
        await state.recordEvent(type: .feature, name: "two")
        await state.recordEvent(type: .feature, name: "three")
        await state.recordEvent(type: .feature, name: "four")

        let size = await state.bufferSizeForTesting()
        #expect(size == 2)
        let bufferWarnings = recorder.messages.filter { $0.contains("buffer full") }
        #expect(bufferWarnings.count == 1)
    }

    @Test("Buffer-full warning respects suppressWarnings")
    func bufferFullWarningSuppressed() async {
        let state = TracklessState()
        let recorder = WarningRecorder()
        await state.setOnWarningForTesting { recorder.record($0) }
        await state.configure(testConfig(suppressWarnings: true))
        await state.replaceBufferForTesting(maxItems: 1)

        await state.recordEvent(type: .feature, name: "one")
        await state.recordEvent(type: .feature, name: "two")

        let size = await state.bufferSizeForTesting()
        #expect(size == 1)
        #expect(recorder.messages.isEmpty)
    }

    @Test("Buffer-full warning is re-armed when a new session starts")
    func bufferFullWarningResetsOnNewSession() async {
        let state = TracklessState()
        let recorder = WarningRecorder()
        await state.setOnWarningForTesting { recorder.record($0) }

        await state.configure(testConfig())
        await state.replaceBufferForTesting(maxItems: 1)
        await state.recordEvent(type: .feature, name: "one")
        await state.recordEvent(type: .feature, name: "two")

        // Reconfiguring starts a new session, which re-arms the warning.
        await state.configure(testConfig())
        await state.replaceBufferForTesting(maxItems: 1)
        await state.recordEvent(type: .feature, name: "three")
        await state.recordEvent(type: .feature, name: "four")

        let bufferWarnings = recorder.messages.filter { $0.contains("buffer full") }
        #expect(bufferWarnings.count == 2)
    }
}

// MARK: - Test Helpers

/// Thread-safe warning collector for async tests.
final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _messages
    }

    func record(_ message: String) {
        lock.lock()
        _messages.append(message)
        lock.unlock()
    }
}
