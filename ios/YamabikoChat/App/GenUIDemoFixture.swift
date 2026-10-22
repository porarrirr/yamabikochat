#if DEBUG
import Foundation

enum GenUIDemoFixture {
    static let title = "GenUI ローン比較"

    @MainActor
    static func seed(chatRepository: ChatRepository, conversations: ConversationRepository, timestamp: Int64) throws {
        let messageID: Int64
        if let id = try conversations.siriConversations(matching: title).first(where: { $0.title == title })?.id,
           let existingID = try conversations.fetchLastAssistantMessage(conversationId: id)?.id {
            messageID = existingID
        } else {
            let id = try chatRepository.createConversation(title: title)
            _ = try conversations.insertMessage(ChatMessage(
                conversationId: id, role: "user",
                text: "住宅ローンの条件を動かして、月々の返済額を比較したい。", createdAtMs: timestamp
            ))
            messageID = try conversations.insertMessage(ChatMessage(
                conversationId: id, role: "assistant",
                text: "借入額を動かすと、返済額・比較表・グラフがその場で変わります。", createdAtMs: timestamp + 1
            ))
        }
        let document = try GenUIDocument.validated(from: documentJSON)
        let content = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        let call = ToolCall(id: "genui-loan-demo", name: GenUITool.name, argumentsJSON: documentJSON)
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(
            phase: .finished, call: call,
            result: ToolResult(callId: call.id, name: call.name, content: content), createdAtMs: timestamp + 1
        ))
        if ProcessInfo.processInfo.arguments.contains("-GenUITranscriptOnlyFixture") {
            payload.steps = []
        }
        try conversations.saveToolActivity(messageId: messageID, variantId: nil, payload: payload)
    }

    static let documentJSON = #"""
    {
      "title":"住宅ローンを比較",
      "subtitle":"借入額を変えて、毎月の負担を確認しましょう。",
      "inputs":[
        {"id":"principal","label":"借入額","kind":"slider","value":30000000,"min":10000000,"max":60000000,"step":1000000,"unit":"円"},
        {"id":"rate","label":"年利","kind":"slider","value":1.5,"min":0,"max":5,"step":0.1,"unit":"%"},
        {"id":"years","label":"返済期間","kind":"select","value":35,"unit":"年","options":[{"label":"20年","value":20},{"label":"25年","value":25},{"label":"30年","value":30},{"label":"35年","value":35}]}
      ],
      "components":[
        {"id":"monthly","kind":"metric","title":"月々の返済額","value":"=round(payment(principal,rate,years))","format":"currency","unit":"円","text":"元利均等返済・ボーナス返済なしの概算です。"},
        {"id":"totals","kind":"cards","items":[{"title":"総支払額（円）","value":"=round(payment(principal,rate,years)*years*12)"},{"title":"利息合計（円）","value":"=round(payment(principal,rate,years)*years*12-principal)"}]},
        {"id":"repayment_chart","kind":"chart","title":"返済期間ごとの月額","series":[{"name":"月々の返済","points":[{"label":"20年","value":"=round(payment(principal,rate,20))"},{"label":"25年","value":"=round(payment(principal,rate,25))"},{"label":"30年","value":"=round(payment(principal,rate,30))"},{"label":"35年","value":"=round(payment(principal,rate,35))"}]}]},
        {"id":"comparison","kind":"table","title":"金利を比較","columns":["年利","月額（円）","総返済額（円）"],"rows":[["1.0%","=round(payment(principal,1,years))","=round(payment(principal,1,years)*years*12)"],["1.5%","=round(payment(principal,1.5,years))","=round(payment(principal,1.5,years)*years*12)"],["2.0%","=round(payment(principal,2,years))","=round(payment(principal,2,years)*years*12)"]]},
        {"id":"note","kind":"text","text":"諸費用・税金・保険料は含みません。条件をリセットすると初期値に戻ります。"}
      ]
    }
    """#
}

#endif
