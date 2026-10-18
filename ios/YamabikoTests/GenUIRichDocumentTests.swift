import Combine
import UIKit
import XCTest
import WebKit
@testable import YamabikoChat

final class GenUIRichDocumentTests: XCTestCase {
    @MainActor
    func testLottieUpdatesStayMountedAndUseCurrentCallbacks() async throws {
        let result = try await runRichRuntimeScript(#"""
        const mounts=[], destroyed=[], speeds=[];
        let complete;
        window.lottie={loadAnimation(options){
            const version=options.animationData.version;
            mounts.push(options.container.isConnected);
            const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
            svg.setAttribute('data-version',version); options.container.append(svg);
            return {destroy(){destroyed.push(version);svg.remove();},
                addEventListener(type,callback){if(type==='complete')complete=callback;},
                setSpeed(value){speeds.push(value);}};
        }};
        await show(`const [n,setN]=DIL.useState(0),[speed,setSpeed]=DIL.useState(1),[done,setDone]=DIL.useState(-1);
            return DIL.h('col',{},DIL.h('lottie',{data:{w:100,h:100,version:n},speed,onComplete:()=>setDone(speed)}),
                DIL.h('button',{label:'Change',onClick:()=>setN(n+1)}),
                DIL.h('button',{label:'Speed',onClick:()=>setSpeed(speed+1)}),DIL.h('text',{},'done='+done));`);
        for(let index=0;index<2;index++){document.querySelectorAll('button')[0].click();await wait();}
        document.querySelectorAll('button')[1].click();await wait();
        complete();await wait();
        return {mounts,destroyed,speed:speeds.at(-1),visible:document.querySelector('.genui-lottie svg')?.getAttribute('data-version'),text:document.getElementById('root').textContent};
        """#)
        XCTAssertEqual(result["mounts"] as? [Bool], [true, true, true])
        XCTAssertEqual(result["destroyed"] as? [Int], [0, 1])
        XCTAssertEqual(result["visible"] as? String, "2")
        XCTAssertEqual(result["speed"] as? Int, 2)
        XCTAssertTrue((result["text"] as? String)?.contains("done=2") == true)
    }

    @MainActor
    func testAnimationChangesRestartOnTheLiveElementAndCancelOnRemoval() async throws {
        let result = try await runRichRuntimeScript(#"""
        const mounts=[],ends=[];let cancellations=0;
        Element.prototype.animate=function(frames){mounts.push(this.isConnected);ends.push(frames[1].opacity);return{cancel(){cancellations++;}};};
        await show(`const [n,setN]=DIL.useState(0),[count,setCount]=DIL.useState(0),[hidden,setHidden]=DIL.useState(false);
            return DIL.h('col',{},hidden?DIL.h('text',{},'Removed'):DIL.h('animate',{initial:{opacity:0},enter:{opacity:n===0?0.5:1}},DIL.h('text',{},'Animation')),
                DIL.h('button',{label:'Change',onClick:()=>setN(n+1)}),
                DIL.h('button',{label:'Counter '+count,onClick:()=>setCount(count+1)}),
                DIL.h('button',{label:'Remove',onClick:()=>setHidden(true)}));`);
        document.querySelectorAll('button')[0].click();await wait();
        document.querySelectorAll('button')[1].click();await wait();
        const afterCounter=mounts.length;
        document.querySelectorAll('button')[2].click();await wait();
        return {mounts,ends,cancellations,afterCounter};
        """#)
        XCTAssertEqual(result["mounts"] as? [Bool], [true, true])
        XCTAssertEqual(result["ends"] as? [Double], [0.5, 1])
        XCTAssertEqual(result["afterCounter"] as? Int, 2)
        XCTAssertEqual(result["cancellations"] as? Int, 2)
    }

    @MainActor
    func testAnimationEnabledAfterInitialRenderUsesTheLiveElement() async throws {
        let result = try await runRichRuntimeScript(#"""
        const mounts=[];
        Element.prototype.animate=function(){mounts.push(this.isConnected);return{cancel(){}};};
        await show(`const [enabled,setEnabled]=DIL.useState(false);return DIL.h('col',{},
            DIL.h('animate',{preventInitialTransition:!enabled},DIL.h('text',{},'Animation')),
            DIL.h('button',{label:'Enable',onClick:()=>setEnabled(true)}));`);
        const initial=mounts.length;
        document.querySelector('button').click();await wait();
        return {initial,mounts};
        """#)
        XCTAssertEqual(result["initial"] as? Int, 0)
        XCTAssertEqual(result["mounts"] as? [Bool], [true])
    }

    @MainActor
    func testFlashcardSwipeSurvivesProgressUpdatesAndCancellation() async throws {
        let result = try await runRichRuntimeScript(#"""
        await show(`const [progress,setProgress]=DIL.useState(0),[swipes,setSwipes]=DIL.useState(0);
            return DIL.h('col',{},DIL.h('flashcard-flip',{front:DIL.h('text',{},'Front'),back:DIL.h('text',{},'Back'),
                onSwipeProgress:setProgress,onSwipeRight:()=>setSwipes(n=>n+1)}),DIL.h('text',{},'swipes='+swipes+';progress='+progress));`);
        const card=document.querySelector('.genui-flashcard-flip');card.setPointerCapture=()=>{};
        const send=(type,x,id=1)=>card.dispatchEvent(new PointerEvent(type,{bubbles:true,clientX:x,pointerId:id}));
        send('pointerdown',0);send('pointermove',100);await wait();
        send('pointermove',200);await wait();send('pointerup',200);await wait();
        const completed=document.getElementById('root').textContent;
        send('pointerdown',0);send('pointermove',100);await wait();send('pointercancel',100);await wait();
        send('pointerup',200);await wait();
        return {same:card===document.querySelector('.genui-flashcard-flip'),completed,cancelled:document.getElementById('root').textContent};
        """#)
        XCTAssertEqual(result["same"] as? Bool, true)
        XCTAssertTrue((result["completed"] as? String)?.contains("swipes=1;progress=0") == true)
        XCTAssertTrue((result["cancelled"] as? String)?.contains("swipes=1;progress=0") == true)
    }

    @MainActor
    func testMathPreservesUnchangedOutputAndSerializesTheLatestFormula() async throws {
        let result = try await runRichRuntimeScript(#"""
        const releases=[],rawSources=[];let active=0,maxActive=0,clears=0;
        window.MathJax={typesetClear(){clears++;},typesetPromise(targets){
            const sources=targets.map(target=>target.textContent);rawSources.push(sources[0]);
            active++;maxActive=Math.max(maxActive,active);
            return new Promise(resolve=>releases.push(()=>{
                targets.forEach((target,index)=>{const span=document.createElement('span');span.className='typeset-result';span.textContent=sources[index];target.replaceChildren(span);});
                active--;resolve();
            }));
        }};
        await show(`const [n,setN]=DIL.useState(0),[count,setCount]=DIL.useState(0);return DIL.h('col',{},
            DIL.h('math',{value:'x^'+n}),DIL.h('button',{label:'Counter '+count,onClick:()=>setCount(count+1)}),
            DIL.h('button',{label:'Formula',onClick:()=>setN(n+1)}));`);
        releases.shift()();await wait();
        const formula=document.querySelector('.typeset-result');
        document.querySelectorAll('button')[0].click();await wait();
        const same=formula===document.querySelector('.typeset-result'),afterCounter=rawSources.length;
        document.querySelectorAll('button')[1].click();await wait();
        document.querySelectorAll('button')[1].click();await wait();
        const whilePending=rawSources.length;
        releases.shift()();await wait();releases.shift()();await wait();
        return {same,afterCounter,whilePending,rawSources,maxActive,clears,final:document.querySelector('.genui-math').textContent};
        """#)
        XCTAssertEqual(result["same"] as? Bool, true)
        XCTAssertEqual(result["afterCounter"] as? Int, 1)
        XCTAssertEqual(result["whilePending"] as? Int, 2)
        XCTAssertEqual(result["maxActive"] as? Int, 1)
        let sources = try XCTUnwrap(result["rawSources"] as? [String])
        XCTAssertEqual(sources.count, 3)
        for (index, source) in sources.enumerated() { XCTAssertTrue(source.contains("x^\(index)")) }
        XCTAssertTrue((result["final"] as? String)?.contains("x^2") == true)
        XCTAssertGreaterThanOrEqual(result["clears"] as? Int ?? 0, 2)
    }

    @MainActor
    func testBundledMathJaxKeepsTheFormulaMountedAcrossUnrelatedUpdates() async throws {
        let result = try await runRichRuntimeScript(#"""
        await window.MathJax.startup.promise;
        await show(`const [n,setN]=DIL.useState(0);return DIL.h('col',{},DIL.h('math',{value:'x^2'}),
            DIL.h('button',{label:'Counter '+n,onClick:()=>setN(n+1)}));`);
        for(let attempt=0;attempt<100 && !document.querySelector('mjx-container');attempt++)await wait(50);
        const formula=document.querySelector('mjx-container');
        document.querySelector('button').click();await wait(200);
        return {rendered:!!formula,same:formula===document.querySelector('mjx-container'),connected:formula?.isConnected};
        """#, withMathJax: true)
        XCTAssertEqual(result["rendered"] as? Bool, true)
        XCTAssertEqual(result["same"] as? Bool, true)
        XCTAssertEqual(result["connected"] as? Bool, true)
    }

    @MainActor
    func testBundledLottieReplacesItsVisibleSVGWhenAnimationDataChanges() async throws {
        let result = try await runRichRuntimeScript(#"""
        await show(`const [n,setN]=DIL.useState(0);return DIL.h('col',{},
            DIL.h('lottie',{data:{v:'5.7.4',fr:30,ip:0,op:30,w:100,h:100,nm:'Animation '+n,ddd:0,assets:[],layers:[]}}),
            DIL.h('button',{label:'Change',onClick:()=>setN(n+1)}));`);
        for(let attempt=0;attempt<100 && !document.querySelector('.genui-lottie svg');attempt++)await wait(50);
        const first=document.querySelector('.genui-lottie svg');
        document.querySelector('button').click();await wait(100);
        const second=document.querySelector('.genui-lottie svg');
        return {initial:!!first,count:document.querySelectorAll('.genui-lottie svg').length,changed:first!==second,connected:second?.isConnected};
        """#)
        XCTAssertEqual(result["initial"] as? Bool, true)
        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(result["changed"] as? Bool, true)
        XCTAssertEqual(result["connected"] as? Bool, true)
    }

    @MainActor
    func testCPUComparisonChartRendersThroughNativeQuickJSInWebKit() async throws {
        let result = try await runRichRuntimeScript(#"""
        const originalPrompt=window.prompt;
        const nativeResponses=[];
        window.prompt=(message)=>{
            const response=originalPrompt(message);
            if(message.startsWith('__genuiChart:'))nativeResponses.push(JSON.parse(response||'{}'));
            return response;
        };
        // Payload from the reported diagnostic: named numeric columns, no series/xKey.
        window.GenUIRuntime.updateDocument({title:'CPU比較',ui:{type:'chart',props:{
            chartType:'bar',height:280,showLegend:true,showValues:true,
            alt:'Cinebench R23のシングルコアとマルチコアの概算比較',
            content:{chartType:'bar',data:[
                {CPU:'Core i5-12450H','Single-core':1600,'Multi-core':9000},
                {CPU:'Apple M2','Single-core':1600,'Multi-core':8500}
            ]}
        }}});
        await wait(100);
        const svg=document.querySelector('#root svg[role="img"]');
        return {svgCount:document.querySelectorAll('#root svg[role="img"]').length,
            labels:svg?.textContent||'',marks:svg?.querySelectorAll('rect,path').length||0,
            unavailable:document.querySelectorAll('.genui-unavailable').length,
            nativeSVG:nativeResponses.some(response=>typeof response.svg==='string'),
            nativeErrors:nativeResponses.filter(response=>response.error).map(response=>response.error)};
        """#, withNativeCharts: true)
        XCTAssertEqual(result["svgCount"] as? Int, 1)
        XCTAssertEqual(result["unavailable"] as? Int, 0)
        XCTAssertEqual(result["nativeSVG"] as? Bool, true)
        XCTAssertEqual(result["nativeErrors"] as? [String], [])
        XCTAssertGreaterThanOrEqual(result["marks"] as? Int ?? 0, 4)
        let labels = try XCTUnwrap(result["labels"] as? String)
        for label in ["Core i5-12450H", "Apple M2", "Single-core", "Multi-core"] {
            XCTAssertTrue(labels.contains(label), labels)
        }
    }

    @MainActor
    func testAllChartTypesRenderInWebKitInBothThemes() async throws {
        let result = try await runRichRuntimeScript(#"""
        const originalPrompt=window.prompt,nativeCalls=[];
        window.prompt=(message)=>{
            const response=originalPrompt(message);
            if(message.startsWith('__genuiChart:'))nativeCalls.push({
                request:JSON.parse(message.slice('__genuiChart:'.length)),response:JSON.parse(response||'{}')
            });
            return response;
        };
        const cases=[];
        for(const chartType of ['bar','line','area','scatter','pie']){
            for(const schema of ['conventional','inferred','explicit']){
                const x=chartType==='scatter'?[0,1,100]:['A','B','C'];
                const data=x.map((label,index)=>schema==='conventional'
                    ?{x:label,value:[3,5,4][index]}
                    :{category:label,score:[3,5,4][index]});
                const content={chartType,data};
                if(schema==='explicit')Object.assign(content,{xKey:'category',nameKey:'category',
                    series:[{dataKey:'score',label:'Score',color:'#123456'}]});
                const props={content};
                // Numeric scatter coordinates require an explicit axis key.
                if(chartType==='scatter'&&schema==='inferred')props.xAxis='category';
                cases.push({id:chartType+'/'+schema,ui:{type:'Chart',props},chartType,
                    dataKey:schema==='conventional'?'value':'score'});
            }
        }
        cases.push({id:'donut/alias',chartType:'pie',dataKey:'amount',ui:{type:'pie-chart',props:{
            size:244,innerRadius:'49%',xAxis:'label',series:[{dataKey:'amount'}],
            data:[{label:'A',amount:3,fill:'#123456'},{label:'B',amount:7,fill:'#654321'}]
        }}});
        const results=[];
        for(const theme of ['light','dark']){
            window.GenUIRuntime.setTheme(theme);
            for(const item of cases){
                const start=nativeCalls.length;
                window.GenUIRuntime.updateDocument({title:item.id,ui:item.ui});
                await wait(60);
                const svg=document.querySelector('#root svg[role="img"]'),calls=nativeCalls.slice(start);
                const circles=Array.from(svg?.querySelectorAll('circle')||[]);
                const xs=circles.map(circle=>Number(circle.getAttribute('cx')));
                results.push({id:theme+'/'+item.id,
                    svg:!!svg,marks:svg?.querySelectorAll('rect,path,circle,polyline,polygon').length||0,
                    unavailable:document.querySelectorAll('.genui-unavailable').length,
                    invalidGeometry:/NaN|Infinity/.test(svg?.outerHTML||''),
                    renderer:item.chartType==='scatter'?calls.length===0:
                        calls.length>0&&calls.every(call=>typeof call.response.svg==='string'&&!call.response.error),
                    contract:calls.every(call=>call.request.viewModel.theme===theme&&
                        call.request.viewModel.series.length===1&&call.request.viewModel.series[0].dataKey===item.dataKey),
                    scatterSpacing:item.chartType!=='scatter'||(xs.length===3&&xs[1]-xs[0]<(xs[2]-xs[1])/10),
                    typeGeometry:item.chartType==='bar'?svg?.querySelectorAll('rect').length===3:
                        ['line','area'].includes(item.chartType)?svg?.querySelectorAll('path').length>=(item.chartType==='area'?2:1)&&svg?.querySelectorAll('rect').length===0:
                        item.chartType==='pie'?svg?.querySelectorAll('path').length>=2:true,
                    rowColors:item.id!=='donut/alias'||['#123456','#654321'].every(color=>svg?.outerHTML.includes(color))
                });
            }
        }
        return {results};
        """#, withNativeCharts: true)
        let cases = try XCTUnwrap(result["results"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 32)
        for item in cases {
            let name = try XCTUnwrap(item["id"] as? String)
            for key in ["svg", "renderer", "contract", "scatterSpacing", "rowColors", "typeGeometry"] {
                XCTAssertEqual(item[key] as? Bool, true, "\(name): \(key)")
            }
            XCTAssertEqual(item["unavailable"] as? Int, 0, name)
            XCTAssertEqual(item["invalidGeometry"] as? Bool, false, name)
            XCTAssertGreaterThan(item["marks"] as? Int ?? 0, 0, name)
        }
    }

    @MainActor
    func testChartMissingSamplesNegativeBarsAndInvalidPiesInWebKit() async throws {
        let result = try await runRichRuntimeScript(#"""
        const originalPrompt=window.prompt;let nativeCalls=0;
        window.prompt=(message)=>{if(message.startsWith('__genuiChart:'))nativeCalls++;return originalPrompt(message);};
        const results=[];
        for(const theme of ['light','dark']){
            window.GenUIRuntime.setTheme(theme);
            for(const chartType of ['bar','line','area']){
                const start=nativeCalls;
                const data=chartType==='bar'?[{x:'A',value:-3},{x:'B',value:5}]:
                    [{x:'A',value:1},{x:'B',value:null},{x:'C',value:3}];
                window.GenUIRuntime.updateDocument({title:chartType,ui:{type:'Chart',props:{content:{chartType,data}}}});
                await wait(60);
                const svg=document.querySelector('#root svg[role="img"]');
                const bars=Array.from(svg?.querySelectorAll('rect')||[]);
                const valid=chartType==='bar'?nativeCalls>start&&bars.length===2&&
                    bars.every(bar=>Number(bar.getAttribute('height'))>0)&&Number(bars[0].getAttribute('y'))>Number(bars[1].getAttribute('y')):
                    nativeCalls===start&&svg?.querySelectorAll('polyline').length===2&&
                    svg?.querySelectorAll('circle').length===2&&
                    (chartType!=='area'||svg?.querySelectorAll('polygon').length===2)&&
                    document.querySelectorAll('table td')[1]?.textContent==='—';
                results.push({id:theme+'/'+chartType,valid:!!valid});
            }
            for(const [index,values] of [[-1,2],[null,2],['unknown',2],[0,0]].entries()){
                const start=nativeCalls;
                window.GenUIRuntime.updateDocument({title:'Invalid',ui:{type:'Chart',props:{alt:'Invalid scores',
                    content:{chartType:'pie',data:values.map((value,i)=>({name:String(i),value}))}}}});
                await wait(60);
                results.push({id:theme+'/invalid-pie/'+index,valid:nativeCalls===start&&
                    document.querySelectorAll('#root svg').length===0&&
                    document.querySelector('.genui-unavailable')?.textContent==='Invalid scores'});
            }
        }
        return {results};
        """#, withNativeCharts: true)
        let cases = try XCTUnwrap(result["results"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 14)
        for item in cases {
            XCTAssertEqual(item["valid"] as? Bool, true, item["id"] as? String ?? "Unknown case")
        }
    }

    @MainActor
    private func runRichRuntimeScript(_ script: String, withMathJax: Bool = false, withNativeCharts: Bool = false) async throws -> [String: Any] {
        let document = GenUIDocument(title: "Rendering regression", ui: GenUINode(type: "text", children: [.string("Ready")]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Runtime ready")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        if withNativeCharts { webView.uiDelegate = recorder }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            configuration.userContentController.removeScriptMessageHandler(forName: "genui")
        }
        let baseURL = withMathJax ? MathMarkdownResourceResolver.mathJaxScriptURL(in: .main)?.deletingLastPathComponent() : nil
        webView.loadHTMLString(html, baseURL: baseURL)
        await fulfillment(of: [rendered], timeout: 15)
        let prelude = """
        const wait=(ms=30)=>new Promise(resolve=>setTimeout(resolve,ms));
        async function show(code){window.GenUIRuntime.updateDocument({title:'Regression',code});window.GenUIRuntime.reset();await wait();}
        """
        let result = try await webView.callAsyncJavaScript(prelude + script, arguments: [:], in: nil, contentWorld: .page)
        if withNativeCharts {
            let image = try await webView.takeSnapshot(configuration: nil)
            let attachment = XCTAttachment(image: image)
            attachment.name = "GenUI native chart"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertNil(recorder.error)
        return try XCTUnwrap(result as? [String: Any])
    }

    @MainActor
    func testRestorationSnapshotsDoNotInvalidateTheSwiftUIHost() {
        let state = GenUIState(document: GenUIDocument(title: "Powers", code: GenUITool.powersExample))
        var updates = 0
        let observation = state.objectWillChange.sink { updates += 1 }
        for value in 1...20 {
            state.richSnapshot = ["hooks": .array([.number(Double(value)), .number(3)])]
        }
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(state.richSnapshot?["hooks"], .array([.number(20), .number(3)]))
        state.richHeight = 400
        XCTAssertEqual(updates, 1, "Actual layout changes must still update the host")
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testPowerSlidersKeepControlsAndContentMountedDuringDrag() async throws {
        let document = GenUIDocument(title: "Powers", code: GenUITool.powersExample)
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Power sliders rendered")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        // WebKit only delivers display frames to an onscreen view.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = webView
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            configuration.userContentController.removeScriptMessageHandler(forName: "genui")
        }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        let result = try await webView.callAsyncJavaScript("""
        const root = document.getElementById('root');
        const sliders = Array.from(root.querySelectorAll('input[type=range]'));
        const fills = Array.from(root.querySelectorAll('.genui-slider-fill'));
        const card = root.querySelector('.genui-card');
        let removed = 0;
        const fillErrors = [];
        function checkFill(slider, index, value) {
            const fill = slider.parentElement.querySelector('.genui-slider-fill');
            if (!fill || fill !== fills[index]) { fillErrors.push('Fill was replaced'); return; }
            const fraction = (value - Number(slider.min)) / (Number(slider.max) - Number(slider.min));
            const expectedWidth = slider.getBoundingClientRect().width * fraction;
            if (Math.abs(fill.getBoundingClientRect().width - expectedWidth) > 1)
                fillErrors.push('Fill width did not match the thumb: ' + value);
            const track = fill.parentElement;
            if (Math.abs(track.getBoundingClientRect().height - 5) > 0.1 ||
                Math.abs(fill.getBoundingClientRect().height - 5) > 0.1)
                fillErrors.push('Track height: ' + JSON.stringify({track:track.getBoundingClientRect(),
                    fill:fill.getBoundingClientRect(), height:getComputedStyle(track).height,
                    variable:getComputedStyle(slider.parentElement).getPropertyValue('--slider-track-height')}));
        }
        const observer = new MutationObserver(records => {
            for (const record of records) removed += record.removedNodes.length;
        });
        observer.observe(root, {childList:true, subtree:true});
        for (const [index, values] of [[0,[3,4,5,2]], [1,[4,5,0,3]]]) {
            const slider = sliders[index];
            slider.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));
            for (const value of values) {
                slider.value = String(value);
                slider.dispatchEvent(new Event('input',{bubbles:true}));
                checkFill(slider, index, value);
                for (let frame = 0; frame < 3; frame++) {
                    await new Promise(requestAnimationFrame);
                    checkFill(slider, index, value);
                }
            }
            slider.dispatchEvent(new PointerEvent('pointerup',{bubbles:true}));
            await new Promise(requestAnimationFrame);
        }
        observer.disconnect();
        return {removed, fillErrors, fillCount:fills.length,
            same:sliders.every((slider,index) => slider === root.querySelectorAll('input[type=range]')[index]),
            card:card === root.querySelector('.genui-card'), text:card.textContent};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["removed"] as? Int, 0)
        XCTAssertEqual(result?["fillCount"] as? Int, 2)
        XCTAssertEqual(result?["fillErrors"] as? [String], [])
        XCTAssertEqual(result?["same"] as? Bool, true)
        XCTAssertEqual(result?["card"] as? Bool, true)
        XCTAssertTrue((result?["text"] as? String)?.contains("pow(2, 3) = 8") == true)
        XCTAssertNil(recorder.error)
    }

    @MainActor
    func testScopedDarkThemeUsesTheRecoveredForegroundPalette() async throws {
        let document = GenUIDocument(title: "Theme", ui: GenUINode(type: "card", props: ["theme": .string("dark")], children: [.node(GenUINode(type: "title", children: [.string("Read")]))]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Dark render")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 300), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        let color = try await webView.callAsyncJavaScript("return getComputedStyle(document.querySelector('.genui-title')).color", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(color, "rgb(255, 255, 255)")
    }

    @MainActor
    func testWebKitPreservesInputIdentityAndUpdatesCallbacks() async throws {
        let document = GenUIDocument(title: "Stable controls", code: #"""
        const [n,setN] = DIL.useState(0);
        return DIL.h('col', {}, DIL.h('input', {inputType:'number',value:n,onChange:value=>setN(Number(value)||0)}),
          DIL.h('text', {}, 'Result '+n), DIL.h('button', {label:'Reset',onClick:()=>setN(0)}));
        """#)
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Initial render")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        let result = try await webView.callAsyncJavaScript("""
        const input=document.querySelector('input'); input.focus(); input.value='12';
        input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0));
        const same=input===document.querySelector('input'), focused=document.activeElement===input;
        const edited=document.querySelector('.genui-text').textContent;
        input.value=''; input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0)); const draft=input.value;
        input.value='12'; input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0));
        document.querySelector('button').click();
        await new Promise(resolve=>setTimeout(resolve,0));
        return {same,focused,edited,draft,reset:document.querySelector('.genui-text').textContent};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["same"] as? Bool, true)
        XCTAssertEqual(result?["focused"] as? Bool, true)
        XCTAssertEqual(result?["edited"] as? String, "Result 12")
        XCTAssertEqual(result?["draft"] as? String, "")
        XCTAssertEqual(result?["reset"] as? String, "Result 0")
        XCTAssertNil(recorder.error)
    }

    func testOriginalComponentCatalogAndFixtureValidate() throws {
        XCTAssertEqual(GenUIReferenceCatalog.components.count, 283)
        XCTAssertEqual(try validated(GenUIOriginalFixture.document), GenUIOriginalFixture.document)
        let document = try GenUIDocument.validated(from: #"{"title":"Timer","ui":{"type":"DigitalTimerWidget","props":{"__state":{"start_time":90,"auto_start":false,"done_label":"Done"}}}}"#)
        XCTAssertEqual(document.ui?.type, "DigitalTimerWidget")
    }

    func testReferenceCompositionValidatesAndRoundTrips() throws {
        XCTAssertEqual(try validated(GenUIReferenceFixture.document), GenUIReferenceFixture.document)
        let data = try JSONEncoder().encode(GenUIReferenceFixture.document)
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: data), GenUIReferenceFixture.document)
    }

    func testReferenceElementsAndWidgetNamesValidate() throws {
        let document = try GenUIDocument.validated(from: #"""
        {"title":"Reference","state":{"ready":true},"ui":{"type":"Col","children":[
            {"type":"Scope","props":{"values":{"heading":"Heading"}},"children":[{"type":"title","children":["{{heading}}"]}]},
            {"type":"Each","props":{"items":[{"id":"a","name":"A"}],"as":"entry","keyField":"id"},"children":[{"type":"text","children":["{{entry.name}}"]}]},
            {"type":"Show","props":{"when":"{{ready}}"},"children":[{"type":"markdown","children":["**Ready**"]},{"type":"Show.Else","children":["Waiting"]}]},
            {"type":"flashcard-flip","props":{"front":{"type":"text","children":["Question"]},"back":{"type":"text","children":["Answer"]}}},
            {"type":"LoadingBlock","props":{"lines":3}},
            {"type":"animate-group","props":{"stagger":60},"children":[{"type":"animate-item","props":{"name":"slide"},"children":[{"type":"Badge","props":{"label":"New"}}]}]}
        ]}}
        """#)
        XCTAssertEqual(document.ui?.children?.count, 6)
        for (alias, type) in GenUIDocument.widgetAliases {
            XCTAssertEqual(GenUIDocument.componentCatalog[alias], GenUIDocument.componentCatalog[type], alias)
        }
    }

    func testEmbeddedReferenceNodesAndUnsafeStateKeysAreRejected() {
        for ui in [
            #"{"type":"flashcard-flip","props":{"front":{"type":"script"}}}"#,
            #"{"type":"component","props":{"content":[{"type":"Link","props":{"url":"javascript:alert(1)"}}]}}"#,
            #"{"type":"input","props":{"bind":"__proto__"}}"#,
            #"{"type":"button","props":{"onClick":{"type":"setState","key":"constructor","value":1}}}"#
        ] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Invalid\",\"ui\":\(ui)}"))
        }
    }

    func testRichRoundTripAndDefaults() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Rich","ui":{"type":"col","children":["hello",2,{"type":"text","props":{"color":null},"children":["world"]}]},"state":{"empty":null}}"#)
        XCTAssertTrue(document.components.isEmpty)
        XCTAssertTrue(document.inputs.isEmpty)
        XCTAssertEqual(document.ui?.children?.count, 3)
        XCTAssertEqual(document.state?["empty"], .null)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: data), document)
    }

    func testCodeDocumentAndExplicitResource() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Counter","code":"const [n,setN]=DIL.useState(0); return DIL.h('text',{},String(n));","resources":{"source":{"title":"Source","url":"https://example.com"}}}"#)
        XCTAssertNotNil(document.code)
        XCTAssertNil(document.ui)
        XCTAssertEqual(document.resources?["source"]?.url, "https://example.com")
    }

    func testUnsupportedTypesPropertiesURLsAndActionsFail() {
        for ui in [
            #"{"type":"script"}"#,
            #"{"type":"text","props":{"innerHTML":"<script>"}}"#,
            #"{"type":"Link","props":{"url":"javascript:alert(1)"}}"#,
            #"{"type":"AsyncImage","props":{"src":"data:image/svg+xml,abc"}}"#,
            #"{"type":"button","props":{"onClick":{"type":"runModel"}}}"#,
            #"{"type":"button","props":{"onClick":{"type":"openUrl","url":"file:///tmp/a"}}}"#
        ] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Invalid\",\"ui\":\(ui)}"))
        }
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"resources":{"bad":{"src":"http://example.com"}}}"#))
    }

    func testRendererModesAreExclusive() {
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"code":"return null"}"#))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"components":[{"id":"a","kind":"text","text":"text"}]}"#))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid"}"#))
    }

    func testTreesBeyondPreviousDepthAndNodeLimits() throws {
        var node = GenUINode(type: "text", children: [.string("leaf")])
        for _ in 0..<64 { node = GenUINode(type: "col", children: [.node(node)]) }
        for document in [
            GenUIDocument(title: "Deep", ui: node),
            GenUIDocument(title: "Wide", ui: GenUINode(type: "col", children: Array(repeating: .node(GenUINode(type: "text")), count: 1024))),
            GenUIDocument(title: "AppBlock", ui: GenUINode(type: "AppBlock", props: ["content": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(node))]))
        ] {
            XCTAssertEqual(try validated(document), document)
        }
    }

    func testDeepAndWideTreesStillRejectInvalidDescendants() throws {
        for leaf in [
            GenUINode(type: "script"),
            GenUINode(type: "text", props: ["innerHTML": .string("unsafe")]),
            GenUINode(type: "Link", props: ["url": .string("javascript:alert(1)")]),
            GenUINode(type: "path", props: ["d": .string("M0 0L1 1")])
        ] {
            var node = leaf
            for _ in 0..<64 { node = GenUINode(type: "col", children: [.node(node)]) }
            let children = Array(repeating: GenUIChild.node(GenUINode(type: "text")), count: 1024) + [.node(node)]
            XCTAssertThrowsError(try validated(GenUIDocument(title: "Invalid", ui: GenUINode(type: "col", children: children))))
        }
    }

    @MainActor
    func testWebKitExecutesLargeCodeAndPreservesLargeHookState() async throws {
        let text = String(repeating: "資料", count: 100_000)
        let code = """
        const [value] = DIL.useState(resources.source.text);
        const [principal, setPrincipal] = DIL.useState(300000);
        const monthly = DIL.useMemo(() => {
            const rate = 5 / 1200;
            return principal * rate / (1 - (1 + rate) ** -360);
        }, [principal]);
        return DIL.h('col', {},
            DIL.h('text', {}, String(Math.round(monthly))),
            DIL.h('button', {label:'Double', onClick:() => setPrincipal(p => p * 2)}));
        """ + String(repeating: " ", count: 65_537)
        let document = try validated(GenUIDocument(title: "WebKit", code: code, resources: ["source": GenUIResource(text: text)]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "GenUI rendered in WebKit")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        XCTAssertNil(recorder.error)
        let snapshot = try XCTUnwrap(recorder.snapshot)
        XCTAssertEqual(snapshot["hooks"], .array([.string(text), .number(300000)]))
        let result = try await webView.evaluateJavaScript("document.querySelector('.genui-text').textContent")
        XCTAssertEqual(result as? String, "1610")
        let updated = expectation(description: "GenUI recalculated locally")
        recorder.expectation = updated
        _ = try await webView.evaluateJavaScript("document.querySelector('button').click()")
        await fulfillment(of: [updated], timeout: 15)
        let doubled = try await webView.evaluateJavaScript("document.querySelector('.genui-text').textContent")
        XCTAssertEqual(doubled as? String, "3221")
        XCTAssertEqual(recorder.snapshot?["hooks"], .array([.string(text), .number(600000)]))
    }

    func testCodeAndDocumentsBeyondPreviousByteLimits() throws {
        let code = "return DIL.h('text', {}, '計算');" + String(repeating: " ", count: 65_537)
        let document = GenUIDocument(title: String(repeating: "題", count: 4097), subtitle: String(repeating: "説明", count: 4097), code: code,
                                     resources: ["source": GenUIResource(text: String(repeating: "資料", count: 50_000))])
        XCTAssertGreaterThan(try JSONEncoder().encode(document).count, 262_144)
        XCTAssertEqual(try validated(document), document)
        XCTAssertThrowsError(try validated(GenUIDocument(title: "Invalid", code: code + "return (")))
    }

    func testInitialDataBeyondPreviousCollectionAndNestingLimits() throws {
        var nested = JSONValue.number(1)
        for _ in 0..<64 { nested = .array([nested]) }
        var state = Dictionary(uniqueKeysWithValues: (0..<129).map { ("key\($0)", JSONValue.number(Double($0))) })
        state["nested"] = nested
        state["points"] = .array(Array(repeating: .number(1), count: 1024))
        state["object"] = .object(Dictionary(uniqueKeysWithValues: (0..<129).map { ("key\($0)", JSONValue.number(1)) }))
        let resources = Dictionary(uniqueKeysWithValues: (0..<65).map { ("ref\($0)", GenUIResource(text: "source")) })
        let document = GenUIDocument(title: "Data", ui: GenUINode(type: "Chart", props: ["content": .object(["data": state["points"]!])]), state: state, resources: resources)
        XCTAssertEqual(try validated(document), document)
    }

    func testRichSchemaDoesNotAdvertiseFixedSizeLimits() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUITool.definition.parametersJSON.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        for key in ["title", "code", "state", "resources"] {
            let property = try XCTUnwrap(properties[key] as? [String: Any])
            XCTAssertNil(property["maxLength"], key)
            XCTAssertNil(property["maxProperties"], key)
        }
        let node = try XCTUnwrap(properties["ui"] as? [String: Any])
        let nodeProperties = try XCTUnwrap(node["properties"] as? [String: Any])
        XCTAssertNil((nodeProperties["children"] as? [String: Any])?["maxItems"])
        XCTAssertFalse(GenUITool.definition.description.contains("Maximum 256 KiB"))
        XCTAssertTrue(GenUITool.definition.description.contains("Math.pow"))
    }

    private func validated(_ document: GenUIDocument) throws -> GenUIDocument {
        try GenUIDocument.validated(from: String(decoding: JSONEncoder().encode(document), as: UTF8.self))
    }

    func testBindingAndHostAction() throws {
        _ = try GenUIDocument.validated(from: #"{"title":"State","state":{"name":""},"ui":{"type":"input","props":{"bind":"name","value":"{{name}}","onChange":{"type":"setState","key":"name","value":"$value"}}}}"#)
        _ = try GenUIDocument.validated(from: #"{"title":"Host","ui":{"type":"button","props":{"onClick":{"type":"issueNewTurn","query":"Explain this"}},"children":["Explain"]}}"#)
    }

    func testLegacyDocumentRemainsValid() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Legacy","components":[{"id":"text","kind":"text","text":"Hello"}]}"#)
        XCTAssertEqual(document.components.count, 1)
        XCTAssertNil(document.ui)
        XCTAssertNil(document.code)
    }

    func testSVGPrimitivesAndLocalReferences() throws {
        _ = try GenUIDocument.validated(from: #"{"title":"SVG","ui":{"type":"svg","props":{"viewBox":"0 0 100 100"},"children":[{"type":"defs","children":[{"type":"linearGradient","props":{"id":"paint"},"children":[{"type":"stop","props":{"offset":"0%","stopColor":"red"}}]}]},{"type":"g","children":[{"type":"circle","props":{"cx":50,"cy":50,"r":20,"fill":"url(#paint)"}},{"type":"text","props":{"x":10,"y":10},"children":["SVG label"]}]}]}}"#)
        for node in [#"{"type":"path","props":{"d":"M0 0L1 1"}}"#, #"{"type":"svg","children":[{"type":"script"}]}"#, #"{"type":"svg","children":[{"type":"rect","props":{"href":"https://example.com"}}]}"#, #"{"type":"svg","children":[{"type":"circle","props":{"fill":"url(https://example.com)"}}]}"#] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Bad SVG\",\"ui\":\(node)}"))
        }
    }

    func testInlineAppBlockNodesAreValidated() throws {
        for key in ["content", "entrypoint"] {
            _ = try GenUIDocument.validated(from: "{\"title\":\"Inline\",\"ui\":{\"type\":\"AppBlock\",\"props\":{\"\(key)\":{\"type\":\"text\",\"children\":[\"Inline node\"]}}}}")
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Inline\",\"ui\":{\"type\":\"AppBlock\",\"props\":{\"\(key)\":{\"type\":\"script\"}}}}"))
        }
    }

    func testRichEncodingContainsOnlyItsRendererMode() throws {
        let document = GenUIDocument(title: "Rich", ui: GenUINode(type: "text"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        XCTAssertNotNil(json["ui"])
        XCTAssertNil(json["components"])
        XCTAssertNil(json["inputs"])
        XCTAssertNil(json["code"])
    }

    func testToolSchemaDefersNamesWhileTheValidatorKeepsTheCompleteCatalog() throws {
        let data = Data(GenUITool.definition.parametersJSON.utf8)
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let node = try XCTUnwrap(properties["ui"] as? [String: Any])
        let props = try XCTUnwrap(node["properties"] as? [String: Any])
        let type = try XCTUnwrap(props["type"] as? [String: Any])
        XCTAssertEqual(type["type"] as? String, "string")
        XCTAssertNil(type["enum"])
        XCTAssertNil(schema["$defs"])
        for name in GenUIReferenceCatalog.components.keys {
            XCTAssertNotNil(GenUIDocument.componentCatalog[name], name)
        }
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid child","ui":{"type":"col","children":[{"type":"MissingWidget"}]}}"#))
    }
}

@MainActor
private final class GenUIRenderRecorder: NSObject, WKScriptMessageHandler, WKUIDelegate {
    var expectation: XCTestExpectation?
    var snapshot: [String: JSONValue]?
    var error: String?

    init(expectation: XCTestExpectation) { self.expectation = expectation }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard frame.isMainFrame, prompt.hasPrefix("__genuiChart:") else { completionHandler(nil); return }
        completionHandler(GenUICELRuntime.evaluate(String(prompt.dropFirst("__genuiChart:".count))))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "state": snapshot = body["state"].flatMap(GenUIHostPolicy.snapshot)
        case "error": error = body["message"] as? String
        default: return
        }
        expectation?.fulfill()
        expectation = nil
    }
}
