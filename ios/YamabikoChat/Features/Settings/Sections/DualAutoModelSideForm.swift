import SwiftUI

struct DualAutoModelSideForm: View {
    let providerTitleKey: String
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String
    let systemPromptTitleKey: String
    @Binding var systemPrompt: String
    var systemPromptLineLimit: ClosedRange<Int> = 2 ... 8

    var body: some View {
        SettingsFormHelpers.dualAutoProviderPickerRow(
            title: providerTitleKey,
            selection: Binding(
                get: { provider.uppercased() },
                set: { provider = $0.uppercased() }
            )
        )
        TextField(L10n.text(modelTitleKey), text: $model)
        TextField(L10n.text(systemPromptTitleKey), text: $systemPrompt, axis: .vertical)
            .lineLimit(systemPromptLineLimit)
    }
}
