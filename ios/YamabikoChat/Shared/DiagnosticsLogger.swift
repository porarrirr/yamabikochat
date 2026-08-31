import Foundation
import OSLog
import UIKit

enum DiagnosticsLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum DiagnosticsLogCategory: String {
    case app = "APP"
    case auth = "AUTH"
    case chat = "CHAT"
    case fusion = "FUSION"
    case network = "NETWORK"
    case settings = "SETTINGS"
}

struct DiagnosticsAppVersion: Equatable {
    let version: String
    let build: String
}

enum DiagnosticsAppVersionHistory {
    private static let lastLaunchedVersionKey = "DiagnosticsLogger.lastLaunchedAppVersion"
    private static let versionField = "version"
    private static let buildField = "build"

    static func recordLaunch(
        current: DiagnosticsAppVersion,
        defaults: UserDefaults = .standard,
        onVersionChange: (DiagnosticsAppVersion) -> Void
    ) {
        let storedValue = defaults.dictionary(forKey: lastLaunchedVersionKey)
        let previous = storedValue.flatMap { value -> DiagnosticsAppVersion? in
            guard let version = value[versionField] as? String,
                  let build = value[buildField] as? String else {
                return nil
            }
            return DiagnosticsAppVersion(version: version, build: build)
        }

        if let previous, previous != current {
            onVersionChange(previous)
        }

        defaults.set(
            [
                versionField: current.version,
                buildField: current.build
            ],
            forKey: lastLaunchedVersionKey
        )
    }
}

enum DiagnosticsLogger {
    #if DEBUG
    private static let fileName = "yamabiko_diagnostics.log"
    private static let previousFileName = "yamabiko_diagnostics.previous.log"
    private static let runtimeFileName = "yamabiko_pi_runtime.log"
    private static let runtimePreviousFileName = "yamabiko_pi_runtime.previous.log"
    private static let maxBytes = 2 * 1024 * 1024
    private static let lock = NSLock()
    private static let systemLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.porarri.yamabikochat.ios",
        category: "Diagnostics"
    )

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    #endif

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func initialize() {
        #if DEBUG
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let currentVersion = DiagnosticsAppVersion(version: version, build: build)
        DiagnosticsAppVersionHistory.recordLaunch(current: currentVersion) { previousVersion in
            log(
                "App version changed from \(previousVersion.version)(\(previousVersion.build)) " +
                    "to \(currentVersion.version)(\(currentVersion.build))",
                category: .app,
                metadata: [
                    "previousVersion": previousVersion.version,
                    "previousBuild": previousVersion.build,
                    "currentVersion": currentVersion.version,
                    "currentBuild": currentVersion.build
                ]
            )
        }
        let device = UIDevice.current
        log("Diagnostics enabled. version=\(version)(\(build)) device=\(device.model) ios=\(device.systemVersion)")
        Task { @MainActor in
            DiagnosticsLifecycleMonitor.shared.install()
        }
        #endif
    }

    static func log(
        _ message: String,
        level: DiagnosticsLogLevel? = nil,
        category: DiagnosticsLogCategory = .app,
        requestID: String? = nil,
        metadata: [String: String] = [:],
        error: Error? = nil
    ) {
        #if DEBUG
        let timestamp = formatter.string(from: Date())
        let resolvedLevel = level ?? (error == nil ? .info : .error)
        let requestSegment: String
        if let requestID, !requestID.isEmpty {
            requestSegment = " | req=\(requestID)"
        } else {
            requestSegment = ""
        }

        let sanitizedMessage = DiagnosticsLogSanitizer.sanitize(message)
        var lines: [String] = [
            "\(timestamp) | \(resolvedLevel.rawValue) | \(category.rawValue)\(requestSegment) | \(sanitizedMessage)"
        ]

        if !metadata.isEmpty {
            let renderedMetadata = metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(DiagnosticsLogSanitizer.sanitize($0.value))" }
                .joined(separator: " ")
            if !renderedMetadata.isEmpty {
                lines.append("meta=\(renderedMetadata)")
            }
        }

        if let error {
            let nsError = error as NSError
            lines.append("type=\(String(reflecting: type(of: error)))")
            lines.append(
                "\(nsError.domain) (\(nsError.code)): \(DiagnosticsLogSanitizer.sanitize(nsError.localizedDescription))"
            )
            if let reason = nsError.localizedFailureReason, !reason.isEmpty {
                lines.append("reason=\(DiagnosticsLogSanitizer.sanitize(reason))")
            }
            if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
                lines.append("suggestion=\(DiagnosticsLogSanitizer.sanitize(suggestion))")
            }
            let debugDescription = DiagnosticsLogSanitizer.sanitize(String(reflecting: error))
            if !debugDescription.isEmpty {
                lines.append("debug=\(debugDescription)")
            }
        }
        let entry = lines.joined(separator: "\n")
        switch resolvedLevel {
        case .info:
            systemLogger.info("\(entry, privacy: .public)")
        case .warning:
            systemLogger.warning("\(entry, privacy: .public)")
        case .error:
            systemLogger.error("\(entry, privacy: .public)")
        }
        append(entry + "\n")
        #endif
    }

    static func read() -> String {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        return [
            (previousFileURL(), "APP LOG (PREVIOUS)"),
            (logFileURL(), "APP LOG (CURRENT)"),
            (runtimePreviousFileURL(), "PI RUNTIME LOG (PREVIOUS)"),
            (runtimeLogFileURL(), "PI RUNTIME LOG (CURRENT)")
        ].compactMap { url, title in
            guard FileManager.default.fileExists(atPath: url.path),
                  let contents = try? String(contentsOf: url, encoding: .utf8),
                  !contents.isEmpty else {
                return nil
            }
            return "===== \(title) =====\n\(contents)"
        }.joined(separator: "\n")
        #else
        return ""
        #endif
    }

    static func clear() {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        for url in [logFileURL(), previousFileURL(), runtimeLogFileURL(), runtimePreviousFileURL()] {
            try? manager.removeItem(at: url)
        }
        #endif
    }

    #if DEBUG
    /// The embedded Node runtime writes lifecycle failures to a separate file so they remain
    /// available even when its loopback health endpoint is unreachable.
    static func piRuntimeLogPath() -> String {
        lock.lock()
        defer { lock.unlock() }
        return runtimeLogFileURL().path
    }

    private static func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL()
        let manager = FileManager.default
        let byteCount = text.lengthOfBytes(using: .utf8)

        if let attrs = try? manager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue + byteCount > maxBytes {
            let previous = previousFileURL()
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }

        if manager.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
            return
        }

        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func logFileURL() -> URL {
        diagnosticsDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    private static func previousFileURL() -> URL {
        diagnosticsDirectoryURL().appendingPathComponent(previousFileName, isDirectory: false)
    }

    private static func runtimeLogFileURL() -> URL {
        diagnosticsDirectoryURL().appendingPathComponent(runtimeFileName, isDirectory: false)
    }

    private static func runtimePreviousFileURL() -> URL {
        diagnosticsDirectoryURL().appendingPathComponent(runtimePreviousFileName, isDirectory: false)
    }

    private static func diagnosticsDirectoryURL() -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let dir = base.appendingPathComponent("YamabikoChat", isDirectory: true)
        try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    #endif
}

