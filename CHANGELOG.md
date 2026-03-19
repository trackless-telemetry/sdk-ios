# Changelog

All notable changes to the Trackless Telemetry iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-19

### Added

- Static singleton API: `Trackless.configure(apiKey:endpoint:)` with typed event methods
- Event types: `view(name:detail:)`, `feature(name:detail:)`, `funnel(name:stepIndex:stepName:)`, `performance(name:duration:threshold:)`, `error(name:severity:code:)`
- Automatic session lifecycle management with duration and screen depth tracking via `UIApplication` lifecycle notifications (`didEnterBackground`, `willEnterForeground`)
- Client-side event rollup — count-aggregatable events deduplicated and counted by key, performance durations collected into arrays
- Periodic flush every 60 seconds with auto-flush at 100 unique items
- Forced flush on app backgrounding and `destroy()`
- Circuit breaker with exponential backoff (30s → 1m → 5m → 15m → 60m) on 5xx/network errors; 4xx errors discard the batch without backoff
- Coarse context detection: platform, OS major version, device class (phone/tablet/desktop via UIDevice idiom), region, app version, build number, days since install
- Swift actor-based concurrency for thread-safe state management
- PII guard strips emails, phone numbers, and SSN patterns from event names before buffering
- Identifier rejection for UUIDs, long hex sequences, numeric-only strings, and hex-dominant strings
- Event name validation: lowercase alphanumeric with `_`, `-`, `.` (1–100 chars)
- Automatic environment detection via `#if DEBUG` (sandbox in debug builds, production otherwise)
- Conditional compilation support for macOS, tvOS, and visionOS
- Zero external dependencies (Foundation only)
- No IDFA/IDFV collection
- No client-side persistence
- Max buffer size of 1,000 unique items; max 100 events per HTTP request
- Published as Swift Package: `https://github.com/trackless-telemetry/sdk-ios`
