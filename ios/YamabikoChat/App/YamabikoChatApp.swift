import SwiftUI
import UIKit

@main
struct YamabikoChatApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}

private struct AppBootstrapView: View {
    @State private var services: AppServices?
    @State private var initializationError: Error?
    @State private var isRetrying = false

    var body: some View {
        Group {
            if let services {
                AppRootHost(services: services)
            } else if let initializationError {
                DatabaseRecoveryView(
                    error: initializationError,
                    isRetrying: isRetrying,
                    onRetry: initialize
                )
            } else {
                ProgressView(L10n.text("データベースを準備しています…"))
            }
        }
        .task {
            if services == nil, initializationError == nil {
                initialize()
            }
        }
    }

    private func initialize() {
        guard !isRetrying else { return }
        isRetrying = true
        initializationError = nil
        do {
            services = try AppServices.resolve()
        } catch {
            initializationError = error
            DiagnosticsLogger.log("Database initialization failed", category: .app, error: error)
        }
        isRetrying = false
    }
}

private struct AppRootHost: View {
    @StateObject private var container: AppContainer
    @StateObject private var appState = AppState()

    init(services: AppServices) {
        _container = StateObject(wrappedValue: AppContainer(services: services))
    }

    var body: some View {
        RootView()
            .environmentObject(container)
            .environmentObject(appState)
            .onOpenURL { url in
                guard url == AppConstants.importShareURL else { return }
                while appState.importSharePayload(
                    from: container.sharePayloadStore,
                    repository: container.chatRepository
                ) {}
            }
    }
}

private struct DatabaseRecoveryView: View {
    let error: Error
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.text("データベースを開けません"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(error.localizedDescription)
                .textSelection(.enabled)
        } actions: {
            Button(L10n.text("再試行"), action: onRetry)
                .disabled(isRetrying)
            Button(L10n.text("エラーをコピー")) {
                UIPasteboard.general.string = error.localizedDescription
            }
        }
        .padding()
    }
}
