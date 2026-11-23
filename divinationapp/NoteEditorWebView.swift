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

    /// 卡片的五行颜色（和点开的排盘窗口共用一个设置）。
    var wuxingColor = false

    var onChange: () -> Void = {}
    var onOpenChart: (Int) -> Void = { _ in }
    var onLabelDeleted: (Int) -> Void = { _ in }
    /// 页面滚动了多少（点）：宿主据此把顶上的标题 / 案主 / 标签 / 术数一起往上挪。
    var onScroll: (CGFloat) -> Void = { _ in }

    /// 页面顶上要留多高的空白（宿主盖在上面的那一块有多高）。
    private var topInset: CGFloat = 0

    /// 最近一次在图片上右键：哪张图、现在怎么对齐（网页在 contextmenu 事件里告诉我们，菜单弹出前就到）。
    fileprivate struct ImageContext { let src: String; let align: String; let alt: String; let time: Date }
    fileprivate var imageContext: ImageContext?
    fileprivate var currentImage: ImageContext?     // 正在弹的图片菜单是针对哪张图

    /// 网页可以调用的后端命令（白名单）。
    private let allowedCommands: Set<String> = [
        "chart_get", "attachment_add",
        "label_search", "label_delete", "chart_label_add", "chart_label_remove",   // 排盘卡片旁的标签
    ]

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

    /// 五行颜色开关变了（在排盘窗口里勾选）：卡片跟着变。
    func setWuxingColor(_ on: Bool) {
        wuxingColor = on
        webView?.evaluateJavaScript("window.noteEditor.setWuxingColor(\(on))")
    }

    /// 宿主顶上那一块（标题、案主、标签、术数）的高度变了：页面顶上留同样高的空白。
    func setTopInset(_ h: CGFloat) {
        guard abs(h - topInset) > 0.5 else { return }
        topInset = h
        if ready { webView?.evaluateJavaScript("window.noteEditor.setTopInset(\(h))") }
    }

    /// 在笔记里查找（⌘F）：打开网页里的查找框。
    func openFind() {
        webView?.evaluateJavaScript("window.noteEditor.openFind()")
    }

    /// 排盘窗口里改了所问之事 / 特点：正文里这个排盘的卡片重新画。
    func refreshChart(id: Int) {
        webView?.evaluateJavaScript("window.noteEditor.refreshChart(\(id))")
    }

    /// 某个标签被彻底删除了：让网页里的排盘卡片也去掉它。
    func labelDeleted(id: Int) {
        webView?.evaluateJavaScript("window.noteEditor.labelDeleted(\(id))")
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

        #if os(macOS)
        let wv = NoteWebView(frame: .zero, configuration: config)
        wv.controller = self                           // 右键点图片时换成图片专用菜单
        #else
        let wv = WKWebView(frame: .zero, configuration: config)
        #endif
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
            webView?.evaluateJavaScript("window.noteEditor.setTopInset(\(topInset))")
            pushContent()
        case "imageContext":
            if let src = msg["src"] as? String {
                imageContext = ImageContext(src: src, align: msg["align"] as? String ?? "left",
                                            alt: msg["alt"] as? String ?? "", time: Date())
            }
        case "scroll":
            if let y = (msg["y"] as? NSNumber)?.doubleValue { onScroll(CGFloat(y)) }
        case "changed":
            onChange()
        case "openChart":
            if let id = msg["id"] as? Int { onOpenChart(id) }
        case "labelDeleted":
            if let id = msg["id"] as? Int { onLabelDeleted(id) }
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
            "wuxingColor": wuxingColor,
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

#if os(macOS)
// MARK: - 图片右键菜单（macOS 原生菜单）

/// 编辑器用的 WKWebView：右键点在图片上时，把系统默认菜单换成我们的图片菜单。
final class NoteWebView: WKWebView {
    weak var controller: NoteEditorController?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        controller?.customizeMenu(menu)
    }
}

