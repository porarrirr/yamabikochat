import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

struct ConversationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "会話"
    static var defaultQuery = ConversationEntityQuery()

    let id: Int
    @Property(title: "タイトル") var title: String
    @Property(title: "更新日時") var updatedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(id: Int64, title: String, updatedAt: Date) {
        self.id = Int(id)
        self.title = title
        self.updatedAt = updatedAt
    }

    init?(_ conversation: Conversation) {
        guard let id = conversation.id, !conversation.isSecret else { return nil }
        self.init(id: id, title: conversation.title,
                  updatedAt: Date(timeIntervalSince1970: Double(conversation.updatedAtMs) / 1000))
    }
}

struct ConversationEntityQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [ConversationEntity] {
        let repository = try AppServices.resolve().conversationRepository
        var found: [Int: ConversationEntity] = [:]
        for start in stride(from: 0, to: identifiers.count, by: 500) {
            let chunk = Array(identifiers[start..<min(start + 500, identifiers.count)])
            for entity in try repository.siriConversations(ids: chunk.map(Int64.init), limit: 500).compactMap(ConversationEntity.init) {
                found[entity.id] = entity
            }
        }
        return identifiers.compactMap { found[$0] }
    }

    func entities(matching string: String) async throws -> [ConversationEntity] {
        try AppServices.resolve().conversationRepository.siriConversations(matching: string)
            .compactMap(ConversationEntity.init)
    }

    func suggestedEntities() async throws -> [ConversationEntity] {
        try AppServices.resolve().conversationRepository.siriConversations(limit: 10)
            .compactMap(ConversationEntity.init)
    }
}

@available(iOS 18.0, *)
extension ConversationEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentModificationDate = updatedAt
        // Only the title is indexed; messages, reasoning and attachments stay in the app.
        attributes.contentDescription = title
        return attributes
    }
}

@available(iOS 18.0, *)
extension ConversationEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "yamabikochat://conversation/\(.id)"
    }
}
