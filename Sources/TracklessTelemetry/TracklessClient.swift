import Foundation
import os
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Internal configuration container for the Trackless SDK.
struct TracklessConfig: Sendable {
    let apiKey: String
    let endpoint: String
    let environment: TracklessEnvironment?
    let enabled: Bool
    let onError: (@Sendable (Error) -> Void)?
    let flushIntervalSeconds: TimeInterval
    let debugLogging: Bool
    let suppressWarnings: Bool
}

/// Trackless — privacy-first analytics SDK for iOS.
///
/// Static singleton API. Zero dependencies (Foundation only). In-memory only
/// (no UserDefaults, no Keychain, no file system writes). No IDFA, no IDFV,
/// no device identifiers.
///
/// Usage:
/// ```swift
/// Trackless.configure(apiKey: "tl_xxxxxxxxxxxxxxxx")
///
/// Trackless.view("Home")
/// Trackless.feature("export_clicked")
/// ```
public final class Trackless: Sendable {

    /// Default production ingest endpoint.
    public static let defaultEndpoint = "https://api.tracklesstelemetry.com"

    // MARK: - Singleton State

    private static let state = TracklessState()

    // MARK: - State

    /// Whether the SDK has been configured and is ready to record events.
    public static var isConfigured: Bool {
        get async { await state.isConfigured }
    }

    // MARK: - Configure

    /// Configure the SDK and start a new session.
    public static func configure(
        apiKey: String,
        endpoint: String = Trackless.defaultEndpoint,
        environment: TracklessEnvironment? = nil,
        enabled: Bool = true,
        onError: (@Sendable (Error) -> Void)? = nil,
        flushIntervalSeconds: TimeInterval = 60,
        debugLogging: Bool = false,
        suppressWarnings: Bool = false
    ) {
        let config = TracklessConfig(
            apiKey: apiKey,
            endpoint: endpoint,
            environment: environment,
            enabled: enabled,
            onError: onError,
            flushIntervalSeconds: flushIntervalSeconds,
            debugLogging: debugLogging,
            suppressWarnings: suppressWarnings
        )
        Task {
            await state.configure(config)
        }
    }

    // MARK: - Event Recording

    /// Record a view event.
    public static func view(_ name: String, detail: String? = nil) {
        Task {
            await state.recordEvent(type: .view, name: name, detail: detail)
        }
    }

    /// Record a feature usage event.
    public static func feature(_ name: String, detail: String? = nil) {
        Task {
            await state.recordEvent(type: .feature, name: name, detail: detail)
        }
    }

    /// Record a funnel step.
    public static func funnel(_ funnelName: String, stepIndex: Int, step stepName: String) {
        Task {
            await state.recordFunnel(funnelName: funnelName, stepIndex: stepIndex, stepName: stepName)
        }
    }

    /// Record a performance measurement.
    public static func performance(_ name: String, durationSeconds: Double, thresholdSeconds: Double? = nil) {
        Task {
            await state.recordPerformance(name: name, durationSeconds: durationSeconds, thresholdSeconds: thresholdSeconds)
        }
    }

    /// Record an error event.
    public static func error(_ name: String, severity: TracklessErrorSeverity = .error, code: String? = nil) {
        Task {
            await state.recordError(name: name, severity: severity, code: code)
        }
    }

    // MARK: - Control

    /// Force flush pending events to the ingest endpoint.
    public static func flush() async {
        await state.flush()
    }

    /// Toggle event recording. Disabling discards buffered data.
    public static func setEnabled(_ isEnabled: Bool) {
        Task {
            await state.setEnabled(isEnabled)
        }
    }

    /// Flush remaining events and clean up. Permanently disables the instance.
    public static func destroy() async {
        await state.destroy()
    }

    // MARK: - Environment Auto-Detection

