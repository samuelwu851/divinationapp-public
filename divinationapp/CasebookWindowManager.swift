#if os(macOS)
import AppKit
import SwiftUI

/// 协调「排盘主窗」与「笔记窗」的磁吸贴合。
/// - 贴合时用 `addChildWindow` 建立父子关系：拖主窗，笔记窗**同步一起动**（无延迟）。
/// - 判断「笔记窗是被主窗带着走 还是 用户单独拖动」：比对两窗的**实时位移**——
///   位移一致＝被带着走（忽略）；主窗没动而笔记窗动了＝用户拖动。与通知先后无关，稳。
/// - 磁吸：脱离后把笔记窗拖到主窗**左/右**边缘很近处才吸上；吸上后拉回贴合位粘住，
///   拉得够远才松开。
final class CasebookWindowManager {
    static let shared = CasebookWindowManager()
    private init() {}

    enum Side { case left, right }

    private weak var main: NSWindow?
    private weak var notes: NSWindow?

    private var attached = false
    private var side: Side = .right
    private var syncing = false                  // 正在程序化移动笔记窗
    private var lastMainOrigin: CGPoint = .zero
    private var lastNotesOrigin: CGPoint = .zero
    private var tokens: [NSObjectProtocol] = []

    // 贴合时「放大」：主窗 + 笔记窗整体填满屏幕（而不是主窗填满、把笔记窗挤出屏幕）
    private var pairMaximized = false            // 现在是不是「整体填满」状态
    private var savedMainFrame: NSRect?          // 放大前主窗的位置大小（再双击时还原）
    private var stableMainFrame: NSRect?         // 主窗最近一次「停稳」的位置大小（放大动画中间的帧不算）
    private var stableWork: DispatchWorkItem?
    private var adjustingMain = false            // 正在程序化调整主窗，忽略它引起的通知
    private var zoomProxy: ZoomDelegateProxy?    // 让 macOS「缩放」直接放大到整体填满的大小（见 installZoomProxy）

    private let snapTrigger: CGFloat = 16         // 很贴近才吸附
    private let detachDist: CGFloat = 48          // 吸住后要拉这么远才松开
    private let defaultNotesWidth: CGFloat = 518

    func registerMain(_ w: NSWindow) {
        guard main !== w else { return }
        main = w
        stableMainFrame = w.frame
        observe(w, NSWindow.didResizeNotification) { [weak self] in self?.onMainResized() }
        observe(w, NSWindow.didMoveNotification) { [weak self] in self?.noteMainFrameChanged() }
        installZoomProxy(on: w)
        // SwiftUI 有可能换掉窗口的 delegate：窗口每次变成焦点时检查一下，被换掉就重新套上
        observe(w, NSWindow.didBecomeKeyNotification) { [weak self, weak w] in
            if let self, let w { self.installZoomProxy(on: w) }
        }
    }

    func registerNotes(_ w: NSWindow) {
        let firstTime = notes !== w
        notes = w
        w.isRestorable = false
        if firstTime {
            observe(w, NSWindow.didMoveNotification) { [weak self] in self?.onNotesMoved() }
            // 关掉笔记窗：解除贴合。SwiftUI 的窗口关掉后对象还在（只是隐藏），
            // 不解除的话，之后拉主窗 / 放大主窗时 attach 会把它当子窗口重新显示出来——看起来像「自己打开了」
            observe(w, NSWindow.willCloseNotification) { [weak self] in self?.notesClosed() }
        }
        attach(to: .right, initial: true)         // 首次出现贴右侧
    }

