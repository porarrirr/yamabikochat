import SwiftUI

/// Plain-text thinking panel for streaming updates (avoids WebView reload flicker).
struct ThinkingStreamTextView: View {
    let text: String
    private let bottomAnchorID = "thinking-stream-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(bottomAnchorID)
            }
            .onChange(of: text) { oldValue, newValue in
                guard newValue.count >= oldValue.count else { return }
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

struct ThinkingSheet: View {
    let thinkingText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                Text("Thinking")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            ThinkingStreamTextView(text: thinkingText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