    /// Auto-detect from build configuration.
    static func detectEnvironment() -> TracklessEnvironment {
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
    private var environment: TracklessEnvironment = .production
    private var onError: (@Sendable (Error) -> Void)?
    private var flushIntervalSeconds: TimeInterval = 60
    private var debugLogging: Bool = false
    private var suppressWarnings: Bool = false

    // State flags
    private var enabled: Bool = false
    private var destroyed: Bool = false
    private var configured: Bool = false

    // Components
    private var buffer = EventBuffer()
    private var circuitBreaker = CircuitBreaker()
    private var context = TracklessEventContext(platform: "ios")
    private var session = SessionManager()
    private var funnels = FunnelTracker()

    // Timer and observer (non-isolated for Sendable)
    private let timerState = TimerState()
    private let observerState = ObserverState()

    private let logger = Logger(subsystem: "com.trackless.sdk", category: "telemetry")

    /// Buffer flush threshold
    private let bufferFlushThreshold = 100

    var isConfigured: Bool {
        configured && !destroyed
    }

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
        suppressWarnings = config.suppressWarnings
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
            addLifecycleObservers()
        }
    }

    func recordEvent(type: TracklessEventType, name: String, detail: String? = nil) async {
        guard canRecord() else {
            warnDrop("not recording", type: type.rawValue, name: name)
            return
        }
        guard let normalized = normalizeName(name) else { return }

        let rawDetail = (detail?.isEmpty == false) ? detail : nil
        if let rawDetail, rawDetail.count > FeatureValidator.maxLength { return }

        await session.recordActivity()
        let eventDetail = rawDetail.map { FeatureValidator.stripPII($0) }
        await buffer.add(TracklessEvent(type: type, name: normalized, detail: eventDetail))
        if debugLogging {
            if let eventDetail {
                logger.info("[Trackless] \(type.rawValue, privacy: .public) — \(normalized, privacy: .public) detail=\(eventDetail, privacy: .public)")
            } else {
                logger.info("[Trackless] \(type.rawValue, privacy: .public) — \(normalized, privacy: .public)")
            }
        }
        await checkFlushThreshold()
    }

    func recordFunnel(funnelName: String, stepIndex: Int, stepName: String) async {
        guard canRecord() else {
            warnDrop("not recording", type: "funnel", name: funnelName)
            return
        }
        guard stepIndex >= 0 else { return }
        guard let normalizedFunnel = normalizeName(funnelName),
              let normalizedStep = normalizeName(stepName) else { return }

        guard await funnels.step(funnelName: normalizedFunnel, stepIndex: stepIndex) else {
            warnDrop("duplicate funnel step", type: "funnel", name: "\(normalizedFunnel).\(normalizedStep)")
            return
        }

        await session.recordActivity()
        await buffer.add(TracklessEvent(
            type: .funnel,
            name: normalizedFunnel,
            step: normalizedStep,
            stepIndex: stepIndex
        ))
        if debugLogging {
            logger.info("[Trackless] funnel — \(normalizedFunnel, privacy: .public) step=\(normalizedStep, privacy: .public) index=\(stepIndex)")
        }
        await checkFlushThreshold()
    }

    func recordPerformance(name: String, durationSeconds: Double, thresholdSeconds: Double? = nil) async {
        guard canRecord() else {
            warnDrop("not recording", type: "performance", name: name)
            return
        }
        guard let normalized = normalizeName(name) else { return }
        guard durationSeconds >= 0 else {
            warnDrop("negative duration (\(durationSeconds))", type: "performance", name: name)
            return
        }
        if let thresholdSeconds, thresholdSeconds <= 0 { return }

        await session.recordActivity()
        await buffer.add(TracklessEvent(type: .performance, name: normalized, duration: durationSeconds, threshold: thresholdSeconds))
        if debugLogging {
            let thresholdStr = thresholdSeconds.map { " threshold=\($0)s" } ?? ""
            logger.info("[Trackless] performance — \(normalized, privacy: .public) duration=\(durationSeconds)s\(thresholdStr, privacy: .public)")
        }
        await checkFlushThreshold()
    }

    func recordError(name: String, severity: TracklessErrorSeverity, code: String?) async {
        guard canRecord() else {
            warnDrop("not recording", type: "error", name: name)
            return
        }
        guard let normalized = normalizeName(name) else { return }
        if let code, code.count > FeatureValidator.maxLength { return }

        let strippedCode = code.map { FeatureValidator.stripPII($0) }
        await session.recordActivity()
        await buffer.add(TracklessEvent(
            type: .error,
            name: normalized,
            severity: severity,
            code: strippedCode
        ))
        if debugLogging {
            logger.info("[Trackless] error — \(normalized, privacy: .public) severity=\(severity.rawValue, privacy: .public)")
        }
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
            addLifecycleObservers()
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

    private func warn(_ message: String) {
        guard !suppressWarnings else { return }
        logger.warning("[Trackless] \(message, privacy: .public)")
    }

    private func warnDrop(_ reason: String, type: String, name: String) {
        guard !suppressWarnings else { return }
        logger.warning("[Trackless] dropped \(type, privacy: .public) \"\(name, privacy: .public)\" — \(reason, privacy: .public)")
    }

    private func normalizeName(_ name: String) -> String? {
        let normalized = FeatureValidator.stripPII(name.lowercased())
        guard !normalized.isEmpty, normalized.count <= FeatureValidator.maxLength else { return nil }
        guard FeatureValidator.isValid(normalized) else {
            warn("event name rejected: \"\(name)\" — must match [a-z0-9_.-], no leading/trailing/consecutive dots")
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
            stepIndex: result.depth,
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
                    warn("flush failed — HTTP \(result.status)")
                    onError?(TracklessError.flushFailed(statusCode: result.status))
                } else if result.status >= 400 {
                    let bodyText = Self.parseResponseSummary(result.body)
                    warn("flush rejected — HTTP \(result.status) \(bodyText)")
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

    // MARK: - Lifecycle Observers

    private func addLifecycleObservers() {
        #if os(iOS) || os(tvOS)
        let backgroundObserver = NotificationCenter.default.addObserver(
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
        observerState.addObserver(backgroundObserver)

        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleForegroundResume()
            }
        }
        observerState.addObserver(foregroundObserver)
        #endif
    }

    private func handleForegroundResume() async {
        guard canRecord() else { return }
        await startNewSession()
        if debugLogging {
            logger.info("[Trackless] foreground — started new session")
        }
    }

    #if os(iOS) || os(tvOS)
    private func cleanupObserver() {
        for observer in observerState.removeAllObservers() {
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
    private var observers: [NSObjectProtocol] = []

    func addObserver(_ observer: NSObjectProtocol) {
        lock.lock()
        observers.append(observer)
        lock.unlock()
    }

    func removeAllObservers() -> [NSObjectProtocol] {
        lock.lock()
        let current = observers
        observers = []
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
