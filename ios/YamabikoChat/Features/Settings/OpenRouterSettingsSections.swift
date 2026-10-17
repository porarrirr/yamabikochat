import SwiftUI

/// OpenRouter settings presentation. Resolution, persistence and routing stay in the existing view model.
struct OpenRouterSettingsSections: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        modelSection
        reasoningSection
        routingSection
        limitsSection
        endpointsSection
        quantizationSection
    }

    private var modelSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("OpenRouter", systemImage: "network")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.settings.defaultModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            Group {
                Button {
                    Task { await viewModel.refreshOpenRouterModels(force: false) }
                } label: {
                    Label("モデル一覧を取得", systemImage: "arrow.down.circle")
                }
                .disabled(viewModel.openRouterModelsLoading)

                Button {
                    Task { await viewModel.refreshOpenRouterModels(force: true) }
                } label: {
                    Label("キャッシュを使わず更新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.openRouterModelsLoading)
            }

            if viewModel.openRouterModelsLoading {
                ProgressView("読み込み中...")
            }

            if let err = viewModel.openRouterModelsError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        } header: {
            Text("OpenRouter · モデル一覧")
        }
    }

    private var reasoningSection: some View {
        Section {
            if let capabilities = selectedOpenRouterModel?.reasoning {
                Toggle("推論を有効にする", isOn: Binding(
                    get: { capabilities.mandatory || viewModel.settings.openRouterThinkingEnabled },
                    set: {
                        viewModel.setOpenRouterThinkingEnabled(
                            $0,
                            modelId: viewModel.settings.defaultModel
                        )
                    }
                ))
                .disabled(capabilities.mandatory)

                Picker("推論の強さ", selection: reasoningChoiceBinding) {
                    ForEach(OpenRouterReasoningChoice.options(for: capabilities), id: \.self) { choice in
                        switch choice {
                        case .effort(let effort):
                            Text(verbatim: effort).tag(choice)
                        case .budget:
                            Text("トークン数で指定").tag(choice)
                        case .automatic:
                            Text("自動").tag(choice)
                        }
                    }
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.settings.openRouterThinkingEnabled)

                if viewModel.settings.openRouterReasoningMode == "budget",
                   capabilities.supportsMaxTokens {
                    LabeledContent("推論トークン上限") {
                        TextField("0 = 自動", text: Binding(
                            get: { String(max(0, viewModel.settings.openRouterThinkingBudget)) },
                            set: { value in
                                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    viewModel.settings.openRouterThinkingBudget = 0
                                } else if let intValue = Int(trimmed) {
                                    viewModel.settings.openRouterThinkingBudget = max(0, intValue)
                                }
                            }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("推論トークン上限")
                    }
                    .disabled(!viewModel.settings.openRouterThinkingEnabled)
                }

                Toggle("Exclude reasoning from response", isOn: Binding(
                    get: { viewModel.settings.openRouterReasoningExclude },
                    set: { viewModel.settings.openRouterReasoningExclude = $0 }
                ))
                .disabled(!viewModel.settings.openRouterThinkingEnabled)

            } else {
                Text("このモデルはReasoning effort選択に対応していません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        } header: {
            Text("推論")
        }
    }

    private var routingSection: some View {
        Section {
            Picker("接続先の優先基準", selection: Binding(
                get: {
                    let value = viewModel.settings.providerSort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return ["price", "throughput", "latency"].contains(value) ? value : "price"
                },
                set: {
                    let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    viewModel.settings.providerSort = ["price", "throughput", "latency"].contains(normalized) ? normalized : "price"
                }
            )) {
                Text("価格").tag("price")
                Text("生成速度").tag("throughput")
                Text("応答の速さ").tag("latency")
            }

            Picker("選択できる接続先の上限", selection: Binding(
                get: { viewModel.settings.providerSelectionMax },
                set: {
                    viewModel.settings.providerSelectionMax = $0
                    trimPreferredProvidersToSelectionMax()
                }
            )) {
                Text("無制限").tag(0)
                Text("3").tag(3)
                Text("5").tag(5)
                Text("10").tag(10)
                Text("12").tag(12)
                Text("20").tag(20)
                Text("30").tag(30)
            }

        } header: {
            Text("ルーティング")
        }
    }

    private var endpointsSection: some View {
        Section {
            if viewModel.openRouterEndpointsLoading {
                ProgressView("Endpointを読み込み中...")
            }

            if let error = viewModel.openRouterEndpointsError, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            ForEach(viewModel.openRouterEndpointOptions) { endpoint in
                OpenRouterEndpointRow(
                    endpoint: endpoint,
                    isSelected: preferredProviderBinding(endpoint.tag)
                )
            }
            if viewModel.openRouterEndpointOptions.isEmpty,
               !viewModel.openRouterEndpointsLoading,
               viewModel.openRouterEndpointsError == nil {
                Text("このモデルで選択可能なendpoint情報はありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("優先する接続先")
                Spacer()
                Text(L10n.format("%d selected", viewModel.settings.preferredProvidersList().count))
            }
        }
    }

    private var quantizationSection: some View {
        Section {
            ForEach(viewModel.openRouterEndpointQuantizations, id: \.self) { quantization in
                Toggle(quantization, isOn: quantizationBinding(quantization))
            }
            if viewModel.openRouterEndpointQuantizations.isEmpty,
               !viewModel.openRouterEndpointsLoading,
               viewModel.openRouterEndpointsError == nil {
                Text("選択可能なQuantization情報は未取得です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("量子化")
                Spacer()
                Text(L10n.format("%d selected", viewModel.settings.selectedQuantizationsList().count))
            }
        }
    }

    private var limitsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("価格上限")
                    Spacer(minLength: 12)
                    TextField("上限なし", text: Binding(
                        get: {
                            let value = viewModel.settings.maxPricePerMillionTokens
                            return value <= 0 ? "" : String(value)
                        },
                        set: { value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                viewModel.settings.maxPricePerMillionTokens = 0
                            } else if let doubleValue = Double(trimmed) {
                                viewModel.settings.maxPricePerMillionTokens = max(0, doubleValue)
                            }
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("価格上限（USD / 100万トークン、0は上限なし）")
                    .frame(maxWidth: 140)
                }
                Text("USD / 100万トークン · 0で上限なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Allow fallbacks", isOn: Binding(
                get: { viewModel.settings.allowFallbacks },
                set: { viewModel.settings.allowFallbacks = $0 }
            ))
            Toggle("Require parameters", isOn: Binding(
                get: { viewModel.settings.requireParameters },
                set: { viewModel.settings.requireParameters = $0 }
            ))
        } header: {
            Text("価格・リクエスト条件")
        }
    }

    private var reasoningChoiceBinding: Binding<OpenRouterReasoningChoice> {
        Binding(
            get: {
                switch viewModel.settings.openRouterReasoningMode {
                case "effort": return .effort(viewModel.settings.openRouterReasoningEffort)
                case "budget": return .budget
                default: return .automatic
                }
            },
            set: { choice in
                let modelID = viewModel.settings.defaultModel
                switch choice {
                case .effort(let effort):
                    viewModel.setOpenRouterReasoningMode("effort", modelId: modelID)
                    viewModel.setOpenRouterReasoningEffort(effort, modelId: modelID)
                case .budget:
                    viewModel.setOpenRouterReasoningMode("budget", modelId: modelID)
                case .automatic:
                    viewModel.setOpenRouterReasoningMode("auto", modelId: modelID)
                }
            }
        )
    }

    private var selectedOpenRouterModel: SimpleModel? {
        viewModel.openRouterModels.first { $0.id == viewModel.settings.defaultModel }
    }

    private func preferredProviderBinding(_ provider: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.preferredProvidersList().contains(provider.lowercased()) },
            set: { isSelected in
                var selected = viewModel.settings.preferredProvidersList()
                let normalized = provider.lowercased()
                if isSelected {
                    if !selected.contains(normalized) {
                        selected.append(normalized)
                    }
                } else {
                    selected.removeAll { $0 == normalized }
                }
                viewModel.settings.setPreferredProvidersList(selected)
            }
        )
    }

    private func quantizationBinding(_ quantization: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.settings.selectedQuantizationsList().contains(quantization) },
            set: { isSelected in
                var selected = viewModel.settings.selectedQuantizationsList()
                if isSelected {
                    if !selected.contains(quantization) {
                        selected.append(quantization)
                    }
                } else {
                    selected.removeAll { $0 == quantization }
                }
                viewModel.settings.setSelectedQuantizationsList(selected)
            }
        )
    }

    private func trimPreferredProvidersToSelectionMax() {
        let current = viewModel.settings.preferredProvidersList()
        viewModel.settings.setPreferredProvidersList(current)
    }

}

/// Menu order only; available choices still come exclusively from the model contract.
enum OpenRouterReasoningChoice: Hashable {
    case effort(String)
    case budget
    case automatic

    static func options(for capabilities: OpenRouterReasoningCapabilities) -> [Self] {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
        let efforts = capabilities.selectableEfforts.enumerated().sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.element) ?? order.count
            let right = order.firstIndex(of: rhs.element) ?? order.count
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        var choices = efforts.map { Self.effort($0.element) }
        if capabilities.supportsMaxTokens { choices.append(.budget) }
        choices.append(.automatic)
        return choices
    }
}
