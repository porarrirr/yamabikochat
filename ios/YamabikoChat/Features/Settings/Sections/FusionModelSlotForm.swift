import SwiftUI

struct FusionModelSlotForm: View {
    let providerTitleKey: String
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String

    var body: some View {
        SettingsFormHelpers.dualAutoProviderPickerRow(
            title: providerTitleKey,
            selection: Binding(
                get: { provider.uppercased() },
                set: { provider = $0.uppercased() }
            )
        )
        TextField(L10n.text(modelTitleKey), text: $model)
    }
}