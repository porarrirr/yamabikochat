/* Run with node --test ios/GenUIRuntimeTests/runtime.test.js; no npm install. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const runtimePath = path.join(__dirname, '../YamabikoChat/App/Resources/genui/runtime.js');
const referenceAssets = ['reference-components.js','reference-tokens.js','reference-icons.js','markdown-it.js'];
for (const asset of referenceAssets) require(path.join(path.dirname(runtimePath), asset));
const api = require(runtimePath);

class Element {
    constructor(tag) {
        this.tagName = tag.toUpperCase(); this.children = []; this.dataset = {};
        this.attributes = {}; this.listeners = {}; this._text = '';
        this.style = {setProperty(key, value) {this[key] = value;}};
        this.classList = {add() {}};
    }
    set textContent(value) {this._text = String(value); this.children = [];}
    get textContent() {return this._text + this.children.map(c => c.textContent ?? String(c)).join('');}
    append(...children) {children.forEach(child=>{if(child&&typeof child==='object')child.parentElement=this;this.children.push(child);});}
    replaceWith(replacement) {const parent=this.parentElement;const index=parent.children.indexOf(this);parent.children[index]=replacement;replacement.parentElement=parent;}
    replaceChildren(...children) {this._text = ''; this.children = children;}
    setAttribute(key, value) {this.attributes[key] = String(value);}
    addEventListener(type, handler) {(this.listeners[type] ||= []).push(handler);}
    fire(type, isTrusted = false) {(this.listeners[type] || []).forEach(fn => fn({isTrusted, preventDefault() {}}));}
    querySelectorAll(selector) {
        const tags = selector.split(',').map(s => s.toUpperCase());
        return this.children.flatMap(c => c instanceof Element ? [...(tags.includes(c.tagName) ? [c] : []), ...c.querySelectorAll(selector)] : []);
    }
    getBoundingClientRect() {return {x:0, y:0, width:320, height:180};}
}

function mount(config, width = 320, saved = {}) {
    const root = new Element('main'), html = new Element('html'), messages = [], tasks = [];
    html.scrollHeight = 300;
    const documentListeners={};
    const document = {
        addEventListener(type,listener){(documentListeners[type] ||= []).push(listener);},
        fire(type,target){(documentListeners[type]||[]).forEach(listener=>listener({type,target,isTrusted:true}));},
        readyState:'complete', body:root, documentElement:html,
        getElementById() {return root;},
        createElement:tag => new Element(tag), createElementNS:(_, tag) => new Element(tag),
        createTextNode:text => ({textContent:String(text)}), createDocumentFragment:() => new Element('fragment')
    };
    const context = {document, __GENUI_DOCUMENT__:config, __GENUI_SAVED_STATE__:saved, innerWidth:width, URL, atob, btoa, TextDecoder, Uint8Array,
        webkit:{messageHandlers:{genui:{postMessage(value) {messages.push(value);}}}},
        addEventListener() {}, requestAnimationFrame:fn => fn(),
        ResizeObserver:class {observe() {}}, queueMicrotask:fn => tasks.push(fn),
        Date, setInterval:() => 1, clearInterval() {}, setTimeout:fn => tasks.push(fn), clearTimeout() {}};
    context.window = context;
    for (const asset of referenceAssets) vm.runInNewContext(fs.readFileSync(path.join(path.dirname(runtimePath),asset),'utf8'), context);
    vm.runInNewContext(fs.readFileSync(runtimePath, 'utf8'), context);
    return {root, messages, context, flush() {let limit=50; while(tasks.length && limit--) tasks.shift()(); assert.ok(limit>0, 'bounded render queue');}};
}

test('Node import exposes vocabulary without installing browser globals', () => {
    assert.equal(globalThis.DIL, undefined);
    assert.equal(globalThis.GenUI, undefined);
    for (const name of ['Chart','MapWidgetV2','AsyncVideo','AppBlock','WritingBlock','segmented-control']) {
        assert.ok(api.componentNames.includes(name), name);
    }
    assert.equal(new Set(api.componentNames).size, api.componentNames.length);
});

test('text interpolation is literal and does not evaluate data as code', () => {
    assert.equal(api.interpolate('Hello {{name}}: {{n}}', {name:'Tokyo', n:0}), 'Hello Tokyo: 0');
    assert.equal(api.interpolate('{{missing}}', {}), '');
    assert.equal(api.interpolate('{{name}}', {name:'<script>bad()</script>'}), '<script>bad()</script>');
    assert.deepEqual(api.h('row', {}, ['first', [api.h('text', {}, 'second')]]).children.map(c => typeof c === 'string' ? c : c.type), ['first','text']);
});

test('URL helpers reject executable/local schemes', () => {
    for (const url of ['javascript:alert(1)', 'file:///private/a', 'data:text/html,hi', '/relative', 'http://example.com', 'https://user:secret@example.com']) assert.equal(api.safeURL(url), null);
    assert.equal(api.safeURL('https://example.com/path'), 'https://example.com/path');
});

test('external action requires a trusted user event', () => {
    const app = mount({ui:api.h('button', {label:'Open', onClick:{type:'openUrl', url:'https://example.com'}})});
    const button = app.root.querySelectorAll('button')[0];
    assert.equal(app.messages.some(m => m.type === 'openUrl'), false);
    button.fire('click');
    assert.equal(app.messages.some(m => m.type === 'openUrl'), false);
    button.fire('click', true);
    assert.equal(app.messages.filter(m => m.type === 'openUrl').length, 1);
});

test('effects cannot silently open URLs or submit turns', () => {
    const app = mount({code:"DIL.useEffect(() => { GenUI.openUrl('https://example.com'); GenUI.issueNewTurn('hidden'); }, []); return DIL.h('text', {}, 'Ready');"});
    app.flush();
    assert.ok(app.root.textContent.includes('Ready'));
    assert.equal(app.messages.some(m => m.type === 'error'), false);
    assert.equal(app.messages.some(m => ['openUrl','issueNewTurn'].includes(m.type)), false);
});

test('deep data interpolation preserves numeric/boolean types', () => {
    const resolved = api.resolve({data:[{x:'{{x}}', value:'{{value}}'}], enabled:'{{enabled}}'}, {x:3, value:12, enabled:false});
    assert.deepEqual(resolved, {data:[{x:3, value:12}], enabled:false});
});

test('hook snapshots preserve explicit null state without environment data', () => {
    const app = mount({code:"const [value] = DIL.useState(null); return DIL.h('text', {}, String(value));"});
    const snapshot = JSON.parse(JSON.stringify(app.context.GenUIRuntime.getSnapshot()));
    assert.deepEqual(snapshot, {bindings:{}, hooks:[null], hookSlots:{'root:0':null}});
    assert.equal(app.root.textContent, 'null');
});

test('local binding updates shared text without submitting a model turn', () => {
    const app = mount({state:{amount:5}, ui:api.h('col', {}, api.h('slider', {bind:'amount', min:0, max:100}), api.h('text', {}, 'Amount {{amount}}'))});
    const slider = app.root.querySelectorAll('input')[0];
    slider.value = '25'; slider.fire('input', true); app.flush();
    assert.ok(app.root.textContent.includes('Amount 25'));
    assert.equal(app.messages.some(m => m.type === 'issueNewTurn'), false);
});

test('maps render inline without an open button or presentation action', () => {
    const props = {title:'Tokyo', points:[{lat:35.6, lng:139.7, name:'Stop'}]};
    const app = mount({ui:api.h('MapWidgetV2', props)});
    assert.equal(app.root.querySelectorAll('button').length, 0);
    assert.equal(app.messages.some(m => m.type === 'openMap'), false);
    const message = app.messages.find(m => m.type === 'maps');
    assert.equal(message.maps.length, 1);
    assert.deepEqual(JSON.parse(JSON.stringify(message.maps[0].props)), props);
    assert.deepEqual(JSON.parse(JSON.stringify(message.maps[0].frame)), {x:0,y:0,width:320,height:180});
});

test('maps display and forward place names addresses and queries without coordinates', () => {
    const props = {points:[{name:'東京駅'},{address:'大阪市北区'},{query:'京都駅'}], origin:{name:'品川駅'}};
    const app = mount({ui:api.h('MapWidgetV2', props)});
    for (const place of ['東京駅','大阪市北区','京都駅']) assert.ok(app.root.textContent.includes(place));
    assert.equal(app.root.textContent.includes('undefined'), false);
    assert.equal(app.messages.some(m => m.type === 'openMap'), false);
    const message = app.messages.find(m => m.type === 'maps');
    assert.deepEqual(JSON.parse(JSON.stringify(message.maps[0].props)), props);
});

test('inline map layout removes hidden maps and follows local state changes', () => {
    const app = mount({state:{visible:true}, code:"return DIL.h('col',{},state.visible && DIL.h('MapWidgetV2',{points:[{name:'東京駅'}]}),DIL.h('button',{label:'Hide',onClick:{type:'setState',key:'visible',value:false}}));"});
    assert.equal(app.messages.filter(m => m.type === 'maps').at(-1).maps.length, 1);
    app.root.querySelectorAll('button')[0].fire('click', true);
    app.flush();
    assert.equal(app.messages.filter(m => m.type === 'maps').at(-1).maps.length, 0);
    assert.equal(app.messages.some(m => m.type === 'openMap'), false);
});

test('unknown image references and app bundles show an unavailable result', () => {
    const app = mount({ui:api.h('col', {}, api.h('AsyncImage', {ref:'proprietary'}), api.h('AppBlock', {title:'App', app_block_id:'remote', entrypoint:'https://example.com/app.js'}))});
    assert.ok(app.root.textContent.includes('unavailable'));
    assert.equal(app.root.querySelectorAll('img,script').length, 0);
});

test('charts render negative bars and numeric scatter positions from supplied data', () => {
    const bar = mount({ui:api.h('Chart', {content:{chartType:'bar', data:[{x:'a', value:-3},{x:'b', value:4}]}})});
    const marks = bar.root.querySelectorAll('rect');
    assert.equal(marks.length, 2);
    assert.ok(marks.every(mark => Number(mark.attributes.height)>0));
    const scatter = mount({ui:api.h('Chart', {content:{chartType:'scatter', xKey:'x', data:[{x:0,value:1},{x:1,value:2},{x:100,value:3}]}})});
    const circles = scatter.root.querySelectorAll('circle');
    assert.equal(circles.length, 3);
    const xs = circles.map(c => Number(c.attributes.cx));
    assert.ok(xs[1]-xs[0] < (xs[2]-xs[1])/10, 'scatter must preserve numeric x spacing');
});

test('resetState resets both local bindings and useState hooks', () => {
    const app = mount({state:{name:'initial'}, code:"const [n,setN]=DIL.useState(3); return DIL.h('col',{},DIL.h('text',{},String(n)),DIL.h('button',{label:'Increment',onClick:()=>setN(n+1)}),DIL.h('button',{label:'Reset',onClick:{type:'resetState'}}));"});
    app.root.querySelectorAll('button')[0].fire('click', true); app.flush();
    assert.equal(app.context.GenUIRuntime.getSnapshot().hooks[0], 4);
    app.root.querySelectorAll('button')[1].fire('click', true); app.flush();
    assert.equal(app.context.GenUIRuntime.getSnapshot().hooks[0], 3);
    assert.equal(app.context.GenUIRuntime.getSnapshot().bindings.name, 'initial');
});

test('text citations open only the supplied line range on a trusted click', () => {
    const app = mount({resources:{file:{title:'Source',text:'first\nsecond\nthird'}},ui:api.h('FileCite',{ref:'file',line_range_start:2,line_range_end:2})});
    const button=app.root.querySelectorAll('button')[0];
    button.fire('click'); assert.equal(app.messages.some(m=>m.type==='openEntityDetail'),false);
    button.fire('click',true);
    assert.equal(app.messages.find(m=>m.type==='openEntityDetail').args.text,'second');
});

test('multiple citation refs remain separate resolved links', () => {
    const app=mount({resources:{a:{title:'First',url:'https://example.com/a'},b:{title:'Second',url:'https://example.com/b'}},ui:api.h('Cite',{refs:['a','b']})});
    const links=app.root.querySelectorAll('button');assert.equal(links.length,2);
    links[1].fire('click',true);
    assert.equal(app.messages.find(m=>m.type==='openUrl').url,'https://example.com/b');
});

test('range pointer drag retains the input node while shared content updates', () => {
    const app=mount({state:{amount:5},ui:api.h('col',{},api.h('input',{value:'Name'}),api.h('slider',{bind:'amount'}),api.h('text',{},'Amount {{amount}}'))});
    const slider=app.root.querySelectorAll('input')[1];
    app.context.document.fire('pointerdown',slider);
    slider.value='35';slider.fire('input',true);app.flush();
    assert.equal(app.root.querySelectorAll('input')[1],slider,'active range survives rerender');
    assert.ok(app.root.textContent.includes('Amount 35'));
    slider.value='55';slider.fire('input',true);app.flush();
    assert.equal(app.root.querySelectorAll('input')[1],slider);
    assert.ok(app.root.textContent.includes('Amount 55'));
    app.context.document.fire('pointerup',slider);app.flush();
    assert.notEqual(app.root.querySelectorAll('input')[1],slider,'drag ends and normal reconciliation resumes');
});

test('JavaScript arithmetic Math functions and custom calculations use the code renderer', () => {
    const code = `
        const [principal, setPrincipal] = DIL.useState(300000);
        const monthly = DIL.useMemo(() => {
            const rate = 5 / 1200, months = 30 * 12;
            return principal * rate / (1 - (1 + rate) ** -months);
        }, [principal]);
        function compound(amount, rate, years) { return amount * Math.pow(1 + rate, years); }
        const stats = [1, 2, 3].reduce((sum, n) => sum + n, 0) / 3;
        const arithmetic = (8 + 4 - 2) * 3 / 2 + 2 ** 3;
        return DIL.h('col', {},
            DIL.h('text', {}, JSON.stringify([monthly, arithmetic, Math.min(4, 2, 3), Math.max(4, 2, 3), Math.abs(-3), Math.round(4.6), Math.pow(2, 3), compound(100, 0.1, 2), stats])),
            DIL.h('button', {label: 'Double', onClick: () => setPrincipal(p => p * 2)}));
    `;
    const app = mount({code});
    const numbers = () => JSON.parse(app.root.children[0].children[0].children[0].textContent);
    assert.ok(Math.abs(numbers()[0] - 1610.464869) < 0.00001);
    assert.deepEqual(numbers().slice(1, 7), [23, 2, 4, 3, 5, 8]);
    assert.ok(Math.abs(numbers()[7] - 121) < 0.00001);
    assert.equal(numbers()[8], 2);
    app.root.querySelectorAll('button')[0].fire('click', true); app.flush();
    assert.ok(Math.abs(numbers()[0] - 3220.929738) < 0.00001);
    assert.equal(app.messages.some(m => m.type === 'error' || m.type === 'issueNewTurn'), false);
});

test('large code trees and local snapshots are not truncated to the previous limits', () => {
    const text = '資料'.repeat(100000);
    const code = "const [value] = DIL.useState(resources.source.text); return DIL.h('text', {}, value);" + ' '.repeat(65537);
    const app = mount({code, resources:{source:{text}}});
    assert.equal(app.root.textContent, text);
    assert.equal(app.context.GenUIRuntime.getSnapshot().hooks[0], text);
    let ui = api.h('text', {}, 'Deep leaf');
    for (let i = 0; i < 64; i++) ui = api.h('col', {}, ui);
    const tree = mount({ui:api.h('col', {}, ui, ...Array.from({length:1024}, (_, i) => api.h('text', {}, String(i))))});
    assert.equal(tree.root.children[0].children[0].children.length, 1025);
    assert.ok(tree.root.textContent.includes('Deep leaf'));
    assert.equal(tree.messages.some(m => m.type === 'error'), false);
});

test('mobile layouts retain authored spacing and dimensions while preserving input updates', () => {
    const app = mount({state:{count:0}, ui:api.h('col', {gap:40,padding:24,height:900,minHeight:800,justify:'between'},
        api.h('row', {gap:24}, api.h('label', {}, '50円玉'), api.h('input', {inputType:'number',bind:'count'}), api.h('text', {}, '{{count}}枚')),
        api.h('spacer', {minSize:200}), api.h('Link', {title:'参照',url:'https://example.com'}))});
    const column = app.root.children[0].children[0];
    assert.equal(column.style.gap, '160px');
    assert.equal(column.style.padding, '96px');
    assert.equal(column.style.height, '900px');
    assert.equal(column.style.minHeight, '800px');
    assert.equal(column.style.justifyContent, 'space-between');
    assert.equal(column.children[1].style.flex, '1');
    assert.equal(column.children[1].style.minHeight, '200px');
    const input=app.root.querySelectorAll('input')[0];input.value='12';input.fire('input',true);app.flush();
    assert.ok(app.root.textContent.includes('12枚'));
    app.root.querySelectorAll('button')[0].fire('click',true);
    assert.equal(app.messages.find(m=>m.type==='openUrl').url,'https://example.com/');
});

test('desktop authored layout and mobile media or explicit scrolling sizes remain available', () => {
    const ui=api.h('col',{height:900,gap:24},api.h('box',{height:240,scrollable:true}),api.h('AsyncImage',{src:'https://example.com/image.png',height:180}));
    const desktop=mount({ui},1024).root.children[0].children[0];
    assert.equal(desktop.style.height,'900px');assert.equal(desktop.style.gap,'96px');
    const mobile=mount({ui}).root.children[0].children[0];
    assert.equal(mobile.children[0].style.height,'240px');
    assert.equal(mobile.children[1].style.height,'180px');
});

test('neutral interactive panels derive paired metrics from shared slider state', () => {
    const app=mount({title:'比較',code:"const [n,setN]=DIL.useState(4); return DIL.h('card',{},DIL.h('slider',{name:'規模',min:1,max:10,value:n,onChange:setN,marks:[{value:1,label:'小'},{value:10,label:'大'}]}),DIL.h('grid',{columns:2},DIL.h('card',{variant:'metric'},DIL.h('caption',{},'合計'),DIL.h('text',{},n*3)),DIL.h('card',{variant:'metric'},DIL.h('caption',{},'差分'),DIL.h('text',{},n-1))));"});
    assert.ok(app.root.textContent.includes('小大'));
    const slider=app.root.querySelectorAll('input')[0];
    assert.equal(slider.style['--range-progress'],'33.33333333333333%');
    slider.value='7';slider.fire('input',true);app.flush();
    assert.ok(app.root.textContent.includes('合計21'));
    assert.ok(app.root.textContent.includes('差分6'));
    assert.equal(app.messages.some(m=>m.type==='issueNewTurn'||m.type==='error'),false);
});

test('icons use bundled stroke geometry and preserve unknown-name fallback', () => {
    for(const name of ['arrow-down','refresh','cpu','layers','check']) {
        const app=mount({ui:api.h('icon',{name,size:28,color:'secondary'})});
        const svg=app.root.querySelectorAll('svg')[0];
        assert.equal(svg.attributes.viewBox,'0 0 24 24');
        assert.ok(JSON.stringify(svg.attributes).length > 0);
        assert.ok(svg.children.length > 0);
    }
    const unknown=mount({ui:api.h('icon',{name:'unknown'})});assert.equal(unknown.root.textContent,'');assert.ok(unknown.messages.some(message=>message.type==='warning' && message.message.includes('unknown')));
});

test('unchanged hook state in an effect does not schedule a render loop', () => {
    const app=mount({code:"const [n,setN]=DIL.useState(7); DIL.useEffect(()=>{setN(7);}); return DIL.h('text',{},String(n));"});
    app.flush();
    assert.equal(app.messages.filter(m=>m.type==='state').length,1);
    assert.equal(app.root.textContent,'7');
});

test('unchanged bound values and setState actions avoid redundant renders', () => {
    const app=mount({state:{n:7},ui:api.h('col',{},api.h('slider',{bind:'n'}),api.h('button',{label:'Same',onClick:{type:'setState',key:'n',value:7}}))});
    const slider=app.root.querySelectorAll('input')[0];slider.value='7';slider.fire('input',true);
    app.root.querySelectorAll('button')[0].fire('click',true);app.flush();
    assert.equal(app.messages.filter(m=>m.type==='state').length,1);
});

test('flow stages retain semantic variants, vector icons and nested decision branches', () => {
    const ui = api.h('card', {}, api.h('list', {connector:true,marker:'none'},
        api.h('list-item', {icon:'cpu',iconColor:'info',variant:'outline',label:'Compute',description:'Try a candidate'}),
        api.h('list-item', {variant:'decision',label:'Accepted?'},api.h('grid',{columns:2},
            api.h('card',{variant:'soft'},api.h('text',{},'Retry')),
            api.h('card',{variant:'success'},api.h('text',{},'Send'))))));
    const app = mount({ui});
    const stages = app.root.querySelectorAll('li');
    assert.equal(stages[0].dataset.variant, 'outline');
    assert.equal(stages[0].children[0].style.color, 'var(--dil-color-text-info)');
    assert.equal(stages[0].children[0].children[0].tagName, 'SVG');
    assert.equal(stages[0].children[1].textContent, 'Compute');
    assert.equal(stages[1].dataset.variant, 'decision');
    assert.equal(stages[1].children[1].style.gridTemplateColumns, 'repeat(2,minmax(0,1fr))');
    assert.equal(stages[1].children[1].children[1].dataset.variant, 'success');
    assert.equal(app.messages.some(m=>m.type==='error'),false);
});

test('actual flow fixture updates probability, clears stale samples and resets locally', () => {
    const source=fs.readFileSync(path.join(__dirname,'../YamabikoChat/App/GenUIRichDemoFixture.swift'),'utf8');
    const code=source.match(/static let flowCode = #"""\n([\s\S]*?)\n    """#/)[1];
    const app=mount({code});
    assert.equal(app.root.querySelectorAll('li').length,4);
    assert.ok(app.root.textContent.includes('6.25%'));
    assert.ok(app.root.textContent.includes('16回'));
    for(const icon of app.root.querySelectorAll('svg')) assert.equal(icon.attributes.viewBox,'0 0 24 24');
    app.root.querySelectorAll('button')[0].fire('click',true);app.flush();
    assert.ok(app.root.textContent.includes('今回の試行：')||app.root.textContent.includes('4096回で打ち切り'));
    const slider=app.root.querySelectorAll('input')[0];slider.value='8';slider.fire('input',true);app.flush();
    assert.ok(app.root.textContent.includes('0.39%'));
    assert.ok(app.root.textContent.includes('256回'));
    assert.equal(app.root.textContent.includes('今回の試行：'),false);
    app.root.querySelectorAll('button')[1].fire('click',true);app.flush();
    assert.ok(app.root.textContent.includes('16回'));
    assert.equal(app.messages.some(m=>m.type==='issueNewTurn'||m.type==='error'),false);
});

test('decorative button icons do not pollute the accessible operation name', () => {
    const app=mount({ui:api.h('button',{},api.h('icon',{name:'refresh'}),'Reset')});
    const button=app.root.querySelectorAll('button')[0];
    assert.equal(button.children[0].attributes['aria-hidden'],'true');
    assert.equal(button.textContent,'Reset');
});

test('source element vocabulary and widget aliases stay aligned with native catalog', () => {
    const source = fs.readFileSync(path.join(__dirname,'../YamabikoChat/Features/Tools/GenUI/GenUIRichDocument.swift'),'utf8');
    const recovered = fs.readFileSync(path.join(__dirname,'../YamabikoChat/Features/Tools/GenUI/GenUIReferenceCatalog.swift'),'utf8');
    const native = [...(source + recovered).matchAll(/"([^"\n]+)": \[/g)].map(match=>match[1]);
    const aliases = [...source.matchAll(/^        "([^"\n]+)": "([^"\n]+)",$/gm)].map(match=>match[1]);
    const svg = ['g','path','circle','ellipse','rect','line','polyline','polygon','defs','linearGradient','radialGradient','stop','clipPath'];
    assert.deepEqual([...api.componentNames].sort(), [...new Set([...native,...aliases])].filter(name=>!svg.includes(name)).sort());
    for(const name of ['markdown','text-only-markdown','flashcard-flip','loading','loading-block','loading-indicator','pulse-indicator','shimmer-text','animate','animate-group','animate-item','transition','tooltip','celebration','Each','Scope','Show','Show.Else'])assert.ok(api.componentNames.includes(name),name);
});

test('intrinsics bind scoped objects, repeat keyed items and switch conditional branches locally', () => {
    const app = mount({state:{ready:false},ui:api.h('col',{},
        api.h('Scope',{values:{heading:'Items'}},api.h('text',{},'{{heading}}')),
        api.h('Each',{items:[{id:'a',name:'Alpha'},{id:'b',name:'Beta'}],as:'entry',keyField:'id'},api.h('text',{},'{{entry.name}}')),
        api.h('Show',{when:'{{ready}}'},api.h('text',{},'Ready'),api.h('Show.Else',{},api.h('text',{},'Waiting'))),
        api.h('button',{label:'Start',onClick:{type:'setState',key:'ready',value:true}}))});
    assert.ok(app.root.textContent.includes('ItemsAlphaBetaWaiting'));
    app.root.querySelectorAll('button')[0].fire('click',true);app.flush();
    assert.ok(app.root.textContent.includes('Ready'));assert.equal(app.root.textContent.includes('Waiting'),false);
    assert.equal(app.messages.some(message=>message.type==='issueNewTurn'),false);
});

test('widget aliases resolve through element aliases including pie and image aliases', () => {
    const app=mount({ui:api.h('Col',{},api.h('PieChart',{data:[{name:'A',value:2},{name:'B',value:3}]}),api.h('SearchImage',{src:'https://example.com/image.png'}))});
    assert.equal(app.root.querySelectorAll('svg').length,1);
    assert.equal(app.root.querySelectorAll('img')[0].src,'https://example.com/image.png');
    assert.equal(app.messages.some(message=>message.type==='warning'),false);
});

test('flashcard retains both faces and changes accessibility and saved flip state', () => {
    const app=mount({ui:api.h('flashcard-flip',{front:api.h('text',{},'Question'),back:api.h('text',{},'Answer')})});
    const card=()=>app.root.querySelectorAll('div').find(el=>el.className==='genui-flashcard-flip');
    assert.ok(card().attributes['aria-label'].includes('Question'));
    assert.equal(card().children[0].children[1].attributes['aria-hidden'],'true');
    card().fire('click',true);app.flush();
    assert.equal(card().attributes['aria-pressed'],'true');
    assert.equal(card().children[0].children[0].attributes['aria-hidden'],'true');
    assert.equal(card().children[0].children[1].attributes['aria-hidden'],'false');
    app.context.GenUIRuntime.reset();app.flush();assert.equal(card().attributes['aria-pressed'],'false');
});

test('Markdown creates semantic nodes and treats HTML and unsafe links as data', () => {
    const app=mount({ui:api.h('markdown',{},'# Heading\n**Strong** and `code`\n- First\n- Second\n<script>alert(1)</script>\n[Safe](https://example.com) [Unsafe](javascript:evil)')});
    assert.equal(app.root.querySelectorAll('h1').length,1);
    assert.equal(app.root.querySelectorAll('strong').length,1);
    assert.equal(app.root.querySelectorAll('li').length,2);
    assert.equal(app.root.querySelectorAll('script').length,0);
    assert.ok(app.root.textContent.includes('<script>alert(1)</script>'));
    assert.equal(app.root.querySelectorAll('button').length,1);
    app.root.querySelectorAll('button')[0].fire('click',true);
    assert.equal(app.messages.find(message=>message.type==='openUrl').url,'https://example.com/');
});

test('subtree error boundaries preserve siblings and attach diagnostic paths', () => {
    const app=mount({code:"const broken=()=>{throw Error('failed child')};return DIL.h('col',{},DIL.h('text',{},'Before'),DIL.h(broken),DIL.h('text',{},'After'));"});
    assert.ok(app.root.textContent.includes('Before'));assert.ok(app.root.textContent.includes('After'));
    assert.ok(app.root.textContent.includes('failed child'));
    assert.equal(app.messages.find(message=>message.type==='warning').path,'0.1');
    assert.equal(app.messages.some(message=>message.type==='error'),false);
});

test('JSON patches are atomic, support escaped pointers and reject prototype writes', () => {
    const original={ui:{type:'text',children:['A']},state:{'a/b':{'c~d':1}}};
    const patched=api.applyJSONPatch(original,[{op:'append',path:'/ui/children/0',value:'B'},{op:'replace',path:'/state/a~1b/c~0d',value:2},{op:'add',path:'/ui/children/-',value:'C'}]);
    assert.equal(patched.ui.children[0],'AB');assert.equal(patched.state['a/b']['c~d'],2);
    assert.equal(original.ui.children[0],'A');
    assert.throws(()=>api.applyJSONPatch(original,[{op:'replace',path:'/ui/children/0',value:'new'},{op:'remove',path:'/missing'}]));
    assert.equal(original.ui.children[0],'A');
    for(const pointer of ['/__proto__/polluted','/ui/children/02','/ui/children/99','/state/a~2b'])assert.throws(()=>api.applyJSONPatch(original,[{op:'add',path:pointer,value:'bad'}]));
    const app=mount({ui:original.ui});app.context.GenUIRuntime.applyPatch([{op:'append',path:'/ui/children/0',value:'B'}]);app.flush();assert.equal(app.root.textContent,'AB');
});

test('chart flags, missing samples and explicit Recharts nodes preserve their contracts', () => {
    const app=mount({ui:api.h('chart',{content:{type:'LineChart',props:{data:[{x:'A',n:1},{x:'B',n:null},{x:'C',n:3}]},children:[{type:'XAxis',props:{dataKey:'x'}},{type:'Line',props:{dataKey:'n',name:'Values'}}]}})});
    assert.equal(app.root.querySelectorAll('polyline').length,2,'missing point splits the line');
    assert.equal(app.root.querySelectorAll('line').length,0,'omitted grid is hidden');
    assert.equal(app.root.querySelectorAll('circle').length,2);
    const mark=app.root.querySelectorAll('circle')[0];assert.equal(mark.attributes.tabindex,'0');mark.fire('click',true);
    assert.ok(app.root.textContent.includes('A · Values: 1'));
    for(const bad of [-1,null,'unknown']){
        const invalid=mount({ui:api.h('chart',{alt:'Supplied alternative',content:{chartType:'pie',data:[{name:'A',value:bad},{name:'B',value:2}]}})});
        assert.equal(invalid.root.textContent,'Supplied alternative');
        assert.equal(invalid.root.querySelectorAll('svg').length,0);
    }
});

test('typed numeric select options remain numeric after editing',()=>{
    const app=mount({state:{n:1},ui:api.h('col',{},api.h('select',{bind:'n',options:[{label:'One',value:1},{label:'Two',value:2}]}),api.h('text',{},'{{n}}'))});
    const select=app.root.querySelectorAll('select')[0];select.value='2';select.fire('change',true);app.flush();
    assert.equal(app.context.GenUIRuntime.getSnapshot().bindings.n,2);
});

test('reference composition keeps controls, chart and learning card on shared state',()=>{
    const source=fs.readFileSync(path.join(__dirname,'../YamabikoChat/App/GenUIReferenceFixture.swift'),'utf8');
    const code=source.match(/static let code = #"""\n([\s\S]*?)\n    """#/)[1];
    const app=mount({code});assert.ok(app.root.textContent.includes('125,000円'));
    const sliders=app.root.querySelectorAll('input').filter(input=>input.type==='range');
    sliders[0].value='400000';sliders[0].fire('input',true);app.flush();assert.ok(app.root.textContent.includes('205,000円'));
    const radios=app.root.querySelectorAll('input').filter(input=>input.type==='radio');radios[1].fire('change',true);app.flush();
    assert.ok(app.root.textContent.includes('貯蓄に回せる金額は？'));
    const flip=app.root.querySelectorAll('div').find(element=>element.className==='genui-flashcard-flip');flip.fire('click',true);app.flush();assert.ok(app.root.textContent.includes('収入 − 住居費 − その他の支出'));
    assert.equal(app.messages.some(message=>['error','warning','issueNewTurn'].includes(message.type)),false);
});

test('keyed hook snapshots restore the correct component after reorder',()=>{
    const code=`
      const Item=({id})=>{const [n,setN]=DIL.useState(0);return DIL.h('button',{label:id+' '+n,onClick:()=>setN(n+1)});};
      return DIL.h('col',{},...state.ids.map(id=>DIL.h(Item,{key:id,id})));
    `;
    const first=mount({code,state:{ids:['a','b']}});first.root.querySelectorAll('button')[0].fire('click',true);first.flush();
    const snapshot=JSON.parse(JSON.stringify(first.context.GenUIRuntime.getSnapshot()));
    snapshot.bindings.ids=['b','a'];
    const restored=mount({code,state:{ids:['a','b']}},320,snapshot);
    assert.equal(restored.root.querySelectorAll('button')[0].textContent,'b 0');
    assert.equal(restored.root.querySelectorAll('button')[1].textContent,'a 1');
});


test('all 283 recovered component sources initialize and render their pending state', () => {
    const names = Object.keys(global.__GENUI_REFERENCE_COMPONENT_FACTORIES__);
    assert.equal(names.length, 283);
    for (const name of names) {
        const app = mount({ui:api.h(name,{})});
        const problems = app.messages.filter(message => message.type === 'error' || message.type === 'warning');
        assert.deepEqual(problems, [], name);
    }
});

test('original DigitalTimerWidget renders supplied state and supports pause and reset', () => {
    const app=mount({ui:api.h('DigitalTimerWidget',{__state:{start_time:90,auto_start:false,done_label:'Done'}})});
    app.flush();
    assert.ok(app.root.textContent.includes('1:30'));
    const play=app.root.querySelectorAll('button')[0];
    play.fire('click',true);app.flush();
    assert.ok(app.root.textContent.includes('⏸︎'));
    app.root.querySelectorAll('button')[0].fire('click',true);app.flush();
    assert.ok(app.root.textContent.includes('▶'));
    const snapshot=app.context.GenUIRuntime.getSnapshot();
    const restored=mount({ui:api.h('DigitalTimerWidget',{__state:{start_time:90,auto_start:false,done_label:'Done'}})},320,snapshot);
    restored.flush();assert.ok(restored.root.textContent.includes('1:30'));
    assert.equal(app.messages.some(message => message.type === 'warning'),false);
});

test('original spacing, palettes, typography and SVGs replace mobile caps and fallback glyphs', () => {
    const app=mount({ui:api.h('col',{gap:20,padding:{x:8,y:2},height:420,justify:'between'},api.h('title',{size:'2xl'},'Heading'),api.h('icon',{name:'reload'}))});
    const col=app.root.children[0].children[0];
    assert.equal(col.style.gap,'80px');assert.equal(col.style.paddingLeft,'32px');
    assert.equal(col.style.height,'420px');assert.equal(col.style.justifyContent,'space-between');
    assert.equal(col.children[0].style.fontSize,'28px');
    assert.equal(col.children[1].children[0].tagName,'SVG');
    assert.equal(col.children[1].textContent,'');
});


test('original currency converter keeps decimal arithmetic and bidirectional input behavior', () => {
    const app=mount({ui:api.h('CurrencyConverterWidget',{__state:{base_amount:100,exchange_rate:150,from_currency:'USD',to_currency:'JPY',from_currency_display_name:'US Dollar',to_currency_display_name:'Japanese Yen',from_currency_symbol:'$',to_currency_symbol:'¥'}})});
    app.flush();const input=app.root.querySelectorAll('input');
    assert.equal(input[1].value,'15,000');
    input[0].value='0.3';input[0].fire('input',true);app.flush();
    assert.equal(app.root.querySelectorAll('input')[1].value,'45');
    const yen=app.root.querySelectorAll('input')[1];yen.value='300';yen.fire('input',true);app.flush();
    assert.equal(app.root.querySelectorAll('input')[0].value,'2.00');
    assert.equal(app.messages.some(message=>message.type==='warning'||message.type==='error'),false);
});

test('original checklist expands overflow and preserves checked items', () => {
    const app=mount({ui:api.h('ChecklistWidget',{__state:{sections:[{name:'Tasks',items:['A','B','C','D','E']}]}})});
    assert.equal(app.root.querySelectorAll('input').length,4);
    const check=app.root.querySelectorAll('input')[1];check.checked=true;check.fire('change',true);app.flush();
    app.root.querySelectorAll('button')[0].fire('click',true);app.flush();
    assert.equal(app.root.querySelectorAll('input').length,5);
    assert.equal(app.root.querySelectorAll('input')[1].checked,true);
});

test('recovered donut chart contract uses row colors and supplied numeric series',()=>{
    const app=mount({ui:api.h('pie-chart',{size:244,data:[{label:'A',amount:3,fill:'#123456'},{label:'B',amount:7,fill:'#654321'}],series:[{dataKey:'amount'}],xAxis:'label',innerRadius:'49%'})});
    assert.equal(app.messages.some(message=>message.type==='warning'||message.type==='error'),false);
    const paths=app.root.querySelectorAll('path');assert.equal(paths.length,2);
    assert.equal(paths[0].attributes.fill,'#123456');
    assert.equal((paths[0].attributes.d.match(/ A/g)||[]).length,2);
});


test('incremental document updates preserve edited bindings and canonical widget hook state',()=>{
    const original={state:{n:1},ui:api.h('input',{bind:'n',inputType:'number'})};
    const app=mount(original);const input=app.root.querySelectorAll('input')[0];input.value='7';input.fire('input',true);app.flush();
    app.context.GenUIRuntime.updateDocument({state:{n:2,extra:9},ui:api.h('col',{},api.h('input',{bind:'n',inputType:'number'}),api.h('text',{},'{{extra}}'))});
    app.flush();assert.equal(app.root.querySelectorAll('input')[0].value,7);assert.ok(app.root.textContent.includes('9'));
    assert.equal(app.context.GenUIRuntime.getSnapshot().bindings.n,7);
});

test('recovered intrinsic aliases use of/itemName/indexName and default Show.when',()=>{
    const app=mount({ui:api.h('col',{},api.h('Show',{},api.h('text',{},'Shown')),api.h('Each',{of:['A','B'],itemName:'letter',indexName:'position'},api.h('text',{},'{{position}}:{{letter}}')))});
    assert.ok(app.root.textContent.includes('Shown'));assert.ok(app.root.textContent.includes('0:A1:B'));
});


test('canonical dark card sets a scoped foreground and tint instead of inheriting light text',()=>{
    const app=mount({ui:api.h('DigitalTimerWidget',{__state:{start_time:90,auto_start:false,done_label:'Done'}})});
    const card=app.root.querySelectorAll('section').find(element=>element.className==='genui-card') || app.root.querySelectorAll('div').find(element=>element.className==='genui-card');
    assert.equal(card.dataset.theme,'dark');assert.equal(card.style.color,'var(--dil-primary)');
});


test('disableAutoSpacing retains explicit source gaps',()=>{
    const app=mount({ui:api.h('col',{gap:4,disableAutoSpacing:true},'A','B')});
    assert.equal(app.root.querySelectorAll('div').find(element=>element.className==='genui-col').style.gap,'16px');
});

test('original prefill and mail draft actions require a trusted click without starting a model turn', () => {
    const app = mount({code: `return DIL.h('col', {},
      DIL.h('button', {label:'Draft', onClick:()=>GenUI.dispatchAction({handler:'client',type:'prefill_composer',payload:{prompt:'下書き'}})}),
      DIL.h('button', {label:'Mail', onClick:()=>GenUI.dispatchAction({type:'email.mailto',payload:{email:{to:'example@example.com',subject:'Subject',body:'Draft'}}})}));`});
    const buttons = app.root.querySelectorAll('button');
    buttons.forEach(button => button.fire('click'));
    assert.equal(app.messages.some(message => ['prefillComposer','composeEmail','issueNewTurn'].includes(message.type)), false);
    buttons.forEach(button => button.fire('click', true));
    assert.equal(app.messages.find(message => message.type === 'prefillComposer').text, '下書き');
    assert.equal(app.messages.find(message => message.type === 'composeEmail').args.email.body, 'Draft');
    assert.equal(app.messages.some(message => message.type === 'issueNewTurn'), false);
});
