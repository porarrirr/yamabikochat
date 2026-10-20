import SwiftUI
import WebKit
import XCTest
@testable import YamabikoChat

final class GenUIHostPolicyTests: XCTestCase {
    @MainActor
    func testRecycledCellReusesRenderedPageWithoutReloading() async throws {
        GenUIRenderCache.shared.removeAll()
        defer { GenUIRenderCache.shared.removeAll() }
        let document = GenUIDocument(title: "Retained canvas", code: "return DIL.h('text', {}, 'Already rendered');")
        let state = GenUIState(document: document)
        let host = richHost(state: state)
        let renderer = host.makeCoordinator()
        let canvas = renderer.makeCanvas()
        let webView = canvas.webView
        renderer.load(in: webView)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !webView.isLoading }, object: nil)
        await fulfillment(of: [finished], timeout: 15)
        let content = try await webView.evaluateJavaScript("document.getElementById('root').textContent") as? String
        XCTAssertEqual(content, "Already rendered")
        _ = try await webView.evaluateJavaScript("window.__scrollRetentionSentinel = 42")

        renderer.detach()
        XCTAssertNil(renderer.parent)
        let restored = richHost(state: state).makeCoordinator()
        XCTAssertTrue(restored === renderer)
        XCTAssertTrue(restored.makeWebView() === webView)
        restored.load(in: webView)
        XCTAssertFalse(webView.isLoading, "Returning to a rendered row must not start another navigation")
        let sentinel = try await webView.evaluateJavaScript("window.__scrollRetentionSentinel") as? Int
        XCTAssertEqual(sentinel, 42, "Keep the live DOM, rather than reconstructing it from saved inputs")
        restored.detach()
    }

    @MainActor
    func testDetachedRendererDoesNotRetainConversationState() {
        weak var releasedState: GenUIState?
        weak var releasedRenderer: GenUIRichWebView.Coordinator?
        autoreleasepool {
            let state = GenUIState(document: GenUIDocument(title: "Release", code: "return DIL.h('text', {}, 'Release');"))
            releasedState = state
            let renderer = richHost(state: state).makeCoordinator()
            releasedRenderer = renderer
            let webView = renderer.makeWebView()
            renderer.detach()
        }
        XCTAssertNil(releasedState)
        GenUIRenderCache.shared.removeAll()
        XCTAssertNil(releasedRenderer, "Script handlers must not form a WebKit retention cycle")
    }

    @MainActor
    func testDifferentCanvasesHaveIndependentRenderers() {
        defer { GenUIRenderCache.shared.removeAll() }
        let document = GenUIDocument(title: "Independent", code: "return DIL.h('text', {}, 'Canvas');")
        let first = richHost(state: GenUIState(document: document)).makeCoordinator()
        let second = richHost(state: GenUIState(document: document)).makeCoordinator()
        XCTAssertFalse(first.makeWebView() === second.makeWebView())
        first.detach()
        second.detach()
    }

    @MainActor
    func testOffscreenRendererCountStaysBoundedAcrossLongHistory() {
        let cache = GenUIRenderCache(rendererLimit: 2)
        let document = GenUIDocument(title: "History", code: "return DIL.h('text', {}, 'History');")
        weak var oldest: GenUIRichWebView.Coordinator?
        for index in 0..<100 {
            let renderer = GenUIRichWebView.Coordinator(parent: richHost(state: GenUIState(document: document)))
            renderer.parent = nil
            if index == 0 { oldest = renderer }
            cache.retainRenderer(renderer, for: UUID())
            XCTAssertLessThanOrEqual(cache.rendererCount, 2)
        }
        XCTAssertNil(oldest, "Eviction must release old renderers, not just remove their lookup keys")
    }

    @MainActor
    func testPreviewCacheEnforcesByteBudgetAndRecency() {
        let document = GenUIDocument(title: "Preview", code: "return DIL.h('text', {}, 'Preview');")
        let image = previewImage()
        let preview = GenUIRenderCache.Preview(image: image, document: document, dark: false, width: 320)
        let cache = GenUIRenderCache(previewByteLimit: preview.byteCount * 2)
        let first = UUID(), second = UUID(), third = UUID()
        cache.storePreview(preview, for: first)
        cache.storePreview(preview, for: second)
        XCTAssertNotNil(cache.preview(for: first))
        cache.storePreview(preview, for: third)
        XCTAssertNil(cache.preview(for: second))
        XCTAssertNotNil(cache.preview(for: first))
        XCTAssertEqual(cache.previewBytes, preview.byteCount * 2)
        for _ in 0..<100 { cache.storePreview(preview, for: UUID()) }
        XCTAssertLessThanOrEqual(cache.previewBytes, preview.byteCount * 2)
    }

    @MainActor
    func testColdCanvasShowsPreviewWhileRestoringSavedInputState() async throws {
        let cache = GenUIRenderCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        let document = GenUIDocument(title: "Restore", code: "const [count] = DIL.useState(3); return DIL.h('text', {}, String(count));")
        let state = GenUIState(document: document)
        state.richSnapshot = ["hooks": .array([.number(9)])]
        cache.storePreview(.init(image: previewImage(), document: document, dark: false, width: 320), for: state.renderCacheID)
        let renderer = richHost(state: state).makeCoordinator()
        let canvas = renderer.makeCanvas()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(canvas)
        canvas.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        window.isHidden = false
        defer { window.isHidden = true }
        renderer.load(in: canvas.webView)
        canvas.layoutIfNeeded()
        XCTAssertTrue(canvas.isShowingPreview)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !canvas.webView.isLoading && !canvas.isShowingPreview
        }, object: nil)
        await fulfillment(of: [finished], timeout: 15)
        let content = try await canvas.webView.evaluateJavaScript("document.getElementById('root').textContent") as? String
        XCTAssertEqual(content, "9", "Evicting WebKit must preserve the user's input state")
        let captured = try XCTUnwrap(cache.preview(for: state.renderCacheID)?.image.cgImage)
        XCTAssertGreaterThan(captured.height, 16, "Replace the cached placeholder with an actual WebKit snapshot")
        XCTAssertLessThanOrEqual(captured.width * captured.height, 605_000)
        renderer.detach()
    }

    @MainActor
    func testMemoryWarningClearsCachesWithoutDroppingVisibleRenderer() {
        let cache = GenUIRenderCache.shared
        cache.removeAll()
        let document = GenUIDocument(title: "Visible", code: "return DIL.h('text', {}, 'Visible');")
        let state = GenUIState(document: document)
        let renderer = richHost(state: state).makeCoordinator()
        let offscreen = GenUIRichWebView.Coordinator(parent: richHost(state: GenUIState(document: document)))
        offscreen.parent = nil
        cache.retainRenderer(offscreen, for: UUID())
        cache.storePreview(.init(image: previewImage(), document: document, dark: false, width: 320), for: UUID())
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(cache.rendererCount, 0)
        XCTAssertEqual(cache.previewBytes, 0)
        XCTAssertTrue(state.richRenderer === renderer)
        renderer.detach()
        cache.removeAll()
    }

    @MainActor
    func testSnapshotWorkIsSerializedAndLateCompletionCannotReleaseNewCapture() throws {
        let cache = GenUIRenderCache()
        let first = try XCTUnwrap(cache.beginPreviewCapture())
        XCTAssertNil(cache.beginPreviewCapture())
        XCTAssertTrue(cache.endPreviewCapture(first))
        let next = try XCTUnwrap(cache.beginPreviewCapture())
        XCTAssertFalse(cache.endPreviewCapture(first))
        XCTAssertNil(cache.beginPreviewCapture())
        XCTAssertTrue(cache.endPreviewCapture(next))
    }

    @MainActor
    private func previewImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    @MainActor
    private func richHost(state: GenUIState) -> GenUIRichWebView {
        GenUIRichWebView(document: state.document, state: state, dark: false,
                         height: Binding(get: { state.richHeight }, set: { state.richHeight = $0 }),
                         onStatus: { _ in }, onAction: { _ in })
    }

    func testFlowFixtureAndDeclarativeStageContract() throws {
        let document = GenUIDocument(title: "Flow", code: GenUIRichDemoFixture.flowCode)
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        XCTAssertEqual(try GenUIDocument.validated(from: json), document)
        XCTAssertNoThrow(try GenUIDocument.validated(from: #"{"title":"Flow","ui":{"type":"list","props":{"connector":true,"marker":"none"},"children":[{"type":"list-item","props":{"icon":"cpu","iconColor":"info","variant":"outline","label":"Compute"}}]}}"#))
        let properties = try XCTUnwrap(GenUIDocument.componentCatalog["list-item"])
        for property in ["icon", "iconColor", "variant"] {
            XCTAssertTrue(properties.contains(property))
            XCTAssertTrue(GenUITool.definition.description.contains("\"" + property + "\""))
        }
    }

    func testCodeValidationParsesWithoutExecutingTheBody() throws {
        XCTAssertThrowsError(try GenUICodeValidator.validate("return ("))
        XCTAssertNoThrow(try GenUICodeValidator.validate("throw new Error('must not execute');"))
    }

    func testExternalLinksRequireHTTPSWithoutEmbeddedCredentials() {
        XCTAssertNotNil(GenUIHostPolicy.externalURL("https://example.com/page"))
        for url in ["javascript:alert(1)", "file:///private/secret", "data:text/html,hello", "http://example.com", "https://user:password@example.com"] {
            XCTAssertNil(GenUIHostPolicy.externalURL(url))
        }
    }

    func testInteractionSnapshotsRequireJSONWithoutFixedByteLimit() {
        XCTAssertEqual(GenUIHostPolicy.snapshot(from: ["bindings": ["count": 3]])?["bindings"], .object(["count": .number(3)]))
        XCTAssertNil(GenUIHostPolicy.snapshot(from: ["value": Double.infinity]))
        let text = String(repeating: "資料", count: 100_000)
        XCTAssertEqual(GenUIHostPolicy.snapshot(from: ["value": text])?["value"], .string(text))
    }

    func testRichDemoUsesTheSameValidatedToolContract() throws {
        let document = GenUIDocument(title: "Demo", code: GenUIRichDemoFixture.code)
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        XCTAssertEqual(try GenUIDocument.validated(from: json), document)
    }
}
