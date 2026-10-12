/* Run with node --test ios/GenUIRuntimeTests/runtime.test.js; no npm install. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const runtimePath = path.join(__dirname, '../YamabikoChat/App/Resources/genui/runtime.js');
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

function mount(config) {
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
    const context = {document, __GENUI_DOCUMENT__:config, innerWidth:320, URL,
        webkit:{messageHandlers:{genui:{postMessage(value) {messages.push(value);}}}},
        addEventListener() {}, requestAnimationFrame:fn => fn(),
        ResizeObserver:class {observe() {}}, queueMicrotask:fn => tasks.push(fn),
        setTimeout:fn => tasks.push(fn), clearTimeout() {}};
    context.window = context;
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
    assert.deepEqual(snapshot, {bindings:{}, hooks:[null]});
    assert.equal(app.root.textContent, 'null');
});

test('local binding updates shared text without submitting a model turn', () => {
    const app = mount({state:{amount:5}, ui:api.h('col', {}, api.h('slider', {bind:'amount', min:0, max:100}), api.h('text', {}, 'Amount {{amount}}'))});
    const slider = app.root.querySelectorAll('input')[0];
    slider.value = '25'; slider.fire('input', true); app.flush();
    assert.ok(app.root.textContent.includes('Amount 25'));
    assert.equal(app.messages.some(m => m.type === 'issueNewTurn'), false);
});

test('maps only request native presentation following a trusted click', () => {
    const props = {title:'Tokyo', points:[{lat:35.6, lng:139.7, name:'Stop'}]};
    const app = mount({ui:api.h('MapWidgetV2', props)});
    assert.equal(app.messages.some(m => ['openMap','map'].includes(m.type)), false);
    const button = app.root.querySelectorAll('button')[0];
    button.fire('click');
    assert.equal(app.messages.some(m => m.type === 'openMap'), false);
    button.fire('click', true);
    const message = app.messages.find(m => m.type === 'openMap');
    assert.deepEqual(JSON.parse(JSON.stringify(message.props.points)), props.points);
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