#if DEBUG
@MainActor
private final class DiagnosticsLifecycleMonitor {
    static let shared = DiagnosticsLifecycleMonitor()

    private var observers: [NSObjectProtocol] = []
    private var backgroundStartedAt: TimeInterval?

    private init() {}

    func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observe(UIApplication.willResignActiveNotification, label: "willResignActive", center: center)
        observe(UIApplication.didEnterBackgroundNotification, label: "didEnterBackground", center: center)
        observe(UIApplication.willEnterForegroundNotification, label: "willEnterForeground", center: center)
        observe(UIApplication.didBecomeActiveNotification, label: "didBecomeActive", center: center)
        observe(UIApplication.protectedDataWillBecomeUnavailableNotification, label: "protectedDataUnavailable", center: center)
        observe(UIApplication.protectedDataDidBecomeAvailableNotification, label: "protectedDataAvailable", center: center)
        observe(UIApplication.didReceiveMemoryWarningNotification, label: "memoryWarning", center: center, level: .warning)
        observe(UIApplication.willTerminateNotification, label: "willTerminate", center: center, level: .warning)
        record(label: "monitorInstalled", level: .info)
    }

    private func observe(
        _ name: Notification.Name,
        label: String,
        center: NotificationCenter,
        level: DiagnosticsLogLevel = .info
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.record(label: label, level: level)
            }
        })
    }

    private func record(label: String, level: DiagnosticsLogLevel) {
        let application = UIApplication.shared
        let now = ProcessInfo.processInfo.systemUptime
        var metadata = Self.environmentMetadata(application: application, uptime: now)

        if label == "didEnterBackground" {
            backgroundStartedAt = now
        } else if label == "willEnterForeground" || label == "didBecomeActive" {
            if let backgroundStartedAt {
                metadata["backgroundDurationMs"] = String(Int(max(0, now - backgroundStartedAt) * 1_000))
            }
            if label == "didBecomeActive" {
                backgroundStartedAt = nil
            }
        }

        DiagnosticsLogger.log(
            "Application lifecycle event",
            level: level,
            category: .app,
            metadata: metadata.merging(["event": label], uniquingKeysWith: { current, _ in current })
        )
    }

    static func environmentMetadata(application: UIApplication, uptime: TimeInterval) -> [String: String] {
        let process = ProcessInfo.processInfo
        let state: String
        switch application.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        let thermal: String
        switch process.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let remaining = application.backgroundTimeRemaining
        return [
            "applicationState": state,
            "backgroundTimeRemaining": remaining > 31_536_000
                ? "unlimited"
                : String(format: "%.1f", remaining),
            "lowPowerMode": String(process.isLowPowerModeEnabled),
            "protectedDataAvailable": String(application.isProtectedDataAvailable),
            "systemUptimeMs": String(Int(uptime * 1_000)),
            "thermalState": thermal
        ]
    }
}
#endif
