import Foundation

enum AppGroupShareStorage {
    static let payloadQueueDirectoryName = "share_payloads"
    static let failedPayloadDirectoryName = "share_payloads_failed"

    struct QueuedPayload: Equatable {
        let id: UUID
        let data: Data
        fileprivate let fileURL: URL
    }

    #if DEBUG
    /// Overrides the app group container URL in unit tests.
    static var testContainerURL: URL?
    #endif

    static func containerURL(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> URL? {
        #if DEBUG
        if let testContainerURL {
            return testContainerURL
        }
        #endif
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func payloadQueueURL(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> URL? {
        containerURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager)?
            .appendingPathComponent(payloadQueueDirectoryName, isDirectory: true)
    }

    @discardableResult
    static func writePayloadData(
        _ data: Data,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let queueURL = payloadQueueURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager) else {
            return false
        }
        do {
            try fileManager.createDirectory(at: queueURL, withIntermediateDirectories: true)
            let fileURL = queueURL.appendingPathComponent(
                String(
                    format: "%020llu-%@.json",
                    UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
                    UUID().uuidString
                ),
                isDirectory: false
            )
            try data.write(to: fileURL, options: .atomic)
            SharePayloadDarwinNotifier.postChange()
            return true
        } catch {
            return false
        }
    }

    static func consumePayloadData(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Data? {
        guard let queued = peekPayload(
            appGroupIdentifier: appGroupIdentifier,
            fileManager: fileManager
        ) else { return nil }
        guard acknowledge(
            queued,
            appGroupIdentifier: appGroupIdentifier,
            fileManager: fileManager
        ) else { return nil }
        return queued.data
    }

    static func readPayloadData(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Data? {
        peekPayload(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager)?.data
    }

    static func peekPayload(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> QueuedPayload? {
        guard let queueURL = payloadQueueURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: queueURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else { return nil }
        for fileURL in urls.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let stem = fileURL.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: fileURL),
                  let separator = stem.firstIndex(of: "-"),
                  let id = UUID(uuidString: String(stem[stem.index(after: separator)...]))
            else { continue }
            return QueuedPayload(id: id, data: data, fileURL: fileURL)
        }
        return nil
    }

    @discardableResult
    static func acknowledge(
        _ queued: QueuedPayload,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let queueURL = payloadQueueURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager),
              queued.fileURL.deletingLastPathComponent().standardizedFileURL == queueURL.standardizedFileURL,
              let currentData = try? Data(contentsOf: queued.fileURL),
              currentData == queued.data
        else { return false }
        do {
            try fileManager.removeItem(at: queued.fileURL)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func quarantine(
        _ queued: QueuedPayload,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let containerURL = containerURL(
            appGroupIdentifier: appGroupIdentifier,
            fileManager: fileManager
        ) else { return false }
        let failedURL = containerURL.appendingPathComponent(failedPayloadDirectoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: failedURL, withIntermediateDirectories: true)
            try fileManager.moveItem(
                at: queued.fileURL,
                to: failedURL.appendingPathComponent(queued.fileURL.lastPathComponent)
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func removePayloadData(
        matching expectedData: Data,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let queued = peekPayload(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager),
              queued.data == expectedData else { return false }
        return acknowledge(queued, appGroupIdentifier: appGroupIdentifier, fileManager: fileManager)
    }
}

enum SharePayloadDarwinNotifier {
    private static let notificationName = AppConstants.sharePayloadDarwinNotification as CFString

    private final class HandlerBox {
        let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private static var handlerBox: HandlerBox?

    static func startObserving(_ handler: @escaping () -> Void) {
        stopObserving()
        let box = HandlerBox(handler: handler)
        handlerBox = box
        let observer = Unmanaged.passUnretained(box).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    box.handler()
                }
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }

    static func stopObserving() {
        guard let handlerBox else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(handlerBox).toOpaque(),
            CFNotificationName(notificationName),
            nil
        )
        self.handlerBox = nil
    }

    static func postChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
    }
}