extension NoteEditorController {
    /// 刚才是在图片上右键（网页 0.8 秒内告诉过我们）→ 换成：左对齐 / 居中 / 右对齐 | 复制 / 粘贴 | 裁剪 / 另存为…
    fileprivate func customizeMenu(_ menu: NSMenu) {
        guard let ctx = imageContext, Date().timeIntervalSince(ctx.time) < 0.8 else { return }
        imageContext = ImageContext(src: ctx.src, align: ctx.align, alt: ctx.alt, time: .distantPast)   // 用过就作废，下次右键别处不受影响
        currentImage = ctx
        menu.removeAllItems()
        menu.autoenablesItems = false

        func item(_ title: String, _ action: Selector, key: String = "", on: Bool = false, enabled: Bool = true) {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            it.state = on ? .on : .off
            it.isEnabled = enabled
            menu.addItem(it)
        }
        item("左对齐", #selector(menuAlignLeft), on: ctx.align == "left")
        item("居中", #selector(menuAlignCenter), on: ctx.align == "center")
        item("右对齐", #selector(menuAlignRight), on: ctx.align == "right")
        menu.addItem(.separator())
        item("复制", #selector(menuCopy))
        item("粘贴（替换这张图）", #selector(menuPaste), enabled: Self.pasteboardHasImage())
        menu.addItem(.separator())
        item("裁剪", #selector(menuCrop))
        item("另存为…", #selector(menuSaveAs))
    }

    @objc private func menuAlignLeft() { webView?.evaluateJavaScript("window.noteEditor.imageAlign('left')") }
    @objc private func menuAlignCenter() { webView?.evaluateJavaScript("window.noteEditor.imageAlign('center')") }
    @objc private func menuAlignRight() { webView?.evaluateJavaScript("window.noteEditor.imageAlign('right')") }
    @objc private func menuCrop() { webView?.evaluateJavaScript("window.noteEditor.cropContextImage()") }

    /// 复制：把图片放进系统剪贴板（可以粘到别的 App）。
    @objc private func menuCopy() {
        guard let url = currentImageFile(), let image = NSImage(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    /// 粘贴：剪贴板里的图片存进 App，替换这张图（宽度、对齐不变）。
    @objc private func menuPaste() {
        guard let (data, name) = Self.pasteboardImage() else { return }
        let params: [String: Any] = ["note_id": noteId, "data": data.base64EncodedString(), "original_name": name]
        guard let json = client.dispatchRaw(cmd: "attachment_add", params: params),
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let src = obj["src"] as? String else { return }
        let args = (try? JSONSerialization.data(withJSONObject: [src, name])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        webView?.evaluateJavaScript("window.noteEditor.replaceContextImage(...\(args))")
    }

    /// 另存为：把原图文件（不是缩放后的）存到用户选的位置。
    @objc private func menuSaveAs() {
        guard let url = currentImageFile() else { return }
        let panel = NSSavePanel()
        let ext = url.pathExtension
        let alt = currentImage?.alt ?? ""
        let base = alt.isEmpty ? "图片" : (alt as NSString).deletingPathExtension
        panel.nameFieldStringValue = ext.isEmpty ? base : "\(base).\(ext)"
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        let save = { (dest: URL) in
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        if let window = webView?.window {
            panel.beginSheetModal(for: window) { resp in if resp == .OK, let dest = panel.url { save(dest) } }
        } else if panel.runModal() == .OK, let dest = panel.url {
            save(dest)
        }
    }

    /// 右键点中的那张图在磁盘上的文件（attachment:文件名 → 图片文件夹里的文件）。
    private func currentImageFile() -> URL? {
        guard let src = currentImage?.src, src.hasPrefix("attachment:"),
              let dir = CasebookPaths.attachmentsDir else { return nil }
        let name = String(src.dropFirst("attachment:".count))
        guard !name.contains("/") else { return nil }
        return dir.appendingPathComponent(name)
    }

    private static func pasteboardHasImage() -> Bool {
        let pb = NSPasteboard.general
        return pb.canReadObject(forClasses: [NSImage.self], options: nil)
            || pb.canReadObject(forClasses: [NSURL.self],
                                options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]])
    }

    /// 剪贴板里的图片 → (文件数据, 文件名)。复制的是图片文件就用原文件（保留 JPEG 等格式），否则转成 PNG。
    private static func pasteboardImage() -> (Data, String)? {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true,
                                               .urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let url = urls.first, let data = try? Data(contentsOf: url) {
            return (data, url.lastPathComponent)
        }
        guard let image = pb.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, "粘贴.png")
    }
}
#endif

// MARK: - 导航：只允许编辑器自己的页面

extension NoteEditorController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.scheme == NoteEditorSchemeHandler.scheme ? .allow : .cancel
    }

    #if os(macOS)
    /// 网页里的 confirm()（删除标签前的确认）：WKWebView 不会自己弹框，要宿主用原生对话框显示。
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let parts = message.components(separatedBy: "\n")
        alert.messageText = parts.first ?? message
        alert.informativeText = parts.dropFirst().joined(separator: "\n")
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        if let window = webView.window {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

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
