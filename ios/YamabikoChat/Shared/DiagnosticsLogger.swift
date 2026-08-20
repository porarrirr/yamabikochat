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

enum DiagnosticsLogger {
    private static let fileName = "yamabiko_diagnostics.log"
    private static let maxBytes = 512 * 1024
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

    static func initialize() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let device = UIDevice.current
        log("Diagnostics enabled. version=\(version)(\(build)) device=\(device.model) ios=\(device.systemVersion)")
    }

    static func log(
        _ message: String,
        level: DiagnosticsLogLevel? = nil,
        category: DiagnosticsLogCategory = .app,
        requestID: String? = nil,
        metadata: [String: String] = [:],
        error: Error? = nil
    ) {
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
    }

    static func read() -> String {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL()
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    private static func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL()
        let manager = FileManager.default

        if let attrs = try? manager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes {
            try? "".write(to: url, atomically: true, encoding: .utf8)
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
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let dir = base.appendingPathComponent("YamabikoChat", isDirectory: true)
        try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }
}