    private func observe(_ w: NSWindow, _ name: Notification.Name, _ fn: @escaping () -> Void) {
        tokens.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { _ in fn() })
    }

    // MARK: - 贴合 / 脱离

    private func flushX(for s: Side, width: CGFloat) -> CGFloat {
        guard let m = main else { return 0 }
        return s == .right ? m.frame.maxX : m.frame.minX - width
    }

    /// 把笔记窗设到主窗某侧、等高，并建立父子关系（一起动）。也用于「吸住后拉回」。
    /// 笔记窗现在是不是开着（关掉的窗口对象还在，只是不显示）。
    private var notesVisible: Bool { notes?.isVisible == true }

    private func notesClosed() {
        detach()
        pairMaximized = false
    }

    private func attach(to s: Side, initial: Bool = false) {
        guard let m = main, let n = notes, initial || n.isVisible else { return }   // 关着的笔记窗不去碰它
        side = s
        let width = initial ? defaultNotesWidth : n.frame.width
        let target = NSRect(x: flushX(for: s, width: width), y: m.frame.origin.y,
                            width: width, height: m.frame.height)
        syncing = true
        n.setFrame(target, display: true)
        if n.parent !== m {
            n.parent?.removeChildWindow(n)
            m.addChildWindow(n, ordered: .above)
        }
        syncing = false
        attached = true
    }

    private func detach() {
        guard let n = notes else { attached = false; return }
        n.parent?.removeChildWindow(n)
        attached = false
    }

    // MARK: - 事件

    private func onMainResized() {
        if adjustingMain { return }               // 自己调的，setMain 里会处理
        noteMainFrameChanged()
        guard attached, notesVisible, let m = main, let n = notes, let vf = m.screen?.visibleFrame else {
            if attached && notesVisible { attach(to: side) }
            return
        }
        // 主窗被放大到填满屏幕（双击标题栏「缩放」或「填充」、绿色按钮的缩放）：
        // 贴着笔记窗时改成两个窗整体填满；已经是整体填满时再放大 = 还原。
        if isFull(m.frame, vf) {
            if pairMaximized {
                pairMaximized = false
                setMain(savedMainFrame ?? defaultRestoreFrame(vf))
            } else {
                savedMainFrame = stableMainFrame
                pairMaximized = true
                setMain(pairFrame(vf, notesWidth: n.frame.width))
            }
            return
        }
        attach(to: side)        // childWindow 只跟随平移、不跟随缩放 → 重新齐边、等高
    }

    /// 一步到位的放大：macOS 执行「缩放」（双击标题栏、Option+绿色按钮）前，会问窗口的 delegate
    /// 「放大后应该多大」（windowWillUseStandardFrame）。贴着笔记窗时回答「整体填满」的大小，
    /// 主窗就直接放大到位，不会先填满屏幕再缩回来；再双击时 macOS 自己会还原。
    ///
    /// delegate 原本是 SwiftUI 的，不能直接换掉：用一个代理套在外面，只接管这一个问题，
    /// 其他所有消息原样转给 SwiftUI。
    /// 注意：系统设置里「双击标题栏」选「填充」时 macOS 不问 delegate，走上面 onMainResized 的兜底（先满屏再缩）。
    private func installZoomProxy(on w: NSWindow) {
        if let proxy = zoomProxy, w.delegate === proxy { return }
        let proxy = ZoomDelegateProxy(original: w.delegate) { [weak self] _, _ in
            guard let self, self.attached, self.notesVisible, let n = self.notes,
                  let vf = self.main?.screen?.visibleFrame else { return nil }   // 笔记窗关着：照常放大主窗
            return self.pairFrame(vf, notesWidth: n.frame.width)
        }
        zoomProxy = proxy                         // window.delegate 是 weak，要自己留着
        w.delegate = proxy
    }

    /// 主窗的位置大小变了：等它停稳 0.35 秒再记下来（放大 / 还原有动画，中间的帧不能当成「放大前」）。
    /// 停稳后的大小不是「整体填满」的样子 → 说明用户自己拖过了，退出整体填满状态。
    private func noteMainFrameChanged() {
        if adjustingMain { return }
        stableWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let m = self.main, let vf = m.screen?.visibleFrame else { return }
            if self.isFull(m.frame, vf) { return }
            if self.pairMaximized, let n = self.notes,
               m.frame.equalTo(self.pairFrame(vf, notesWidth: n.frame.width)) { return }
            self.pairMaximized = false
            self.stableMainFrame = m.frame
        }
        stableWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 两个窗整体填满屏幕时，主窗的位置大小（笔记窗在哪边，就从那边让出它的宽度）。
    private func pairFrame(_ vf: NSRect, notesWidth: CGFloat) -> NSRect {
        let w = max(vf.width - notesWidth, 300)
        let x = side == .right ? vf.minX : vf.maxX - w
        return NSRect(x: x, y: vf.minY, width: w, height: vf.height)
    }

    /// 找不到放大前的大小时（理论上不会）：回到默认大小、居中。
    private func defaultRestoreFrame(_ vf: NSRect) -> NSRect {
        NSRect(x: vf.midX - 312, y: vf.midY - 390, width: 625, height: 780)
    }

    private func isFull(_ f: NSRect, _ vf: NSRect) -> Bool {
        abs(f.width - vf.width) < 2 && abs(f.height - vf.height) < 2
    }

    /// 程序化设定主窗大小（带动画），然后让笔记窗重新贴齐、等高。
    private func setMain(_ frame: NSRect) {
        guard let m = main else { return }
        adjustingMain = true
        m.setFrame(frame, display: true, animate: true)
        adjustingMain = false
        if attached { attach(to: side) }
    }

    private func onNotesMoved() {
        guard let m = main, let n = notes else { return }

        // 记录并比对两窗实时位移
        let mo = m.frame.origin, no = n.frame.origin
        let mdx = mo.x - lastMainOrigin.x, mdy = mo.y - lastMainOrigin.y
        let ndx = no.x - lastNotesOrigin.x, ndy = no.y - lastNotesOrigin.y
        lastMainOrigin = mo; lastNotesOrigin = no

        if syncing { return }                     // 程序化移动，忽略

        // 两窗位移一致且确实动了 → 是被主窗带着走，正常跟随
        let movedTogether = abs(mdx - ndx) < 1 && abs(mdy - ndy) < 1 && (abs(mdx) > 0.5 || abs(mdy) > 0.5)

        if attached {
            if movedTogether { return }
            // 用户在拖「贴着的」笔记窗
            let expX = flushX(for: side, width: n.frame.width)
            let dev = max(abs(no.x - expX), abs(no.y - mo.y))
            if dev < detachDist {
                attach(to: side)                  // 还在吸附区 → 拉回贴合位（粘住）
            } else {
                detach()                          // 拉得够远 → 松开
            }
        } else {
            // 脱离状态：很贴近主窗左/右边且纵向重叠 → 吸附
            guard verticalOverlap(n.frame, m.frame) else { return }
            if abs(no.x - m.frame.maxX) < snapTrigger {
                attach(to: .right)
            } else if abs((no.x + n.frame.width) - m.frame.minX) < snapTrigger {
                attach(to: .left)
            }
        }
    }

    private func verticalOverlap(_ a: NSRect, _ b: NSRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > 60
    }
}


