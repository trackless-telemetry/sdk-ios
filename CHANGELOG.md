# Changelog

All notable changes to the Trackless Telemetry iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-08-26

### Added

- **AGENTS.md** — a README for coding agents, following the [agents.md](https://agents.md) convention: the critical integration rules, the exact public API surface, naming and environment rules in brief, and a pointer to GUIDE.md as the authoritative guide.
- **Verification and troubleshooting documentation** — GUIDE.md gains a "Verify the Integration" section (the exact unified-log signal strings an agent can check unattended — subsystem `com.trackless.sdk`, ending at `[Trackless] flush success — HTTP 200` — plus the dashboard's "See your first feature data" checklist confirmation) and a troubleshooting table decoding the ingest endpoint's deliberately generic responses (401 wrong/regenerated key, 402 quota reached, 429 rate limit, 5xx/network with the circuit breaker's actual behavior — failed batches are not re-sent; backoff only pauses future flushes, 30s → 60m). AGENTS.md gains a matching compact "Verify" block.
- **Anti-interpolation rule documented** — event fields must come from finite sets enumerable at write time; never interpolate runtime values (`Trackless.feature("export_\(format)")` is the failure mode). Stated as a fourth critical rule in AGENTS.md and a subsection under GUIDE.md's event-naming rules, including the per-app daily cardinality budget that drops new `(type, name, detail)` tuples beyond it.
- **.cursorrules completes the critical rules** — now states the no-wrapper rule and the detail-is-a-separate-parameter rule alongside the existing guidance.
- **API key provenance documented** — GUIDE.md and AGENTS.md now state that the key comes from the dashboard, is shown once at app creation, and must be obtained from the developer — never fabricated or committed as a placeholder posing as real.

### Fixed

- **.cursorrules no longer pins a stale version** — the install line said "v0.2.2+"; it now says "latest release" so the file no longer needs a bump on every release.

- **Name-rejection warnings no longer echo raw caller input** — when an event name fails normalization, the warning and the `onError` value now omit the name entirely and explain why it was rejected. Previously both carried the raw, pre-normalization string; because `warn` emits to the unified log with `privacy: .public`, that value was not redacted and persisted in the unified log, where a sysdiagnose bundle would collect it. This is the path the 0.3.0 "Drop warnings never include raw input" entry described but did not actually cover — that change fixed the sibling `warnDrop` path only. `TracklessError.invalidFeatureName` keeps its associated value, but that value is now the *reason* for the rejection rather than the name — the signature is unchanged, so existing `case .invalidFeatureName(let value)` call sites keep compiling. No telemetry was ever affected: nothing here is buffered or transmitted, and PII stripping still runs before any event reaches the wire.

## [0.4.0] - 2026-08-21

### Added

- **Session reach for errors** — the first `error(...)` call for a given name within a session now carries `firstOccurrences: 1`, letting the dashboard compute what share of sessions hit each error (session reach), not just raw counts. This mirrors the existing `firstUses` marker for feature events: dedup is keyed on the normalized error **name only** (not `name` + `severity` + `code`), so a session that raises the same error at several severities or with several codes still contributes exactly one first occurrence. The per-session first-occurrence set is in-memory only and resets on session end; it deliberately survives buffer flushes, so a rolled-up event spanning a session boundary may report `firstOccurrences` greater than 1. Repeats within a session and non-error events send no `firstOccurrences` field. Fully backward compatible: older backends ignore the field.

## [0.3.0] - 2026-07-21

### Added

- **Session reach for features** — the first `feature(...)` call for a given name within a session now carries `firstUses: 1`, letting the dashboard compute what share of sessions used each feature (session reach), not just raw counts. Dedup is keyed on the normalized feature **name only** (not `name` + `detail`), so a session that exercises several detail variants still contributes exactly one first-use. The per-session first-use set is in-memory only and resets on session end (mirroring funnel-step dedup); it deliberately survives buffer flushes, so a rolled-up event spanning a session boundary may report `firstUses` greater than 1. Repeats within a session, non-feature events, and detail variants after the first use send no `firstUses` field. Fully backward compatible: older backends ignore the field.

### Fixed

- **Request body size limit** — flush now checks each serialized payload against the ingest endpoint's 50 KB body limit. Oversized payloads are split in half recursively until each request fits; a single event that exceeds the limit on its own is dropped with a warning. Previously oversized batches were rejected server-side and the whole batch was lost.
- **Buffer-full visibility** — when the event buffer reaches its 1000-item cap and starts rejecting new events, the SDK now logs a warning (at most once per session, re-armed when a new session starts, respects `suppressWarnings`) instead of dropping data silently.
- **Pre-configure visibility** — event methods called before `configure()` now log a one-time warning (respects `suppressWarnings`) instead of dropping events silently.

### Changed

- **Drop warnings never include raw input** — warnings for events dropped *after* validation (the `warnDrop` path) only ever contain normalized (PII-stripped) event names, and warnings for events dropped before validation omit the name entirely. **Correction:** as originally worded this entry overstated the scope. It did not cover the name-rejection warning in `normalizeName`, which kept emitting raw caller input until the fix listed under Unreleased.

## [0.2.4] - 2026-04-18

### Changed

- **More defensive `distributionChannel` detection** — sessions where `Bundle.main.appStoreReceiptURL` is missing, or points at the production receipt path but no receipt file is present, are now reported as `"unknown"` instead of `"app_store"`. This prevents misclassifying Apple Beta App Review sessions (whose reviewer environment doesn't always produce a normal sandbox receipt) as real App Store installs. `"testflight"` and `"app_store"` now require positive evidence — a `sandboxReceipt` path or a present receipt file, respectively.

## [0.2.3] - 2026-04-16

### Added

- **Distribution channel detection** — new `distributionChannel` context field automatically detects how the app was installed: `"testflight"` for TestFlight builds (via App Store sandbox receipt), `"app_store"` for App Store builds, and `"debug"` for debug builds. Enables filtering and grouping by distribution channel in the dashboard.

## [0.2.2] - 2026-03-24

### Added

- Include SDK version (`ios/0.2.2`) in event context for server-side diagnostics
- Add `language` to event context — ISO 639-1 code detected from `Locale.current`

### Changed

- **App Store privacy label guidance updated** — documentation now declares Diagnostics — Crash Data and Diagnostics — Performance Data in addition to Usage Data — Product Interaction, reflecting the error and performance event types. All categories remain Not Linked to User Identity and Not Used for Tracking.
- **Privacy guarantees clarified** — explicitly documents that error tracking collects no stack traces, crash logs, or error messages, and that performance tracking stores no individual duration measurements (server-side t-digest aggregation only).

## [0.2.1] - 2026-03-19

### Changed

- **Graceful field normalization** — `name`, `detail`, `step`, and `code` fields are now automatically normalized before buffering: lowercased, invalid characters replaced with underscores, leading/trailing underscores and dots trimmed, consecutive dots collapsed. Developers can now pass natural strings like `"Sign Up Button"` (becomes `"sign_up_button"`) or `"ERR_001"` (becomes `"err_001"`) instead of having them silently rejected.
- **PII stripping extended** — PII auto-stripping (emails, phone numbers, SSN patterns) now applies to `detail`, `step`, and `code` fields in addition to `name`.
- **Abuse detection extended** — anti-identifier patterns (UUID, long hex, long numeric, all-hex) now apply to `detail`, `step`, and `code` fields. Fields matching abuse patterns are omitted rather than rejecting the entire event.
- Empty `detail` or `code` values no longer cause the entire event to be dropped — the event is recorded without the optional field.

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
