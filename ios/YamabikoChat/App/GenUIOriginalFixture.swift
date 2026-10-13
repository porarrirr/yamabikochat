import Foundation

/// The original componentSource renderers with deterministic supplied data.
/// Currency figures are fixture inputs, not a fetched exchange rate.
enum GenUIOriginalFixture {
    static let document = GenUIDocument(title: "元のコンポーネント", code: code)
    static let code = #"""
    const h = DIL.h;
    return h('col',{gap:4},
      h('Scope',{values:{price:12,quantity:3}},h('text',{'$value':'price * quantity',ariaLabel:'CELで計算した値'})),
      h('DigitalTimerWidget',{__state:{start_time:90,auto_start:false,done_label:'完了'}}),
      h('ClockWidget',{__state:{fixed_tick:0,tz_offset_minutes:540,time_format:'24h',location:'東京'}}),
      h('CurrencyConverterWidget',{__state:{base_amount:100,exchange_rate:150,
        from_currency:'USD',to_currency:'JPY',from_currency_flag:'US',to_currency_flag:'JP',
        from_currency_display_name:'米ドル',to_currency_display_name:'日本円',
        from_currency_symbol:'$',to_currency_symbol:'¥'}}),
      h('chart',{ariaLabel:'元の面グラフ',height:180,data:[{x:'A',value:3},{x:'B',value:5}],series:[{type:'area',dataKey:'value',label:'値'}],xAxis:'x',showYAxis:true}),
      h('ChecklistWidget',{__state:{sections:[{name:'出発前の確認',items:['パスポート','航空券','宿泊先','充電器','保険証書','現地の連絡先']}]}}));
    """#
}
