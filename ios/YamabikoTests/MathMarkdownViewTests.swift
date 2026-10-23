import XCTest
import SwiftUI
import WebKit
import JavaScriptCore
@testable import YamabikoChat

final class MathMarkdownViewTests: XCTestCase {
    @MainActor
    func testNativeTableFitsWrappedTextWithoutOverlappingRows() async throws {
        let source = """
        | 候補 | あなたにとっての価値 |
        | --- | --- |
        | **追加契約なし** | 既存の Devin の軽量モデルを活用できれば、追加費用なしで悩みを検証できる |
        | **OpenCode Go** | 月10ドル。OpenCode 以外のエージェントでも使え、GLM-5.3-Flash や DeepSeek V4.1 Flash などが掲載されている |
        | **Claude Pro** | Claude を使う理由が明確なら候補。ただし、すでに強い AI が複数ある状況では、契約だけ増えるおそれ |
        | **X サブスク** | X の機能や利用自体に価値を感じる人向け |
        """
        for width: CGFloat in [320, 402, 768] {
            for typeSize: DynamicTypeSize in [.large, .accessibility3] {
                for streaming in [false, true] {
                    let host = UIHostingController(rootView:
                        NativeMarkdownView(markdownText: source, isStreaming: streaming,
                            preparsedBlocks: NativeMarkdownParser.parse(source))
                            .environment(\.dynamicTypeSize, typeSize)
                            .frame(width: width, alignment: .topLeading)
                    )
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 2000))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true }
                    // Allow the asynchronous Markdown parser to publish its blocks.
                    for _ in 0..<100 {
                        try await Task.sleep(for: .milliseconds(20))
                        host.view.layoutIfNeeded()
                        if tableTextViews(in: host.view).count == 10 { break }
                    }
                    let cells = tableTextViews(in: host.view)
                    XCTAssertEqual(cells.count, 10)
                    for cell in cells {
                        let needed = cell.sizeThatFits(CGSize(width: cell.bounds.width, height: .greatestFiniteMagnitude))
                        XCTAssertGreaterThanOrEqual(cell.bounds.height + 1, needed.height,
                            "Cell must fit all wrapped lines at width \(width), \(typeSize), streaming=\(streaming): \(cell.text ?? "")")
                    }
                    let descriptions = cells.filter { $0.text.contains("既存の") || $0.text.contains("月10ドル") || $0.text.contains("Claude を") || $0.text.contains("X の") }
                        .map { $0.convert($0.bounds, to: host.view) }
                        .sorted { $0.minY < $1.minY }
                    XCTAssertEqual(descriptions.count, 4)
                    for (previous, next) in zip(descriptions, descriptions.dropFirst()) {
                        XCTAssertLessThanOrEqual(previous.maxY, next.minY, "Table rows must not overlap")
                    }
                }
            }
        }
    }

    @MainActor
    func testNativeMarkdownFitsLongHeadingsListsAndQuotes() async throws {
        let longText = String(repeating: "長い日本語と English の文章を折り返して表示します。", count: 8)
        let source = """
        # \(longText)

        \(longText)

        1. \(longText)
        2. **\(longText)**

        > \(longText)
        >
        > \(longText)

        ```swift
        let message = "長いコードも横スクロールで表示します"
        print(message)
        ```

        末尾の文章
        """
        for width: CGFloat in [320, 768] {
            for typeSize: DynamicTypeSize in [.large, .accessibility3] {
                let host = UIHostingController(rootView:
                    NativeMarkdownView(markdownText: source, isStreaming: true,
                        preparsedBlocks: NativeMarkdownParser.parse(source))
                        .environment(\.dynamicTypeSize, typeSize)
                        .frame(width: width, alignment: .topLeading)
                )
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 2000))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                try await Task.sleep(for: .milliseconds(50))
                host.view.layoutIfNeeded()
                let textViews = tableTextViews(in: host.view)
                XCTAssertFalse(textViews.isEmpty)
                for text in textViews {
                    let needed = text.sizeThatFits(CGSize(width: text.bounds.width, height: .greatestFiniteMagnitude))
                    XCTAssertGreaterThanOrEqual(text.bounds.height + 1, needed.height)
                }
                let frames = textViews.map { $0.convert($0.bounds, to: host.view) }.sorted { $0.minY < $1.minY }
                for (previous, next) in zip(frames, frames.dropFirst()) {
                    XCTAssertLessThanOrEqual(previous.maxY, next.minY)
                }
            }
        }
    }

    @MainActor
    private func tableTextViews(in view: UIView) -> [SelectableChatTextView] {
        if let text = view as? SelectableChatTextView { return [text] }
        return view.subviews.flatMap { tableTextViews(in: $0) }
    }

    // Exact answer from the trigonometric-addition diagnostic export (2026-10-22).
    private static let trigonometricDiagnosticAnswer = #"""
    加法定理を三角関数の公式として、証明します。

    \[
    \sin(\alpha+\beta)=\sin\alpha\cos\beta+\cos\alpha\sin\beta
    \]

    \[
    \cos(\alpha+\beta)=\cos\alpha\cos\beta-\sin\alpha\sin\beta
    \]

    単位円上で、角 \(t\) に対応する点を
    \[
    P(t)=(\cos t,\sin t)
    \]
    とします。角 \(\alpha\) だけ回転させる行列は
    \[
    R(\alpha)=
    \begin{pmatrix}
    \cos\alpha&-\sin\alpha\\
    \sin\alpha&\cos\alpha
    \end{pmatrix}
    \]
    です。

    点 \(P(\beta)\) を角 \(\alpha\) だけ回転させると \(P(\alpha+\beta)\) になるので、
    \[
    \begin{pmatrix}
    \cos(\alpha+\beta)\\
    \sin(\alpha+\beta)
    \end{pmatrix}
    =
    \begin{pmatrix}
    \cos\alpha&-\sin\alpha\\
    \sin\alpha&\cos\alpha
    \end{pmatrix}
    \begin{pmatrix}
    \cos\beta\\
    \sin\beta
    \end{pmatrix}.
    \]

    右辺を計算すると、
    \[
    \begin{pmatrix}
    \cos\alpha\cos\beta-\sin\alpha\sin\beta\\
    \sin\alpha\cos\beta+\cos\alpha\sin\beta
    \end{pmatrix}.
    \]
    成分を比べれば、上の2つの公式が得られます。
    """#

    @MainActor
    func testTrigonometricDiagnosticAnswerRendersMatricesInNativeMessageView() async throws {
        try await assertMathRenders(Self.trigonometricDiagnosticAnswer, expectedEquationCount: 11, usesNativeView: true)
    }

    @MainActor
    func testTrigonometricDiagnosticAnswerFitsTimelineCell() async throws {
        try await assertTimelineMathFits(Self.trigonometricDiagnosticAnswer, expectedEquationCount: 11)
    }

    // Exact answer from the sphere-surface-area diagnostic export (2026-10-22).
    private static let diagnosticAnswer = #"""
    球の表面積の求め方の証明を3種類、サブエージェントを用いてまとめました。

    ---

    ### 1. 積分法（回転体の表面積）\#u{0020}\#u{0020}
    **証明の概要**\#u{0020}\#u{0020}
    半円 $y = \sqrt{r^2 - x^2}$ を $x$ 軸の周りに回転させた回転体の表面積として計算します。\#u{0020}\#u{0020}
    表面積の公式：\#u{0020}\#u{0020}
    $$S = 2\pi \int_{-r}^{r} y \sqrt{1 + \left(\frac{dy}{dx}\right)^2} \, dx$$\#u{0020}\#u{0020}

    - $\frac{dy}{dx} = -\frac{x}{\sqrt{r^2 - x^2}}$\#u{0020}\#u{0020}
    - $\sqrt{1 + \left(\frac{dy}{dx}\right)^2} = \frac{r}{\sqrt{r^2 - x^2}}$\#u{0020}\#u{0020}
    - $y \cdot \sqrt{1 + \left(\frac{dy}{dx}\right)^2} = r$\#u{0020}\#u{0020}

    したがって、\#u{0020}\#u{0020}
    $$S = 2\pi \int_{-r}^{r} r \, dx = 2\pi r \cdot 2r = 4\pi r^2$$\#u{0020}\#u{0020}

    ---

    ### 2. 微小面積の積分（球面座標）\#u{0020}\#u{0020}
    **証明の概要**\#u{0020}\#u{0020}
    球面座標 $(R, \theta, \phi)$ で微小面積要素を求め、全表面を積分します。\#u{0020}\#u{0020}
    座標：\#u{0020}\#u{0020}
    - $x = R \sin\theta \cos\phi$\#u{0020}\#u{0020}
    - $y = R \sin\theta \sin\phi$\#u{0020}\#u{0020}
    - $z = R \cos\theta$\#u{0020}\#u{0020}

    微小面積要素：\#u{0020}\#u{0020}
    $$dA = R^2 \sin\theta \, d\theta \, d\phi$$\#u{0020}\#u{0020}

    積分範囲：$\theta \in [0, \pi]$, $\phi \in [0, 2\pi]$\#u{0020}\#u{0020}
    $$S = \int_0^{2\pi} \int_0^{\pi} R^2 \sin\theta \, d\theta \, d\phi = R^2 \cdot 2\pi \cdot 2 = 4\pi R^2$$\#u{0020}\#u{0020}

    ---

    ### 3. アルキメデスの方法（円柱との比較）\#u{0020}\#u{0020}
    **証明の概要**\#u{0020}\#u{0020}
    アルキメデスは、半径 $r$ の球を同じ半径・高さ $2r$ の円柱に内接させ、球の表面積が円柱の側面積に等しいことを示しました。\#u{0020}\#u{0020}

    - 円柱の側面積：$2\pi r \cdot 2r = 4\pi r^2$\#u{0020}\#u{0020}
    - 球の表面積を水平な微小帯に分割し、各帯の面積が円柱の対応する帯と等しいことを幾何学的に証明（断面の投影による等価性）。\#u{0020}\#u{0020}

    結果：$S = 4\pi r^2$\#u{0020}\#u{0020}

    ---

    いずれの方法でも、球の表面積は $4\pi r^2$ となります。
    """#

    @MainActor
    func testDiagnosticAnswerRendersAllEquationsInNativeMessageView() async throws {
        try await assertMathRenders(Self.diagnosticAnswer, expectedEquationCount: 20, usesNativeView: true)
    }

    @MainActor
    func testDiagnosticAnswerRendersAfterStreamCompletionAndViewRecreation() async throws {
        let row = ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 130,
            message: ChatMessage(id: 130, conversationId: 46, role: "model", text: "", createdAtMs: 1),
            thinkingStream: nil, variants: []
        )))
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 130, text: Self.diagnosticAnswer, thinking: "", isFinal: false))
        try await assertMathRenders(Self.diagnosticAnswer, expectedEquationCount: 20, presentationRow: row)
        // Recreate the host like a timeline cell coming back on screen.
        try await assertMathRenders(Self.diagnosticAnswer, expectedEquationCount: 20, presentationRow: row)
    }

    private struct StreamingDiagnosticView: View {
        @ObservedObject var row: ChatTimelineRowStore

        var body: some View {
            NativeMarkdownView(
                markdownText: row.streamingSnapshot?.text ?? "",
                isStreaming: row.streamingSnapshot?.isFinal == false,
                preparsedBlocks: row.streamingMarkdownBlocks
            )
            .environment(\.markdownPresentationCache, row.markdownPresentationCache)
        }
    }

    @MainActor
    func testMathRendersInActualWebView() async throws {
        try await assertMathRenders(AppStoreScreenshotDemoSeeder.mathRenderingFixtureText)
    }

    @MainActor
    func testMathHasTextHeightOnFirstLayoutBeforeWebKitLoads() {
        let source = Array(repeating: "数式の準備中も本文を表示します。$x^2 + y^2 = r^2$", count: 20)
            .joined(separator: "\n")
        let host = UIHostingController(rootView: MathMarkdownView(markdownText: source))
        let size = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, 400, "The first layout must fit the text, rather than an empty 44-point WebView")
    }

    private static let dollarMathListFixture = #"""
    **手法:** 半円を $x$ 軸の周りに回転させます。

    1. **球の表現:** 半径 $r$ の球を、半円 $y = \sqrt{r^2 - x^2}$（$x \in [-r, r]$）として表します。

    2. **表面積の公式:** $S = 2\pi \int_{-r}^{r} y \sqrt{1 + \left(\frac{dy}{dx}\right)^2}\,dx$。

    3. **微分:** $\frac{dy}{dx} = -\frac{x}{\sqrt{r^2 - x^2}}$。

    4. **被積分関数の簡略化:**

       $$
       \sqrt{1 + \left(\frac{dy}{dx}\right)^2}

       = \frac{r}{\sqrt{r^2 - x^2}}
       $$

       したがって、$S = 4\pi r^2$。
    """#

    @MainActor
    func testDollarMathListRendersInNativeMessageView() async throws {
        try await assertMathRenders(Self.dollarMathListFixture, expectedEquationCount: 8, usesNativeView: true)
    }

    @MainActor
    func testStandaloneFractionFitsWebViewHeight() async throws {
        try await assertMathRenders(#"\[S=\frac{dV}{dr}=\frac{d}{dr}\left(\frac{4}{3}\pi r^3\right)=4\pi r^2.\]"#)
    }

    @MainActor
    func testMathParagraphRemainsVisibleBelowUserMessage() async throws {
        try await assertTimelineMathFits(AppStoreScreenshotDemoSeeder.mathRenderingFixtureText)
    }

    @MainActor
    func testDiagnosticAnswerTimelineCellFitsAllMath() async throws {
        try await assertTimelineMathFits(Self.diagnosticAnswer, expectedEquationCount: 20)
    }

    @MainActor
    private func assertTimelineMathFits(_ source: String, expectedEquationCount: Int? = nil) async throws {
        let expectedBlocks = NativeMarkdownParser.parse(source).filter {
            if case .math = $0 { return true }
            return false
        }.count
        let store = ChatTimelineStore()
        store.update(messages: [
            FullChatMessage(id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "user", text: "球の表面積を説明してください", createdAtMs: 1), thinkingStream: nil, variants: []),
            FullChatMessage(id: 2, message: ChatMessage(id: 2, conversationId: 1, role: "model", text: source, createdAtMs: 2), thinkingStream: nil, variants: [])
        ])
        let controller = ChatTimelineViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.configure(store: store, scrollToLatestRequest: 0, regeneratableMessageID: nil,
            dualSplitLayout: "VERTICAL", dualSplitRatio: 0.5,
            onRoute: { _ in }, onPreviousVariant: { _ in },
            onNextVariant: { _ in }, onBranch: { _ in }, onRegenerate: {}, onAskChatWithSelection: { _ in },
            onEditUserMessage: { _ in }, onSelectUserMessageText: { _ in })
        func webViews(_ view: UIView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
        }
        let expectedEquations = expectedEquationCount ?? (source.components(separatedBy: #"\("#).count - 1
            + source.components(separatedBy: #"\["#).count - 1)
        var rendered = false
        for _ in 0..<100 {
            controller.view.layoutIfNeeded()
            let views = webViews(controller.view)
            if views.count == expectedBlocks {
                var equations = 0
                for view in views {
                    equations += (try? await view.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length")) as? Int ?? 0
                }
                rendered = equations == expectedEquations
                if rendered { break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Timeline math rendering"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(rendered)
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        for view in webViews(controller.view) {
            var ancestor = view.superview
            while ancestor != nil, !(ancestor is UICollectionViewCell) { ancestor = ancestor?.superview }
            let cell = try XCTUnwrap(ancestor as? UICollectionViewCell)
            let frameInCell = view.convert(view.bounds, to: cell)
            XCTAssertGreaterThanOrEqual(frameInCell.minY, -1, "Math paragraph must not start above its clipped chat cell")
            XCTAssertLessThanOrEqual(frameInCell.maxY, cell.bounds.maxY + 1, "Math paragraph must fit inside its chat cell")
            let top = try await view.evaluateJavaScript("document.getElementById('yamabiko-markdown').getBoundingClientRect().top") as? Double
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(top), -1)
        }
    }

    @MainActor
    private func assertMathRenders(_ source: String, expectedEquationCount: Int? = nil, usesNativeView: Bool = false, presentationRow: ChatTimelineRowStore? = nil) async throws {
        let expectedCount = expectedEquationCount ?? (source.components(separatedBy: #"\("#).count - 1
            + source.components(separatedBy: #"\["#).count - 1)
        let mathBlocks = NativeMarkdownParser.parse(source).compactMap { block -> String? in
            guard case let .math(_, markdown) = block else { return nil }
            return markdown
        }.joined(separator: "\n")
        if expectedEquationCount == nil {
            XCTAssertEqual(mathBlocks.components(separatedBy: #"\("#).count - 1
                + mathBlocks.components(separatedBy: #"\["#).count - 1, expectedCount)
        }
        let controller = UIHostingController(rootView: ScrollView {
            if let presentationRow {
                StreamingDiagnosticView(row: presentationRow)
            } else if usesNativeView {
                NativeMarkdownView(markdownText: source)
            } else {
                MathMarkdownView(markdownText: source)
            }
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        if let presentationRow, presentationRow.streamingSnapshot?.isFinal == false {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            presentationRow.apply(snapshot: ChatStreamingSnapshot(targetId: 130, text: source, thinking: "", isFinal: true))
        }
        func webViews(_ view: UIView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
        }
        var count = 0
        var state = ""
        var outsideViewport = -1
        var visibleWebViews = 0
        for _ in 0..<100 {
            controller.view.layoutIfNeeded()
            let views = webViews(controller.view)
            count = 0
            outsideViewport = 0
            visibleWebViews = 0
            for webView in views {
                var ancestor: UIView? = webView
                var isVisible = true
                while let view = ancestor {
                    if view.isHidden || view.alpha < 0.99 || view.layer.opacity < 0.99 { isVisible = false }
                    ancestor = view.superview
                }
                if isVisible { visibleWebViews += 1 }
                count += (try? await webView.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length")) as? Int ?? 0
                state = String(describing: try? await webView.evaluateJavaScript("JSON.stringify({math:typeof window.MathJax, viewport:innerHeight, root:document.getElementById('yamabiko-markdown').getBoundingClientRect().toJSON(), svg:Array.from(document.querySelectorAll('mjx-container svg')).map(s=>s.getBoundingClientRect().toJSON())})")) + " frame=\(webView.frame)"
                if count > 0 {
                    outsideViewport += (try await webView.evaluateJavaScript("""
                        Array.from(document.querySelectorAll('mjx-container svg')).filter(svg => {
                            const box = svg.getBoundingClientRect();
                            return box.top < -1 || box.bottom > window.innerHeight + 1;
                        }).length
                        """)) as? Int ?? -1
                    let clipped = try await webView.evaluateJavaScript("""
                        Array.from(document.querySelectorAll('mjx-container[display="true"]')).filter(container => {
                            const svg = container.querySelector('svg').getBoundingClientRect();
                            const box = container.getBoundingClientRect();
                            return svg.top < box.top - 1 || svg.bottom > box.bottom + 1;
                        }).length
                        """) as? Int
                    XCTAssertEqual(clipped, 0, "Display equations must fit their scroll containers")
                    let errors = try await webView.evaluateJavaScript("document.querySelectorAll('mjx-merror').length") as? Int
                    XCTAssertEqual(errors, 0)
                }

            }
            if count == expectedCount, outsideViewport == 0, visibleWebViews == views.count { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Math rendering in iOS simulator"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(count, expectedCount, state)
        XCTAssertEqual(visibleWebViews, webViews(controller.view).count, "Painted equations must replace the initial text")
        XCTAssertEqual(outsideViewport, 0, "All equations must fit inside the measured WebView height: \(state)")
    }

    func testMathListRendererPreservesNumberingContinuationAndNestedBlocks() throws {
        let source = #"""
        7. **公式:** $S = 4\pi r^2$
           続きの説明。

           $$
           \frac{r}{\sqrt{r^2-x^2}}

           $$

           - 内側 $r$

        8. 次の項目 $x$
        """#
        let html = try renderMarkdownWithJavaScript(source)
        XCTAssertTrue(html.hasPrefix("<ol start=\"7\"><li>"), html)
        XCTAssertEqual(html.components(separatedBy: "<ol").count - 1, 1, html)
        XCTAssertTrue(html.contains("<ul><li><p>内側 $r$</p></li></ul>"), html)
        XCTAssertTrue(html.contains("</ul></li><li><p>次の項目 $x$</p></li></ol>"), html)
        XCTAssertTrue(html.contains(#"\frac{r}{\sqrt{r^2-x^2}}"#), html)
        XCTAssertFalse(html.contains("@@"), html)
    }

    @MainActor
    func testMathWaitsForEngineStartupBeforeCommittingContent() async throws {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: #""$x^2$""#,
            markdownRendererScript: "window.yamabikoRenderMarkdown = s => '<p>' + s + '</p>';",
            bodyTextColor: "#000000", codeBackgroundColor: "#111111",
            borderColor: "#222222", linkColor: "#333333",
            mathJaxScriptTag: """
            <script>
            window.MathJax.startup.promise = new Promise(resolve => {
              window.finishStartup = function() {
                window.MathJax.typesetPromise = function(targets) {
                  targets[0].textContent = 'rendered equation';
                  return Promise.resolve();
                };
                resolve();
              };
            });
            </script>
            """
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        webView.loadHTMLString(html, baseURL: nil)
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("typeof window.finishStartup === 'function'")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let before = try await webView.evaluateJavaScript("document.getElementById('yamabiko-markdown').textContent") as? String
        XCTAssertEqual(before, "", "Raw TeX must not count as a finished render while MathJax is starting")
        _ = try await webView.evaluateJavaScript("window.finishStartup();")
        let after = try await webView.evaluateJavaScript("document.getElementById('yamabiko-markdown').textContent") as? String
        XCTAssertEqual(after, "rendered equation")
    }

    @MainActor
    func testFailedTypesettingDoesNotPublishRawTeXAndNextRenderRecovers() async throws {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: #""$first$""#,
            markdownRendererScript: "window.yamabikoRenderMarkdown = s => '<p>' + s + '</p>';",
            bodyTextColor: "#000000", codeBackgroundColor: "#111111",
            borderColor: "#222222", linkColor: "#333333",
            mathJaxScriptTag: """
            <script>
            window.renderErrors = [];
            window.webkit = {messageHandlers: {mathRenderError: {postMessage: function(error) {
              window.renderErrors.push(error);
            }}}};
            window.MathJax.typesetPromise = function() { return Promise.reject(new Error('test failure')); };
            </script>
            """
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        webView.loadHTMLString(html, baseURL: nil)
        var errorCount = 0
        for _ in 0..<100 {
            errorCount = (try? await webView.evaluateJavaScript("window.renderErrors.length")) as? Int ?? 0
            if errorCount > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(errorCount, 1, "Report typesetting failures to native diagnostics")
        let failedText = try await webView.evaluateJavaScript("document.getElementById('yamabiko-markdown').textContent") as? String
        XCTAssertEqual(failedText, "")
        let ready = try await webView.evaluateJavaScript("window.__yamabikoContentReady") as? Bool
        XCTAssertEqual(ready, false)
        _ = try await webView.evaluateJavaScript("""
            window.MathJax.typesetPromise = function(targets) {
              targets[0].textContent = 'recovered equation';
              return Promise.resolve();
            };
            window.__yamabikoRenderSource('$next$', true);
            """)
        let recoveredText = try await webView.evaluateJavaScript("document.getElementById('yamabiko-markdown').textContent") as? String
        XCTAssertEqual(recoveredText, "recovered equation")
        let roots = try await webView.evaluateJavaScript("document.querySelectorAll('.yamabiko-markdown').length") as? Int
        XCTAssertEqual(roots, 1, "Failed staging roots must be removed")
    }

    @MainActor
    func testFinalSnapshotPublishesMathBlocksBeforeViewTasksRun() throws {
        let row = ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 130,
            message: ChatMessage(id: 130, conversationId: 46, role: "model", text: "", createdAtMs: 1),
            thinkingStream: nil, variants: []
        )))
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 130, text: Self.diagnosticAnswer, thinking: "", isFinal: false))
        XCTAssertTrue(try XCTUnwrap(row.streamingMarkdownBlocks).contains { if case .math = $0 { return true }; return false })
        row.apply(snapshot: ChatStreamingSnapshot(targetId: 130, text: Self.diagnosticAnswer, thinking: "", isFinal: true))
        let expected = NativeMarkdownParser.parse(Self.diagnosticAnswer)
        XCTAssertEqual(row.streamingMarkdownBlocks, expected)
        XCTAssertEqual(row.markdownPresentationCache.blocks(for: Self.diagnosticAnswer, rendersMath: true), expected)
    }

    @MainActor
    func testMathUpdatesKeepCommittedContentUntilTypesettingCompletes() async throws {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"first\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = s => '<p>' + s + '</p>';",
            bodyTextColor: "#000000", codeBackgroundColor: "#111111",
            borderColor: "#222222", linkColor: "#333333",
            mathJaxScriptTag: """
            <script>
            window.MathJax.typesetClear = function() {};
            window.MathJax.typesetPromise = function(targets) {
              return new Promise(resolve => {
                window.finishTypesetting = function() {
                  targets[0].textContent = 'typeset:' + targets[0].textContent;
                  window.finishTypesetting = null;
                  resolve();
                };
              });
            };
            </script>
            """
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        webView.loadHTMLString(html, baseURL: nil)
        func waitForPendingTypeset() async throws {
            for _ in 0..<100 {
                if (try? await webView.evaluateJavaScript("typeof window.finishTypesetting === 'function'")) as? Bool == true {
                    return
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("Typesetting did not start")
        }
        func displayedText() async throws -> String {
            try await webView.evaluateJavaScript("document.getElementById('yamabiko-markdown').textContent") as? String ?? ""
        }
        try await waitForPendingTypeset()
        let initial = try await displayedText()
        XCTAssertEqual(initial, "", "Unprocessed TeX must never be committed")
        _ = try await webView.evaluateJavaScript("window.finishTypesetting();")
        let first = try await displayedText()
        XCTAssertEqual(first, "typeset:first")
        _ = try await webView.evaluateJavaScript("window.__yamabikoRenderSource('second', true);")
        try await waitForPendingTypeset()
        let duringUpdate = try await displayedText()
        XCTAssertEqual(duringUpdate, first, "Keep the previous output throughout asynchronous typesetting")
        _ = try await webView.evaluateJavaScript("window.__yamabikoRenderSource('latest', true); window.finishTypesetting();")
        try await waitForPendingTypeset()
        let afterStaleRender = try await displayedText()
        XCTAssertEqual(afterStaleRender, first, "A superseded render must not replace visible content")
        _ = try await webView.evaluateJavaScript("window.finishTypesetting();")
        let latest = try await displayedText()
        XCTAssertEqual(latest, "typeset:latest")
        let stagingCount = try await webView.evaluateJavaScript("document.querySelectorAll('.yamabiko-markdown').length") as? Int
        XCTAssertEqual(stagingCount, 1)
    }

    func testBuildHTMLIncludesMathJax() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"hello\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathJaxScriptTag: "<script src=\"tex-svg.js\"></script>"
        )

        XCTAssertTrue(html.contains("window.MathJax ="))
        XCTAssertTrue(html.contains("tex-svg.js"))
        XCTAssertTrue(html.contains("typesetPromise([root])"))
        XCTAssertTrue(html.contains("packages: {'[-]': ['require']}"))
        XCTAssertTrue(html.contains("options: { enableMenu: false }"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testResourceSynchronizationReplacesStaleCachedFiles() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try Data("new-script".utf8).write(to: source.appendingPathComponent("tex-svg.js"))
        try Data("old".utf8).write(to: destination.appendingPathComponent("tex-svg.js"))

        try MathMarkdownWebResourceLoader.synchronizeResources(
            from: source,
            to: destination,
            fileManager: fileManager
        )

        let value = try String(
            contentsOf: destination.appendingPathComponent("tex-svg.js"),
            encoding: .utf8
        )
        XCTAssertEqual(value, "new-script", "A stale cache must be replaced from the bundle")
    }

    func testResolveResourceURLPrefersMathJaxSubdirectory() {
        let subdirectoryURL = URL(fileURLWithPath: "/tmp/mathjax/markdown-renderer.js")
        let rootURL = URL(fileURLWithPath: "/tmp/markdown-renderer.js")

        let resolved = MathMarkdownResourceResolver.resolveResourceURL(
            resource: "markdown-renderer",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: { _, _, subdirectory in
                if subdirectory == "mathjax" {
                    return subdirectoryURL
                }
                if subdirectory == nil {
                    return rootURL
                }
                return nil
            }
        )

        XCTAssertEqual(resolved, subdirectoryURL)
    }

    func testResolveResourceURLFallsBackToRootWhenSubdirectoryMissing() {
        let rootURL = URL(fileURLWithPath: "/tmp/markdown-renderer.js")

        let resolved = MathMarkdownResourceResolver.resolveResourceURL(
            resource: "markdown-renderer",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: { _, _, subdirectory in
                subdirectory == nil ? rootURL : nil
            }
        )

        XCTAssertEqual(resolved, rootURL)
    }

    func testMarkdownRendererScriptFallsBackAndLogsWhenResourceMissing() {
        var logs: [String] = []

        let script = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "fallback-renderer",
            lookup: { _, _, _ in nil },
            scriptLoader: { _ in
                XCTFail("scriptLoader should not be called when lookup fails")
                return nil
            },
            logger: { message in
                logs.append(message)
            }
        )

        XCTAssertEqual(script, "fallback-renderer")
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("fallback"))
    }

    func testGeneratedFallbackMatchesBundledRendererAndPreservesBlankLinesInMath() throws {
        let bundled = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "",
            logger: { _ in XCTFail("Bundled renderer must be present") }
        )
        XCTAssertEqual(MathMarkdownRendererSource.script, bundled)
        for unavailableScript in [nil, "", "  "] as [String?] {
            var warnings: [String] = []
            let fallback = MathMarkdownResourceResolver.markdownRendererScript(
                fallbackScript: MathMarkdownRendererSource.script,
                lookup: { _, _, _ in URL(fileURLWithPath: "/missing.js") },
                scriptLoader: { _ in unavailableScript },
                logger: { warnings.append($0) }
            )
            XCTAssertEqual(warnings.count, 1)
            let context = try XCTUnwrap(JSContext())
            context.evaluateScript("var window = this;")
            context.evaluateScript(fallback)
            let render = try XCTUnwrap(context.objectForKeyedSubscript("yamabikoRenderMarkdown"))
            for math in ["$$\nx = 1\n\ny = 2\n$$", #"\["# + "\nx = 1\n\ny = 2\n" + #"\]"#] {
                let html = try XCTUnwrap(render.call(withArguments: [math])?.toString())
                XCTAssertEqual(html.components(separatedBy: "<p>").count - 1, 1, html)
                XCTAssertTrue(html.contains("x = 1"))
                XCTAssertTrue(html.contains("y = 2"))
            }
        }
    }

    func testMarkdownRendererScriptUsesLoadedScriptWhenAvailable() {
        let resolvedURL = URL(fileURLWithPath: "/tmp/mathjax/markdown-renderer.js")
        let rendererScript = "window.yamabikoRenderMarkdown = function(){ return '<p>ok</p>'; };"

        let script = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "fallback-renderer",
            lookup: { _, _, _ in resolvedURL },
            scriptLoader: { _ in rendererScript },
            logger: { _ in
                XCTFail("logger should not be called when script is loaded")
            }
        )

        XCTAssertEqual(script, rendererScript)
    }

    func testNormalizeEscapedDollarDelimitersBothSides() {
        let input = #"数式: \$sum_{k=1}^{n} k\$ を表示"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"数式: $sum_{k=1}^{n} k$ を表示"#)
    }

    func testNormalizeEscapedDollarDelimitersEscapedOpeningOnly() {
        let input = #"数式: \$sum_{k=1}^{n} k$ を表示"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"数式: $sum_{k=1}^{n} k$ を表示"#)
    }

    func testNormalizeEscapedDollarDelimitersPreservesEscapedCurrency() {
        let input = #"価格は \$5 です"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedDollarDelimitersSkipsInlineCode() {
        let input = #"`x = \$sum$` と本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"`x = \$sum$` と本文 $sum$"#)
    }

    func testNormalizeEscapedDollarDelimitersSkipsFencedCodeBlock() {
        let input = #"""
