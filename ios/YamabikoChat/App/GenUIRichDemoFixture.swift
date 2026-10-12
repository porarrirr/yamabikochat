import Foundation

enum GenUIRichDemoFixture {
    static let title = "GenUI コンポーネント"

    @MainActor
    static func seed(chatRepository: ChatRepository, conversations: ConversationRepository, timestamp: Int64) throws {
        let messageID: Int64
        if let id = try conversations.siriConversations(matching: title).first(where: { $0.title == title })?.id,
           let existing = try conversations.fetchLastAssistantMessage(conversationId: id)?.id {
            messageID = existing
        } else {
            let id = try chatRepository.createConversation(title: title)
            messageID = try conversations.insertMessage(ChatMessage(conversationId: id, role: "assistant", text: "部品の状態を共有し、グラフやカードを同時に更新できます。", createdAtMs: timestamp))
        }
        let document = GenUIDocument(title: "ひとつの操作で、表示が変わる", subtitle: "入力・カード・グラフをつないだGenUI", code: code)
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        _ = try GenUIDocument.validated(from: json)
        let call = ToolCall(id: "genui-rich-demo", name: GenUITool.name, argumentsJSON: json)
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(phase: .finished, call: call, result: ToolResult(callId: call.id, name: call.name, content: json), createdAtMs: timestamp))
        try conversations.saveToolActivity(messageId: messageID, variantId: nil, payload: payload)
    }

    static let code = #"""
    const h = DIL.h;
    const [name,setName] = DIL.useState('東京');
    const [mode,setMode] = DIL.useState('light');
    const [volume,setVolume] = DIL.useState(65);
    const [enabled,setEnabled] = DIL.useState(true);
    const chart = DIL.useMemo(() => ({chartType:'bar',xKey:'name',valueSuffix:'%',yAxisMin:0,yAxisMax:100,data:[{name:'現在',value:volume},{name:'目標',value:80}],series:[{dataKey:'value',label:'達成率'}]}),[volume]);
    const reset = () => {setName('東京');setMode('light');setVolume(65);setEnabled(true);};
    return h('col',{gap:5},
      h('row',{justify:'between',align:'center',wrap:true},h('badge',{color:'success',pill:true,label:'状態を共有'}),h('caption',{color:'secondary'},'DIL / LOCAL STATE')),
      h('card',{padding:4,gap:3},
        h('label',{weight:600},'表示する名前'),
        h('input',{name:'name',value:name,placeholder:'名前を入力',onChange:setName}),
        h('segmented-control',{label:'表示モード',value:mode,options:[{label:'ライト',value:'light'},{label:'ダーク',value:'dark'}],onChange:setMode}),
        h('row',{justify:'between'},h('label',{},'slider.value'),h('badge',{label:String(volume),pill:true})),
        h('slider',{name:'volume',value:volume,min:0,max:100,step:1,onChange:setVolume}),
        h('checkbox',{checked:enabled,label:'表示を有効にする',onChange:setEnabled})
      ),
      h('grid',{columns:2,gap:3},
        h('card',{padding:4,theme:mode},h('caption',{color:'secondary'},'現在の名前'),h('title',{size:'xl'},name)),
        h('card',{padding:4,theme:mode},h('caption',{color:'secondary'},'現在の値'),h('title',{size:'xl',tabularNums:true},String(volume)+'%'))
      ),
      h('Chart',{content:chart}),
      h('CodeBlock',{language:'json'},JSON.stringify({name,mode,volume,enabled},null,2)),
      h('row',{gap:3,wrap:true},h('button',{label:'初期値に戻す',onClick:reset}),h('button',{label:'状態をコピー',variant:'secondary',onClick:()=>GenUI.copy(JSON.stringify({name,mode,volume,enabled}))})),
      h('popover',{},h('popover-trigger',{},'補足を表示'),h('popover-content',{showCloseButton:true},h('text',{},'入力とグラフは同じ状態を参照しています。'))),
      h('MapWidgetV2',{title:'東京の地点',points:[{id:'tokyo',lat:35.6812,lng:139.7671,title:'東京駅'}],narrative:'指定した座標をiOSの地図で確認できます。'})
    );
    """#
}
