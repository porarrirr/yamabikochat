import AppIntents
import SwiftUI

extension View {
    @ViewBuilder
    func siriConversationContext(id: Int64, isSecret: Bool) -> some View {
        if #available(iOS 27.0, *) {
            self.appEntityIdentifier(isSecret ? nil : EntityIdentifier(for: ConversationEntity.self, identifier: Int(id)))
        } else {
            self
        }
    }
}
