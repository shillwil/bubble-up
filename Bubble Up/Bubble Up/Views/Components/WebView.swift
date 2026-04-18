import SwiftUI
import WebKit

/// WKWebView wrapper for displaying full article content.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(BubbleUpTheme.background)
        webView.scrollView.backgroundColor = UIColor(BubbleUpTheme.background)

        // Inject editorial CSS
        let css = """
        body {
            font-family: 'New York', Georgia, serif;
            font-size: 17px;
            line-height: 1.6;
            color: #1a1a1a;
            background-color: #f5f4f0;
            padding: 0 16px;
            max-width: 680px;
            margin: 0 auto;
        }
        h1, h2, h3 {
            font-family: 'New York', Georgia, serif;
        }
        blockquote {
            border-left: 3px solid #da2d16;
            padding-left: 20px;
            font-style: italic;
            font-size: 20px;
            margin: 24px 0;
        }
        img {
            max-width: 100%;
            height: auto;
            border-radius: 2px;
        }
        a { color: #da2d16; }
        """

        let script = WKUserScript(
            source: """
            var style = document.createElement('style');
            style.textContent = `\(css)`;
            document.head.appendChild(style);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
