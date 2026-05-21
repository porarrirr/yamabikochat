import SwiftUI

enum SettingsFormHelpers {
    @ViewBuilder
    static func providerPickerRow(title: String, selection: Binding<String>) -> some View {
        Picker(L10n.text(title), selection: selection) {
            ForEach(ProviderCatalog.options) { provider in
                Text(provider.title).tag(provider.key)
            }
        }
    }

    @ViewBuilder
    static func dualAutoProviderPickerRow(title: String, selection: Binding<String>) -> some View {
        Picker(L10n.text(title), selection: selection) {
            ForEach(ProviderCatalog.dualAutoConversationOptions) { provider in
                Text(provider.title).tag(provider.key)
            }
        }
    }
}
