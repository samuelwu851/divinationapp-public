#if os(macOS)
import AppKit

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

    private let snapTrigger: CGFloat = 16         // 很贴近才吸附
    private let detachDist: CGFloat = 48          // 吸住后要拉这么远才松开
    private let defaultNotesWidth: CGFloat = 432

    func registerMain(_ w: NSWindow) {
        guard main !== w else { return }
        main = w
        observe(w, NSWindow.didResizeNotification) { [weak self] in self?.onMainResized() }
    }

    func registerNotes(_ w: NSWindow) {
        notes = w
        w.isRestorable = false
        observe(w, NSWindow.didMoveNotification) { [weak self] in self?.onNotesMoved() }
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
    private func attach(to s: Side, initial: Bool = false) {
        guard let m = main, let n = notes else { return }
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
        guard attached else { return }
        attach(to: side)        // childWindow 只跟随平移、不跟随缩放 → 重新齐边、等高
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
#endif
