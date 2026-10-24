import SwiftUI

struct DualAutoModelSideForm: View {
    let providerTitleKey: String
    @Binding var provider: String
    let modelTitleKey: String
    @Binding var model: String
    let systemPromptTitleKey: String
    @Binding var systemPrompt: String
    var providerPresets: [ModelPreset] = []
    var catalogProviders: [CatalogProvider] = []
    var openRouterModels: [SimpleModel] = []
    var openRouterModelsLoading = false
    var openRouterModelsError: String?
    var onRefreshOpenRouterModels: () -> Void = {}
    var onProviderPresetSelected: (ModelPreset) -> Void = { _ in }

    @Binding var pccReasoningLevel: String?
    var codexModels: [PiCodexModel] = []
    var initialModel: (String) -> String = ProviderCatalog.defaultModel
    @State private var isPromptExpanded = false

    var body: some View {
        Section {
            ModelSlotForm(
                providerTitleKey: providerTitleKey,
                presetTitleKey: "プリセット",
                provider: $provider,
                modelTitleKey: modelTitleKey,
                model: $model,
                providerPresets: providerPresets,
                catalogProviders: catalogProviders,
                pccReasoningLevel: $pccReasoningLevel,
                codexModels: codexModels,
                initialModel: initialModel,
                onProviderPresetSelected: onProviderPresetSelected,
                openRouterModels: openRouterModels,
                openRouterModelsLoading: openRouterModelsLoading,
                openRouterModelsError: openRouterModelsError,
                onRefreshOpenRouterModels: onRefreshOpenRouterModels
            )
        }
        .pickerStyle(.navigationLink)

        Section {
            Button {
                withAnimation { isPromptExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("システムプロンプト")
                        if !isPromptExpanded {
                            Text(systemPrompt.isEmpty ? "未設定" : systemPrompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 12)
                    Image(systemName: isPromptExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversation-model-prompt")
            .accessibilityValue(isPromptExpanded ? "展開中" : "折りたたみ")
            if isPromptExpanded {
                TextField(L10n.text(systemPromptTitleKey), text: $systemPrompt, axis: .vertical)
                    .lineLimit(3 ... 10)
                    .accessibilityIdentifier("conversation-model-prompt-editor")
            }
        }
    }
}


/// A compact overview keeps configuration readable before opening an editor.
struct ConversationSettingsRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let status: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Expand controls in the current form without adding another navigation level.
struct ConversationAdvancedSettingsSection<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        Section {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(L10n.text("詳細設定"), systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conversation-model-advanced")
            .accessibilityValue(isExpanded ? "展開中" : "折りたたみ")
            if isExpanded {
                content()
            }
        }
    }
}
