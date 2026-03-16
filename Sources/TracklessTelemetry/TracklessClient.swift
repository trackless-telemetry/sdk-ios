import Foundation
import os
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Configuration for the Trackless SDK.
public struct TracklessConfig: Sendable {
    /// Default production ingest endpoint.
    public static let defaultEndpoint = "https://api.tracklesstelemetry.com"

    public let apiKey: String
    public let endpoint: String
    public let environment: Environment?
    public let enabled: Bool
    public let onError: (@Sendable (Error) -> Void)?
    public let flushIntervalSeconds: TimeInterval
    public let debugLogging: Bool

    public init(
        apiKey: String,
        endpoint: String = TracklessConfig.defaultEndpoint,
        environment: Environment? = nil,
        enabled: Bool = true,
        onError: (@Sendable (Error) -> Void)? = nil,
        flushIntervalSeconds: TimeInterval = 60,
        debugLogging: Bool = false
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.environment = environment
        self.enabled = enabled
        self.onError = onError
        self.flushIntervalSeconds = flushIntervalSeconds
        self.debugLogging = debugLogging
    }
}

/// Trackless — privacy-first analytics SDK for iOS.
///
/// Static singleton API. Zero dependencies (Foundation only). In-memory only
/// (no UserDefaults, no Keychain, no file system writes). No IDFA, no IDFV,
/// no device identifiers.
///
/// Usage:
/// ```swift
/// Trackless.configure(TracklessConfig(
///     apiKey: "tl_xxxxxxxxxxxxxxxx",
///     endpoint: "https://api.tracklesstelemetry.com"
/// ))
///
/// Trackless.screen("Home")
/// Trackless.feature("export_clicked")
/// ```
public final class Trackless: Sendable {

    // MARK: - Singleton State

    private static let state = TracklessState()

    // MARK: - Configure

    /// Configure the SDK and start a new session.
    public static func configure(_ config: TracklessConfig) {
        Task {
            await state.configure(config)
        }
    }

    // MARK: - Event Recording

    /// Record a screen view.
    public static func screen(_ name: String) {
        Task {
            await state.recordEvent(type: .screen, name: name)
        }
    }

    /// Record a feature usage event.
    public static func feature(_ name: String) {
        Task {
            await state.recordEvent(type: .feature, name: name)
        }
    }

    /// Record a funnel step.
    public static func funnel(_ funnelName: String, step stepName: String) {
        Task {
            await state.recordFunnel(funnelName: funnelName, stepName: stepName)
        }
    }

    /// Record a selection event (e.g., theme preference, language choice).
    public static func selection(_ name: String, option: String) {
        Task {
            await state.recordSelection(name: name, option: option)
        }
    }

    /// Record a performance measurement.
    public static func performance(_ name: String, duration: Double) {
        Task {
            await state.recordPerformance(name: name, duration: duration)
        }
    }

    /// Record an error event.
    public static func error(_ name: String, severity: ErrorSeverity = .error, code: String? = nil) {
        Task {
            await state.recordError(name: name, severity: severity, code: code)
        }
    }

    /// Record a generic event with optional properties. Properties are PII-guarded.
    public static func event(_ name: String, properties: [String: String]? = nil) {
        Task {
            await state.recordGenericEvent(name: name, properties: properties)
        }
    }

    // MARK: - Control

    /// Force flush pending events to the ingest endpoint.
    public static func flush() async {
        await state.flush()
    }

    /// Toggle event recording. Disabling discards buffered data.
    public static func setEnabled(_ enabled: Bool) {
        Task {
            await state.setEnabled(enabled)
        }
    }

    /// Flush remaining events and clean up. Permanently disables the instance.
    public static func destroy() async {
        await state.destroy()
    }

    // MARK: - Environment Auto-Detection

