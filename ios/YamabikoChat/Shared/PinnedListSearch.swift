import SwiftUI

private struct PinnedListSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityLabel(Text(prompt))
                .accessibilityIdentifier("picker-search-field")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L10n.text("クリア")))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : 0)
        .frame(minHeight: 48)
        .background(Color(uiColor: .amoledSecondarySystemFill), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(uiColor: .amoledSystemGroupedBackground))
    }
}

extension View {
    /// Keep picker search directly above the results, including while scrolling.
    func pinnedListSearch(text: Binding<String>, prompt: String) -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedListSearchField(text: text, prompt: prompt)
            }
    }
}
