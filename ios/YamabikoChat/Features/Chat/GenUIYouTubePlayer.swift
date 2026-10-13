import SwiftUI
import WebKit

/// Isolated media player: no GenUI, CEL or application action message handlers.
final class GenUIYouTubePlayer: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var onEvent: ((String, Int?) -> Void)?

    init(videoID: String, title: String, poster: Bool = false) {
        let configuration = YamabikoWebKitSupport.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "videoEvent")
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.isUserInteractionEnabled = !poster
        let identifier = Bundle.main.bundleIdentifier ?? "com.porarri.yamabikochat.ios"
        let baseURL = URL(string: "https://\(identifier)")!
        // Google documents the app Bundle ID as the WebView embedding identity:
        // https://developers.google.com/youtube/terms/required-minimum-functionality#embedded-player-api-client-identity
        let encodedID = String(data: try! JSONEncoder().encode(videoID), encoding: .utf8)!
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style></head><body><div id="player"></div><script src="https://www.youtube.com/iframe_api"></script><script>
        let player;
        function send(type,value){window.webkit.messageHandlers.videoEvent.postMessage({type,value});}
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{host:'https://www.youtube-nocookie.com',videoId:\(encodedID),playerVars:{playsinline:1,controls:\(poster ? 0 : 1),origin:'\(baseURL.absoluteString)'},events:{onReady:()=>send('ready',null),onStateChange:event=>send('state',event.data),onError:event=>send('error',event.data)}});}
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: baseURL)
        webView.accessibilityLabel = title
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? [String: Any],
              let type = value["type"] as? String, ["ready", "state", "error"].contains(type) else { return }
        if type == "error" {
            DiagnosticsLogger.log("GenUI YouTube player error", category: .app, metadata: ["code": String(describing: value["value"] ?? "unknown")])
        }
        onEvent?(type, value["value"] as? Int)
    }

    func remove() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "videoEvent")
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}

struct GenUIVideoPresentation: Identifiable {
    let id = UUID()
    let videoID: String
    let title: String
}

struct GenUIVideoPresentationView: UIViewRepresentable {
    let presentation: GenUIVideoPresentation
    func makeCoordinator() -> GenUIYouTubePlayer {
        GenUIYouTubePlayer(videoID: presentation.videoID, title: presentation.title)
    }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: GenUIYouTubePlayer) { coordinator.remove() }
}