    /// Auto-detect from build configuration.
    static func detectEnvironment() -> Environment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

// MARK: - Internal State Actor

/// Manages all mutable SDK state with actor isolation for thread safety.
actor TracklessState {

    // Configuration
    private var apiKey: String = ""
    private var endpoint: String = ""
    private var environment: Environment = .production
    private var onError: (@Sendable (Error) -> Void)?
    private var flushIntervalSeconds: TimeInterval = 60
    private var debugLogging: Bool = false

    // State flags
    private var enabled: Bool = false
    private var destroyed: Bool = false
    private var configured: Bool = false

    // Components
    private var buffer = EventBuffer()
    private var circuitBreaker = CircuitBreaker()
    private var context = EventContext(platform: "ios")
    private var session = SessionManager()
    private var funnels = FunnelTracker()

    // Timer and observer (non-isolated for Sendable)
    private let timerState = TimerState()
    private let observerState = ObserverState()

    private let logger = Logger(subsystem: "com.trackless.sdk", category: "telemetry")

    /// Buffer flush threshold
    private let bufferFlushThreshold = 100

    func configure(_ config: TracklessConfig) async {
        // Clean up previous state
        timerState.cancelTimer()
        #if os(iOS) || os(tvOS)
        cleanupObserver()
        #endif

        apiKey = config.apiKey
        endpoint = config.endpoint
        environment = config.environment ?? Trackless.detectEnvironment()
        onError = config.onError
        flushIntervalSeconds = config.flushIntervalSeconds
        debugLogging = config.debugLogging
        enabled = config.enabled
        destroyed = false
        configured = true

        buffer = EventBuffer()
        circuitBreaker = CircuitBreaker()
        context = ContextDetection.detect()
        session = SessionManager()
        funnels = FunnelTracker()

        if debugLogging {
            logger.info("[Trackless] configured — env=\(self.environment.rawValue, privacy: .public) flush=\(Int(self.flushIntervalSeconds))s")
        }

        if enabled {
            await startNewSession()
            startPeriodicFlush()
            addBackgroundObserver()
        }
    }

    func recordEvent(type: EventType, name: String) async {
        guard canRecord() else { return }
        guard let normalized = normalizeName(name) else { return }

        await session.recordActivity()
        await buffer.add(TracklessEvent(type: type, name: normalized))
        await checkFlushThreshold()
    }

    func recordFunnel(funnelName: String, stepName: String) async {
        guard canRecord() else { return }
        guard let normalizedFunnel = normalizeName(funnelName),
              let normalizedStep = normalizeName(stepName) else { return }

        guard let stepIndex = await funnels.step(funnelName: normalizedFunnel, stepName: normalizedStep) else {
            return // Duplicate step
        }

        await session.recordActivity()
        await buffer.add(TracklessEvent(
            type: .funnel,
            name: normalizedFunnel,
            step: normalizedStep,
            stepIndex: stepIndex
        ))
        await checkFlushThreshold()
    }

    func recordSelection(name: String, option: String) async {
        guard canRecord() else { return }
        guard let normalized = normalizeName(name) else { return }
        guard !option.isEmpty else { return }

        await session.recordActivity()
        await buffer.add(TracklessEvent(type: .selection, name: normalized, option: option))
        await checkFlushThreshold()
    }

    func recordPerformance(name: String, duration: Double) async {
        guard canRecord() else { return }
        guard let normalized = normalizeName(name) else { return }
        guard duration >= 0 else { return }

        await session.recordActivity()
        await buffer.add(TracklessEvent(type: .performance, name: normalized, duration: duration))
        await checkFlushThreshold()
    }

    func recordError(name: String, severity: ErrorSeverity, code: String?) async {
        guard canRecord() else { return }
        guard let normalized = normalizeName(name) else { return }

        await session.recordActivity()
        await buffer.add(TracklessEvent(
            type: .error,
            name: normalized,
            severity: severity,
            code: code
        ))
        await checkFlushThreshold()
    }

    func recordGenericEvent(name: String, properties: [String: String]?) async {
        guard canRecord() else { return }
        guard let normalized = normalizeName(name) else { return }

        await session.recordActivity()
        let sanitized = PIIGuard.sanitize(properties)
        await buffer.add(TracklessEvent(
            type: .event,
            name: normalized,
            properties: sanitized
        ))
        await checkFlushThreshold()
    }

    func flush() async {
        await performFlush()
    }

    func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        if !enabled {
            await buffer.clear()
            timerState.cancelTimer()
            #if os(iOS) || os(tvOS)
            cleanupObserver()
            #endif
        } else if !destroyed && configured {
            startPeriodicFlush()
            addBackgroundObserver()
        }
    }

