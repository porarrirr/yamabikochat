import Foundation

enum AppGroupShareStorage {
    static let payloadFileName = "share_payload.json"

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

    static func payloadFileURL(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> URL? {
        containerURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager)?
            .appendingPathComponent(payloadFileName, isDirectory: false)
    }

    @discardableResult
    static func writePayloadData(
        _ data: Data,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let fileURL = payloadFileURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager) else {
            return false
        }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
        guard let data = readPayloadData(
            appGroupIdentifier: appGroupIdentifier,
            fileManager: fileManager
        ) else { return nil }
        guard removePayloadData(
            matching: data,
            appGroupIdentifier: appGroupIdentifier,
            fileManager: fileManager
        ) else { return nil }
        return data
    }

    static func readPayloadData(
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Data? {
        guard
            let fileURL = payloadFileURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager),
            fileManager.fileExists(atPath: fileURL.path)
        else {
            return nil
        }

        return try? Data(contentsOf: fileURL)
    }

    @discardableResult
    static func removePayloadData(
        matching expectedData: Data,
        appGroupIdentifier: String = AppConstants.appGroupIdentifier,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let fileURL = payloadFileURL(appGroupIdentifier: appGroupIdentifier, fileManager: fileManager),
              let currentData = try? Data(contentsOf: fileURL),
              currentData == expectedData
        else { return false }
        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
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
