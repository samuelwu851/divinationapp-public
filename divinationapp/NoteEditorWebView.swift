import SwiftUI
import WebKit
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
#endif

/// 网页编辑器（NoteEditor/ 下的 TipTap）的控制器：NoteEditorView 持有它。
///
/// 网页 ↔ Swift 的约定：
/// - Swift → 网页：`noteEditor.init({...})` 载入正文；`noteEditor.getJSON()` 取正文；`noteEditor.insertChart(id)` 插卡片。
/// - 网页 → Swift：
///   - `bridge`（有返回值）：网页要调后端（取排盘、存图片），Swift 转发给 Python，只放行白名单命令。
///   - `notify`（无返回值）：ready / changed / openChart 事件。
/// - 沙盒 App 里 WKWebView 需要「Outgoing Connections (Client)」权限才能加载页面（WebKit 的子进程要用），
///   即使内容全是本地的；编辑器本身不联网，导航只放行 noteeditor://。
/// - 页面和图片都走自定义网址 `noteeditor://`：app/ 下是编辑器文件，asset/ 下是笔记图片。
@MainActor
final class NoteEditorController: NSObject {
    private(set) var webView: WKWebView?
    private let client = DivinationClient()

    private var noteId = 0
    private var initialContent = ""
    private var ready = false

    var onChange: () -> Void = {}
    var onOpenChart: (Int) -> Void = { _ in }

    /// 网页可以调用的后端命令（白名单）。
    private let allowedCommands: Set<String> = ["chart_get", "attachment_add"]

    /// 设定要编辑的笔记；页面已就绪就立刻载入。
    func load(noteId: Int, content: String) {
        self.noteId = noteId
        self.initialContent = content
        if ready { pushContent() }
    }

    /// 当前正文 JSON（保存时取）。
    func currentJSON() async -> String? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript("window.noteEditor.getJSON()") as? String
    }

    /// 光标是否在正文里（插入排盘前检查）。
    func cursorInBody() async -> Bool {
        guard let webView, ready else { return false }
        return (try? await webView.evaluateJavaScript("window.noteEditor.cursorInBody()") as? Bool) ?? false
    }

    /// 在光标处插入排盘卡片。
    func insertChart(id: Int) {
        webView?.evaluateJavaScript("window.noteEditor.insertChart(\(id))")
    }

    // MARK: - 创建 WebView

    func makeWebView() -> WKWebView {
        if let webView { return webView }

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(NoteEditorSchemeHandler(), forURLScheme: NoteEditorSchemeHandler.scheme)
        let ucc = config.userContentController
        let proxy = MessageProxy(owner: self)          // 中间人：避免 userContentController 强引用控制器
        ucc.addScriptMessageHandler(proxy, contentWorld: .page, name: "bridge")
        ucc.add(proxy, name: "notify")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        #if os(macOS)
        wv.setValue(false, forKey: "drawsBackground")  // 透明，透出 SwiftUI 的纸纹背景
        #else
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        #endif
        #if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) { wv.isInspectable = true }   // Safari「开发」菜单可调试
        #endif
        wv.load(URLRequest(url: URL(string: "\(NoteEditorSchemeHandler.scheme)://app/note-editor.html")!))
        webView = wv
        return wv
    }

    /// 页面销毁时拆掉消息处理器。
    func tearDown() {
        let ucc = webView?.configuration.userContentController
        ucc?.removeScriptMessageHandler(forName: "bridge", contentWorld: .page)
        ucc?.removeScriptMessageHandler(forName: "notify")
        webView = nil
        ready = false
    }

    // MARK: - 网页 → Swift

    fileprivate func handleNotify(_ body: Any) {
        guard let msg = body as? [String: Any], let event = msg["event"] as? String else { return }
        switch event {
        case "ready":
            ready = true
            pushContent()
        case "changed":
            onChange()
        case "openChart":
            if let id = msg["id"] as? Int { onOpenChart(id) }
        default:
            break
        }
    }

    fileprivate func handleBridge(_ body: Any) -> (Any?, String?) {
        guard let msg = body as? [String: Any], let cmd = msg["cmd"] as? String else {
            return (nil, "请求格式不对")
        }
        guard allowedCommands.contains(cmd) else { return (nil, "不允许的命令：\(cmd)") }
        var params = msg["params"] as? [String: Any] ?? [:]
        if cmd == "attachment_add" { params["note_id"] = noteId }   // 只能往当前笔记里存图片
        guard let json = client.dispatchRaw(cmd: cmd, params: params) else { return (nil, "后端无响应") }
        return (json, nil)
    }

    private func pushContent() {
        let payload: [String: Any] = [
            "noteId": noteId,
            "content": initialContent,
            "accent": Self.accentHex(),
            "assetBase": "\(NoteEditorSchemeHandler.scheme)://asset/",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.noteEditor.init(\(json))")
    }

    /// 系统强调色 → #RRGGBB，让网页里的按钮颜色和 SwiftUI 一致。
    private static func accentHex() -> String {
        let c = Color.accentColor.resolve(in: EnvironmentValues())
        func h(_ v: Float) -> String { String(format: "%02x", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#" + h(c.red) + h(c.green) + h(c.blue)
    }
}

// MARK: - 导航：只允许编辑器自己的页面

extension NoteEditorController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == NoteEditorSchemeHandler.scheme ? .allow : .cancel
    }

    #if os(macOS)
    /// macOS 上 <input type=file> 需要宿主自己弹文件选择框。
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.urls : nil
    }
    #endif
}

/// 消息中间人：WKUserContentController 会强引用消息处理器，用它弱引用控制器，避免循环引用。
private final class MessageProxy: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    weak var owner: NoteEditorController?
    init(owner: NoteEditorController) { self.owner = owner }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.handleNotify(message.body) }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        MainActor.assumeIsolated {
            let (result, error) = owner?.handleBridge(message.body) ?? (nil, "编辑器已关闭")
            replyHandler(result, error)
        }
    }
}

// MARK: - noteeditor:// 网址

/// - `noteeditor://app/<文件>`：App 包里的编辑器文件（html / mjs）
/// - `noteeditor://asset/<文件名>`：案例库图片文件夹里的图片
final class NoteEditorSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "noteeditor"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let data = Self.load(url) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": Self.mimeType(url.pathExtension),
                                                      "Content-Length": "\(data.count)",
                                                      "Access-Control-Allow-Origin": "*"])!   // ES 模块按跨域规则加载
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func load(_ url: URL) -> Data? {
        let name = url.lastPathComponent                 // 只取文件名，防止 ../ 跳出目录
        guard !name.isEmpty, name != "/" else { return nil }
        switch url.host {
        case "app":
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let file = Bundle.main.url(forResource: base, withExtension: ext)
                ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "NoteEditor")
            return file.flatMap { try? Data(contentsOf: $0) }
        case "asset":
            guard let dir = CasebookPaths.attachmentsDir else { return nil }
            return try? Data(contentsOf: dir.appendingPathComponent(name))
        default:
            return nil
        }
    }

    private static func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "mjs", "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "bmp": return "image/bmp"
        case "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - SwiftUI 包装

#if os(macOS)
struct NoteEditorWebView: NSViewRepresentable {
    let controller: NoteEditorController
    func makeNSView(context: Context) -> WKWebView { controller.makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct NoteEditorWebView: UIViewRepresentable {
    let controller: NoteEditorController
    func makeUIView(context: Context) -> WKWebView { controller.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