    func destroy() async {
        guard !destroyed else { return }
        destroyed = true

        await endCurrentSession()
        await performFlush()

        timerState.cancelTimer()
        #if os(iOS) || os(tvOS)
        cleanupObserver()
        #endif
        await session.destroy()
        configured = false
    }

    // MARK: - Private Helpers

    private func canRecord() -> Bool {
        enabled && !destroyed && configured
    }

    private func normalizeName(_ name: String) -> String? {
        let normalized = name.lowercased()
        guard !normalized.isEmpty, normalized.count <= FeatureValidator.maxLength else { return nil }
        guard FeatureValidator.isValid(normalized) else {
            if debugLogging {
                logger.warning("[Trackless] rejected invalid event name: \(name, privacy: .public)")
            }
            onError?(TracklessError.invalidFeatureName(name))
            return nil
        }
        return normalized
    }

    private func startNewSession() async {
        let started = await session.start()
        if started {
            await buffer.add(TracklessEvent(type: .session, name: "start"))
        }
    }

    private func endCurrentSession() async {
        guard let result = await session.end() else { return }
        await funnels.clear()
        await buffer.add(TracklessEvent(
            type: .session,
            name: "end",
            count: result.depth,
            duration: Double(result.duration)
        ))
    }

    private func checkFlushThreshold() async {
        let size = await buffer.totalSize
        if size >= bufferFlushThreshold {
            await performFlush()
        }
    }

    private func performFlush() async {
        let isEmpty = await buffer.isEmpty
        guard !isEmpty else { return }

        let canAttempt = await circuitBreaker.canAttempt()
        guard canAttempt else { return }

        let payloads = await buffer.drain(environment: environment.rawValue, context: context)
        guard !payloads.isEmpty else { return }

        for payload in payloads {
            do {
                let result = try await HTTPClient.sendPayload(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    payload: payload
                )

                if result.status >= 500 {
                    await circuitBreaker.recordFailure()
                    if debugLogging {
                        logger.error("[Trackless] flush failed — HTTP \(result.status)")
                    }
                    onError?(TracklessError.flushFailed(statusCode: result.status))
                } else if result.status >= 400 {
                    let bodyText = Self.parseResponseSummary(result.body)
                    onError?(TracklessError.flushRejected(statusCode: result.status, body: bodyText))
                } else {
                    await circuitBreaker.recordSuccess()
                    if debugLogging {
                        logger.info("[Trackless] flush success — HTTP \(result.status)")
                    }
                }
            } catch {
                await circuitBreaker.recordFailure()
                onError?(error)
            }
        }
    }

    private static func parseResponseSummary(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "(no body)" }
        guard let text = String(data: data, encoding: .utf8) else { return "(unreadable body)" }
        if text.count <= 200 { return text }
        return String(text.prefix(200)) + "..."
    }

    // MARK: - Periodic Flush

    private func startPeriodicFlush() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(
            deadline: .now() + flushIntervalSeconds,
            repeating: flushIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.flush()
            }
        }
        timerState.setTimer(timer)
        timer.resume()
    }

    // MARK: - Background Flush

    private func addBackgroundObserver() {
        #if os(iOS) || os(tvOS)
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.endCurrentSession()
                await self.performFlush()
            }
        }
        observerState.setObserver(observer)
        #endif
    }

    #if os(iOS) || os(tvOS)
    private func cleanupObserver() {
        if let observer = observerState.removeObserver() {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    #endif
}

// MARK: - Timer State (thread-safe)

final class TimerState: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    func setTimer(_ newTimer: DispatchSourceTimer) {
        lock.lock()
        timer?.cancel()
        timer = newTimer
        lock.unlock()
    }

    func cancelTimer() {
        lock.lock()
        timer?.cancel()
        timer = nil
        lock.unlock()
    }
}

// MARK: - Observer State (thread-safe)

final class ObserverState: @unchecked Sendable {
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    func setObserver(_ newObserver: NSObjectProtocol) {
        lock.lock()
        observer = newObserver
        lock.unlock()
    }

    func removeObserver() -> NSObjectProtocol? {
        lock.lock()
        let current = observer
        observer = nil
        lock.unlock()
        return current
    }
}

// MARK: - Errors

/// Internal error types for the SDK.
public enum TracklessError: Error, Sendable {
    case invalidFeatureName(String)
    case flushFailed(statusCode: Int)
    case flushRejected(statusCode: Int, body: String)
}
