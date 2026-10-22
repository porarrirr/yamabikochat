import SwiftUI

/// Unmodified assets from OpenAI's official Sign in with ChatGPT guide.
struct ChatGPTBrandIcon: View {
    var inverse = false

    var body: some View {
        Image(inverse ? "ChatGPTLogoInverse" : "ChatGPTLogo")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
