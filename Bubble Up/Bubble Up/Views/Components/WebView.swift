import SwiftUI
import WebKit

/// WKWebView wrapper for displaying full article content.
struct WebView: UIViewRepresentable {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let isDark = colorScheme == .dark
        let textColor = isDark ? "#f5f4f0" : "#1a1a1a"
        let bgColor = isDark ? "#211311" : "#f5f4f0"
        let linkColor = "#da2d16"

        let bgUIColor = isDark
            ? UIColor(BubbleUpTheme.backgroundDark)
            : UIColor(BubbleUpTheme.background)
        webView.backgroundColor = bgUIColor
        webView.scrollView.backgroundColor = bgUIColor

        let css = """
        body {
            font-family: 'New York', Georgia, serif;
            font-size: 17px;
            line-height: 1.6;
            color: \(textColor);
            background-color: \(bgColor);
            padding: 0 16px;
            max-width: 680px;
            margin: 0 auto;
        }
        h1, h2, h3 {
            font-family: 'New York', Georgia, serif;
        }
        blockquote {
            border-left: 3px solid \(linkColor);
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
        a { color: \(linkColor); }
        """

        let script = """
        var existingStyle = document.getElementById('bubble-up-css');
        if (existingStyle) existingStyle.remove();
        var style = document.createElement('style');
        style.id = 'bubble-up-css';
        style.textContent = `\(css)`;
        document.head.appendChild(style);
        """

        webView.evaluateJavaScript(script)

        let request = URLRequest(url: url)
        webView.load(request)
    }
}