/// 套在 SwiftUI 窗口 delegate 外面的代理：只回答「缩放后多大」，其余消息全部原样转给原来的 delegate。
private final class ZoomDelegateProxy: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    let standardFrame: (NSWindow, NSRect) -> NSRect?

    init(original: NSWindowDelegate?, standardFrame: @escaping (NSWindow, NSRect) -> NSRect?) {
        self.original = original
        self.standardFrame = standardFrame
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        if let f = standardFrame(window, newFrame) { return f }
        return original?.windowWillUseStandardFrame?(window, defaultFrame: newFrame) ?? newFrame
    }

    // 其他 delegate 方法：自己没实现的，交给原来的 delegate
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original, original.responds(to: aSelector) { return original }
        return super.forwardingTarget(for: aSelector)
    }
}

/// 拿到 SwiftUI 视图所在的 NSWindow：视图**真正被放进窗口的那一刻**回调（viewDidMoveToWindow）。
///
/// 以前的写法是 makeNSView 里 `DispatchQueue.main.async { view.window }`——赌「下一轮主循环时
/// 视图已经进了窗口」。调试版跑得慢通常赌得赢；导出的 Release 版开了优化，常常那一刻 window 还是 nil，
/// 直接跳过、也不会再试，于是笔记窗没注册、磁铁跟随不生效。
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void
        private weak var reported: NSWindow?

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window, w !== reported else { return }   // 同一个窗口只报一次
            reported = w
            // 推到下一轮再回调：此刻窗口可能还在布局中，立刻改窗口大小 / 位置会被 SwiftUI 盖掉
            DispatchQueue.main.async { [onWindow] in onWindow(w) }
        }
    }
}
#endif
