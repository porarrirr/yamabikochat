import SwiftUI

@main
struct YamabikoChatApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(appState)
                .onAppear {
                    appState.consumeSharePayload(from: container.sharePayloadStore)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppConstants.sharePayloadDidChangeNotification)) { _ in
                    appState.consumeSharePayload(from: container.sharePayloadStore)
                }
        }
    }
}