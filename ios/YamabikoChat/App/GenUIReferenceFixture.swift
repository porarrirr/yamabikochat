import Foundation

/// A small composition exercise for the reference-inspired renderer, with fictional data.
/// No model, provider or external data requests are needed to exercise its interactions.
enum GenUIReferenceFixture {
    static let document = GenUIDocument(
        title: "毎月の家計を見直す",
        subtitle: "収入と支出を動かして、余裕のあるバランスを探しましょう。例示データです。",
        code: code
    )

    static let code = #"""
    const h = DIL.h;
    const [income, setIncome] = DIL.useState(320000);
    const [rent, setRent] = DIL.useState(90000);
    const [tab, setTab] = DIL.useState('balance');
    const fixed = 105000;
    const saving = income - rent - fixed;
    const rows = [{name:'住居',value:rent},{name:'生活費',value:65000},{name:'その他',value:40000},{name:'貯蓄',value:Math.max(0,saving)}];
    const yen = value => value.toLocaleString('ja-JP') + '円';
    const ratio = income > 0 ? saving/income : 0;
    return h('col', {gap:5},
      h('row', {justify:'between',align:'start'},
        h('col', {gap:1}, h('caption', {}, '毎月の余裕'),
          h('text', {size:36,weight:650,tabularNums:true}, yen(saving))),
        h('badge', {variant:saving>=0?'success':'warning',pill:true,label:saving>=0?'黒字':'見直しが必要'})),
      h('caption', {}, '収入の ' + (ratio*100).toFixed(1) + '% を残せます'),
      h('segmented-control', {ariaLabel:'表示内容',value:tab,onChange:setTab,options:[{value:'balance',label:'収支'},{value:'learn',label:'考え方'}]}),
      tab==='balance' ? h('col', {gap:5},
        h('card', {gap:3},
          h('row', {justify:'between'},h('label', {htmlFor:'income'}, '手取り収入'),h('text', {strong:true,tabularNums:true},yen(income))),
          h('slider', {id:'income',label:'手取り収入',min:200000,max:500000,step:10000,value:income,onChange:setIncome,marks:[{value:200000,label:'20万円'},{value:350000,label:'35万円'},{value:500000,label:'50万円'}]}),
          h('divider'),
          h('row', {justify:'between'},h('label', {htmlFor:'rent'}, '住居費'),h('text', {strong:true,tabularNums:true},yen(rent))),
          h('slider', {id:'rent',label:'住居費',min:40000,max:180000,step:5000,value:rent,onChange:setRent,marks:[{value:40000,label:'4万円'},{value:110000,label:'11万円'},{value:180000,label:'18万円'}]})),
        h('col',{gap:3},
          h('title',{size:'lg'},'支出の内訳'),
          h('Chart',{content:{chartType:'bar',data:rows.map(row=>({x:row.name,value:row.value})),series:[{dataKey:'value',label:'月額',valueSuffix:'円'}],showLegend:false}})),
        h('popover',{},
          h('popover-trigger',{},'計算の前提を見る'),
          h('popover-content',{},h('markdown',{},'生活費は **65,000円**、その他の支出は **40,000円** と仮定しています。\n\n税金・臨時支出は含めていません。自分の条件に置き換えて比較してください。'))),
        h('button',{variant:'outline',label:'初期値に戻す',onClick:()=>{setIncome(320000);setRent(90000);}},h('icon',{name:'refresh'})))
      : h('col',{gap:4},
        h('title',{size:'lg'},'お金の流れを整理する'),
        h('markdown',{},'1. 毎月の収入を把握する\n2. 固定費を先に引く\n3. 残った金額の使い道を決める'),
        h('flashcard-flip',{label:'タップして答えを見る',front:h('col',{gap:2},h('caption',{},'確認してみましょう'),h('text',{},'貯蓄に回せる金額は？')),back:h('col',{gap:2},h('caption',{},'収入 − 住居費 − その他の支出'),h('text',{tabularNums:true},yen(saving)))}),
        h('caption',{},'条件を動かして、答えが変わる理由を確かめてみてください。')));
    """#
}
