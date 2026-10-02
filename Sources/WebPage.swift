import SwiftUI
import WebKit

struct WebDestination: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    var login = false
}

struct WebPage: View {
    let destination: WebDestination
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    var body: some View {
        NavigationStack {
            WebsiteView(path: destination.path)
                .navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { Task { await store.bootstrap(showLoading: false); dismiss() } } }
                    if destination.login {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(checking ? "检查中…" : "已登录") {
                                Task {
                                    checking = true; await store.bootstrap(showLoading: false); checking = false
                                    if store.phase == .ready { dismiss() }
                                }
                            }.disabled(checking)
                        }
                    }
                }
        }
        .task { await store.client.exportWebCookies() }
    }
}

struct WebsiteView: UIViewRepresentable {
    let path: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.ignoresViewportScaleLimits = false
        let script = """
        (()=>{function apply(){if(!document.head)return;let m=document.querySelector('meta[name=viewport]');if(!m){m=document.createElement('meta');m.name='viewport';document.head.append(m)}m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover'}document.addEventListener('DOMContentLoaded',apply);apply()})();
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.load(URLRequest(url: Client.origin.appendingPathComponent(path)))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil { webView.load(action.request) }
            return nil
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "vrcrp", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            guard let host = webView.window?.rootViewController else { completionHandler(); return }
            var top = host; while let next = top.presentedViewController { top = next }
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "vrcrp", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            guard let host = webView.window?.rootViewController else { completionHandler(false); return }
            var top = host; while let next = top.presentedViewController { top = next }
            top.present(alert, animated: true)
        }
    }
}
