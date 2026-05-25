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
                .onOpenURL { url in
                    guard url == AppConstants.importShareURL else { return }
                    appState.importSharePayload(
                        from: container.sharePayloadStore,
                        repository: container.chatRepository
                    )
                }
        }
    }
}