```tex
\$sum$
```
本文 \$sum$
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)
        let expected = #"""
```tex
\$sum$
```
本文 $sum$
"""#

        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededNormalizes() {
        let input = #"本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, #"本文 $sum$"#)
    }

    func testNormalizeEscapedMathIfNeededNormalizesEscapedSequencesWhenMathPresent() {
        let input = #"1行目\\n\\(a+b\\) と \\$sum_{k=1}^{n}k\\$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        let expected = """
        1行目
        \\(a+b\\) と $sum_{k=1}^{n}k$
        """
        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededDoesNotNormalizeEscapedSequencesWithoutMath() {
        let input = #"line1\\nline2"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedMathIfNeededSkipsEscapedSequenceNormalizationInCode() {
        let input = #"""
```text
\\n\\(x\\)
```
本文 \\(x+y\\)
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        let expected = #"""
```text
\\n\\(x\\)
```
本文 \(x+y\)
"""#
        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededIgnoresMathMarkersInsideCodeOnly() {
        let input = #"""
```text
\$sum$
```
line1\\nline2
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, input)
    }

    func testMathJaxLoadPlannerPrefersLocalScriptWhenAvailable() {
        let localURL = URL(fileURLWithPath: "/tmp/mathjax/tex-svg.js")

        let plan = MathJaxLoadPlanner.plan(
            localScriptURL: localURL
        )

        XCTAssertTrue(plan.scriptTag.contains("src=\"tex-svg.js\""))
        XCTAssertEqual(plan.baseURL, localURL.deletingLastPathComponent())
    }

    func testMathJaxLoadPlannerReportsMissingLocalScript() {
        var logs: [String] = []

        let plan = MathJaxLoadPlanner.plan(
            localScriptURL: nil,
            logger: { message in
                logs.append(message)
            }
        )

        XCTAssertTrue(plan.scriptTag.isEmpty)
        XCTAssertNil(plan.baseURL)
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("local script missing"))
    }

    func testMarkdownRendererDoesNotLeakMathPlaceholdersAfterEmphasisReplacement() throws {
        let result = try renderMarkdownWithJavaScript("本文 *強調* と $x_i$")

        XCTAssertFalse(result.contains("@@"))
        XCTAssertTrue(result.contains("$x_i$"))
        XCTAssertTrue(result.contains("<em>強調</em>"))
    }

    func testMarkdownRendererEscapesHTMLInsideMathDelimiters() throws {
        let result = try renderMarkdownWithJavaScript("$<img src=x onerror=alert(1)>$")

        XCTAssertFalse(result.contains("<img"))
        XCTAssertTrue(result.contains("&lt;img"))
    }

    func testMarkdownRendererWrapsCodeBlockWithCopyButton() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            ```swift
            let value = 42
            ```
            """
        )

        XCTAssertTrue(result.contains("yamabiko-code-block"))
        XCTAssertTrue(result.contains("yamabiko-copy-button"))
        XCTAssertTrue(result.contains(">Copy<"))
        XCTAssertTrue(result.contains("let value = 42"))
        XCTAssertFalse(result.contains("```"))
    }

    func testMarkdownRendererRendersGfmTable() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 項目 | 値 |
            | --- | --- |
            | A | 1 |
            | B | 2 |
            """
        )

        XCTAssertTrue(result.contains("yamabiko-table-wrap"))
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("<thead>"))
        XCTAssertTrue(result.contains("<tbody>"))
        XCTAssertTrue(result.contains("<th>項目</th>"))
        XCTAssertTrue(result.contains("<td>A</td>"))
    }

    func testMarkdownRendererConvertsBareURLToDomainLink() throws {
        let result = try renderMarkdownWithJavaScript(
            "参考: https://www.ankerjapan.com/blogs/magazine/example?source=chat"
        )

        XCTAssertTrue(result.contains("href=\"https://www.ankerjapan.com/blogs/magazine/example?source=chat\""))
        XCTAssertTrue(result.contains(">ankerjapan.com <"))
        XCTAssertTrue(result.contains("yamabiko-external-arrow"))
        XCTAssertTrue(result.contains(">↗</span>"))
        XCTAssertFalse(result.contains(">https://www.ankerjapan.com"))
    }

    func testMarkdownRendererPreservesEncodedURLAndExcludesTrailingPunctuation() throws {
        let result = try renderMarkdownWithJavaScript(
            "参照（https://pick-navi.com/ranking/%E3%83%A2%E3%83%90%E3%82%A4%E3%83%AB）。"
        )

        XCTAssertTrue(result.contains("href=\"https://pick-navi.com/ranking/%E3%83%A2%E3%83%90%E3%82%A4%E3%83%AB\""))
        XCTAssertTrue(result.contains(">pick-navi.com <"))
        XCTAssertTrue(result.contains("</a>）。"))
    }

    func testMarkdownRendererKeepsBalancedClosingParenthesisInBareURL() throws {
        let result = try renderMarkdownWithJavaScript(
            "https://example.com/wiki/Swift_(programming_language)"
        )

        XCTAssertTrue(result.contains("href=\"https://example.com/wiki/Swift_(programming_language)\""))
    }

    func testMarkdownRendererKeepsMarkdownLinkLabelAndAddsExternalIndicator() throws {
        let result = try renderMarkdownWithJavaScript("[公式サイト](https://example.com/path)")

        XCTAssertTrue(result.contains("href=\"https://example.com/path\""))
        XCTAssertTrue(result.contains(">公式サイト <"))
        XCTAssertTrue(result.contains(">↗</span>"))
        XCTAssertFalse(result.contains(">example.com <"))
    }

    func testMarkdownRendererDoesNotDuplicateExistingExternalIndicator() throws {
        let result = try renderMarkdownWithJavaScript("[公式サイト ↗](https://example.com/path)")

        XCTAssertEqual(result.components(separatedBy: "↗").count - 1, 1)
    }

    func testMarkdownRendererDoesNotAutoLinkCodeMathOrUnsafeScheme() throws {
        let result = try renderMarkdownWithJavaScript(
            "`https://code.example/path` と $https://math.example/x$ と javascript:alert(1)"
        )

        XCTAssertTrue(result.contains("<code>https://code.example/path</code>"))
        XCTAssertTrue(result.contains("$https://math.example/x$"))
        XCTAssertTrue(result.contains("javascript:alert(1)"))
        XCTAssertFalse(result.contains("href="))
    }

    func testMarkdownRendererAutoLinksBareURLInsideTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | サイト | URL |
            | --- | --- |
            | Example | https://www.example.com/very/long/path |
            """
        )

        XCTAssertTrue(result.contains("<td>Example</td>"))
        XCTAssertTrue(result.contains("href=\"https://www.example.com/very/long/path\""))
        XCTAssertTrue(result.contains(">example.com <"))
    }

    func testMarkdownRendererAppliesTableAlignment() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | L | C | R |
            | :--- | :---: | ---: |
            | a | b | c |
            """
        )

        XCTAssertTrue(result.contains("text-align: left;"))
        XCTAssertTrue(result.contains("text-align: center;"))
        XCTAssertTrue(result.contains("text-align: right;"))
    }

    func testMarkdownRendererPreservesBrInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 説明 |
            | --- |
            | 1行目<br>2行目 |
            """
        )

        XCTAssertTrue(result.contains("<td>1行目<br/>2行目</td>"))
    }

    func testMarkdownRendererEscapesUnsafeHtmlInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 説明 |
            | --- |
            | <script>alert(1)</script> |
            """
        )

        XCTAssertTrue(result.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(result.contains("<script>alert(1)</script>"))
    }

    func testMarkdownRendererPreservesMathTokensInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 式 |
            | --- |
            | $a_c = v^2/r$ |
            """
        )

        XCTAssertTrue(result.contains("yamabiko-table-wrap"))
        XCTAssertTrue(result.contains("$a_c = v^2/r$"))
        XCTAssertFalse(result.contains("&amp;"))
    }

    func testMarkdownRendererPreservesMathWithSpecialCharacters() throws {
        let result = try renderMarkdownWithJavaScript("本文 $a < b$ と $c & d$")

        XCTAssertTrue(result.contains("$a &lt; b$"))
        XCTAssertTrue(result.contains("$c &amp; d$"))
        XCTAssertFalse(result.contains("$a < b$"))
    }

    func testMarkdownRendererEscapesExecutableMarkupInsideMath() throws {
        let payloads = [
            #"$<img src=x onerror=alert(1)>$"#,
            #"$$<svg onload=alert(1)></svg>$$"#,
            #"\(<math href=\"javascript:alert(1)\">x</math>\)"#,
            #"\[<a href=\"data:text/html,boom\">x</a>\]"#
        ]

        for payload in payloads {
            let result = try renderMarkdownWithJavaScript(payload)
            XCTAssertFalse(result.contains("<img"), payload)
            XCTAssertFalse(result.contains("<svg"), payload)
            XCTAssertFalse(result.contains("<math"), payload)
            XCTAssertFalse(result.contains("<a "), payload)
            XCTAssertTrue(result.contains("&lt;"), payload)
        }
    }

    func testMarkdownRendererDoesNotParseInvalidTableDelimiter() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | a | b |
            | nope | nope |
            """
        )

        XCTAssertFalse(result.contains("<table>"))
        XCTAssertTrue(result.contains("<p>| a | b | | nope | nope |</p>"))
    }

    func testDisplayMathWithBlankLinesStaysInOneTextNode() throws {
        for equation in [#"\["# + "\n\nx^2 < y\n\n" + #"\]"#, "$$\n\nx^2 < y\n\n$$"] {
            let html = try renderMarkdownWithJavaScript(equation)
            XCTAssertEqual(html, "<p>" + equation.replacingOccurrences(of: "<", with: "&lt;") + "</p>")
        }
    }

    func testInlineCodeKeepsLiteralMathWhenOtherMathIsPresent() throws {
        let html = try renderMarkdownWithJavaScript(#"`$x$` と \(y\)"#)
        XCTAssertTrue(html.contains("<code>$x$</code>"), html)
        XCTAssertFalse(html.contains("<code>@@"), html)
    }

    func testTableDoesNotSplitPipesInsideMathOrInlineCode() throws {
        for value in [#"$|x|$"#, #"\(\left|x\right|\)"#, "`a|b`"] {
            let html = try renderMarkdownWithJavaScript("| 式 | 説明 |\n| --- | --- |\n| " + value + " | 絶対値 |")
            XCTAssertTrue(html.contains("<td>絶対値</td>"), html)
            if value.hasPrefix("`") {
                XCTAssertTrue(html.contains("<code>a|b</code>"), html)
            } else {
                XCTAssertTrue(html.contains(value), html)
            }
        }
    }

    func testNormalizationPreservesMatrixRowsStartingWithNRT() {
        for row in ["n", "r", "t", "[2pt]n", #"\theta"#, #"\text{値}"#] {
            for delimiters in [(#"\["#, #"\]"#), ("$$", "$$"), ("$", "$"), (#"\("#, #"\)"#)] {
                let source = delimiters.0 + #"\begin{matrix}a\\"# + row + #"\end{matrix}"# + delimiters.1
                XCTAssertEqual(MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(source), source)
            }
        }
    }

    @MainActor
    func testMathInHeadingsTablesAndBlockquotesRendersInNativeMessageView() async throws {
        let source = #"""
        ### 三平方の定理 \(a^2+b^2=c^2\)

        | 式 | 説明 |
        | --- | --- |
        | $|x|$ | 絶対値 |
        | \(\frac{a}{b}\) | 分数 |

        > 行列の等式：
        > \[
        > \begin{pmatrix}a\\n\end{pmatrix}
        > =
        > \begin{pmatrix}a\\n\end{pmatrix}
        > \]
        """#
        try await assertMathRenders(source, expectedEquationCount: 4, usesNativeView: true)
    }

    private func loadMarkdownRendererSource() throws -> String {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let rendererURL = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("YamabikoChat")
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent("mathjax")
            .appendingPathComponent("markdown-renderer.js")

        return try String(contentsOf: rendererURL, encoding: .utf8)
    }

    private func renderMarkdownWithJavaScript(_ input: String) throws -> String {
        let script = try loadMarkdownRendererSource()
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return ""
        }

        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        context.evaluateScript("var window = this;")
        context.evaluateScript(script)
        if let jsError {
            XCTFail("Renderer script evaluation failed: \(jsError)")
        }

        guard let renderer = context.objectForKeyedSubscript("yamabikoRenderMarkdown") else {
            XCTFail("Renderer function was not registered")
            return ""
        }

        let output = renderer.call(withArguments: [input])?.toString() ?? ""
        if let jsError {
            XCTFail("Renderer function failed: \(jsError)")
        }
        return output
    }

}
