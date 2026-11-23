import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 左滑放进回收站

/// 笔记列表的「左滑」状态（整张列表共用一份：同一时间只有一条是拉开的）。
///
/// 两种拉法：
/// - 鼠标：按住一条往左拖（SwiftUI 的 DragGesture）。
/// - 触控板：两指往左滑。这在 macOS 上是「横向滚动」事件，不是拖动手势，
///   所以用一个本地事件监听（NSEvent local monitor）接住鼠标所在那一条的横向滚动。
@Observable
final class SwipeState {
    static let revealWidth: CGFloat = 80        // 拉开后这一条往左挪多少（= 垃圾桶宽 + 间隙）
    static let gap: CGFloat = 8                 // 红色垃圾桶和笔记内容之间留的空隙

    var openId: Int?                            // 已经拉开的那一条
    var dragId: Int?                            // 正在拉的那一条
    var dragX: CGFloat = 0                      // 正在拉的距离（往左是负数）
    var hoveredId: Int?                         // 鼠标停在哪一条上（触控板横滑作用在它身上）

    /// 某一条现在应该往左挪多少（拉开 = -72，正在拉 = 跟着手指）。
    func offset(for id: Int) -> CGFloat {
        let base: CGFloat = openId == id ? -Self.revealWidth : 0
        let x = dragId == id ? base + dragX : base
        return min(0, max(-Self.revealWidth * 1.6, x))
    }

    func begin(_ id: Int) {
        if openId != id { openId = nil }        // 拉另一条时，先合上之前那条
        dragId = id
        dragX = 0
    }

    /// 松手：
    /// - 原来是合着的：要拉到底（垃圾桶完整露出来）才停住，没拉到底就弹回去；
    /// - 原来是拉开的：往右挪一点点（超过 4 点）就整个合上，否则保持拉开。
    /// 可以重复调用（第二次什么都不做）——拖动被系统取消时也会走到这里，保证不会停在半截。
    func end() {
        guard let id = dragId else { return }
        let wasOpen = openId == id
        withAnimation(.easeOut(duration: 0.18)) {
            if wasOpen {
                openId = dragX > 4 ? nil : id
            } else {
                openId = dragX <= -Self.revealWidth + 2 ? id : nil
            }
            dragId = nil
            dragX = 0
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.18)) { openId = nil }
    }

    /// 全部归零（不带动画）：放进回收站以后、列表重新出现时用，免得恢复回来的笔记还是拉开的样子。
    func reset() {
        openId = nil
        dragId = nil
        dragX = 0
    }

    /// 全部合上（带动画）：连「正在拉、还没松手判定」的那条也一起收回。
    func collapseAll() {
        withAnimation(.easeOut(duration: 0.18)) {
            openId = nil
            dragId = nil
            dragX = 0
        }
    }

    /// 有没有哪一条现在是露出垃圾桶的（拉开的，或者正在拉的）。
    var anyRevealed: Bool { openId != nil || (dragId != nil && dragX < -1) }

    /// 刚刚点了红色垃圾桶：这次点击别当成「点别处」去合上。
    var trashTapped = false

    /// 刚才那次「点别处」已经把拉开的合上了：这次点击落在某条笔记上时，不要顺便打开它。
    private(set) var swallowTap = false

    /// 某一行被点了：如果这次点击是用来合上的，就吞掉（返回 true）。
    func consumeTap() -> Bool {
        guard swallowTap else { return false }
        swallowTap = false
        return true
    }

    #if os(macOS)
    private var monitors: [Any] = []
    private var tracking = false

    /// 开始监听（列表出现时调用，消失时 stopTrackpad）：
    /// - 触控板横向滑动 → 拉开 / 合上；
    /// - 鼠标在别处点一下 → 拉开的那条合上。
    func startTrackpad() {
        guard monitors.isEmpty else { return }
        add(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            self?.handle(e) ?? e
        })
        // 点别处 → 合上。用「按下」而不是「松开」：列表（NSTableView）处理点击时自己接走了松开事件，
        // 本地监听收不到，所以之前点别处没反应。按下时看位置：点在红色垃圾桶上就放行（让按钮处理）。
        // 不再按坐标判断点没点在垃圾桶上（列表里每一行的坐标系和窗口不一样，不可靠）：
        // 按下时先记一下，稍等 0.25 秒——这期间垃圾桶按钮被点了（trashTapped）就不合上，否则全部合上。
        add(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self else { return e }
            guard self.anyRevealed else { return e }
            self.trashTapped = false
            self.swallowTap = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !self.trashTapped { self.collapseAll() }
            }
            // 点的不是笔记（比如搜索框、空白处）就不会有 consumeTap 来清掉它：过一会儿自动作废
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.swallowTap = false }
            return e
        })
    }

    func stopTrackpad() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    /// 加监听：addLocalMonitorForEvents 返回的是可选值，要拆出来再存，不然 removeMonitor 认不出、监听摘不掉。
    private func add(_ m: Any?) { if let m { monitors.append(m) } }

    /// 只管「鼠标停在某一条上、而且是横着滑」的滚动；竖着滑照常交给列表滚动。
    private func handle(_ e: NSEvent) -> NSEvent? {
        // 让这一条跟着手指走：开了「自然滚动」时 scrollingDeltaX 本来就是手指方向，没开就反过来
        let dx = e.isDirectionInvertedFromDevice ? e.scrollingDeltaX : -e.scrollingDeltaX
        switch e.phase {
        case .began:
            guard abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
            // 有一条拉开着、而手指不在它上面：往右一滑就合上它（这次滑动不再拉别的）
            if let open = openId, hoveredId != open {
                tracking = true
                if dx > 0 { close() }
                return nil
            }
            guard let id = hoveredId else { return e }
            tracking = true
            begin(id)
            dragX += dx
            return nil
        case .changed:
            guard tracking else { return e }
            if dragId != nil { dragX += dx }
            return nil
        case .ended, .cancelled:
            guard tracking else { return e }
            tracking = false
            end()
            return nil
        default:
            // 松手后的惯性滚动：刚才在横滑就吞掉，别让列表跟着动
            return tracking || (!e.momentumPhase.isEmpty && dragId != nil) ? nil : e
        }
    }
    #endif
}

/// 可左滑的一行：往左拉露出红底垃圾桶，点它放进回收站。拉开时点这一行 = 合上（不打开笔记）。
struct SwipeToTrashRow<Content: View>: View {
    let id: Int
    let swipe: SwipeState
    var onTap: () -> Void
    var onTrash: () -> Void
    @ViewBuilder var content: () -> Content

    /// 鼠标拖动是否还在进行：拖动被系统取消时 onEnded 不会被调用，但这个值会自动变回 false，
    /// 借它补一次「松手」，这一条就不会停在半截。
    @GestureState private var dragging = false

    var body: some View {
        let x = swipe.offset(for: id)
        content()
            .contentShape(Rectangle())
            .offset(x: x)
            .overlay(alignment: .trailing) {
                // 红底垃圾桶：只占露出来的那一块，和笔记内容之间留一点空隙
                Button(action: { swipe.trashTapped = true; onTrash() }) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: max(0, -x - SwipeState.gap))
                        .frame(maxHeight: .infinity)
                        .background(Color(hex: 0xC0504D))       // 柔和一点的红，不刺眼
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .opacity(-x > SwipeState.gap + 1 ? 1 : 0)
                .help("放进回收站")
            }
            .clipped()
            .onTapGesture {
                if swipe.consumeTap() { return }                          // 这次点击是用来合上拉开那条的
                if swipe.anyRevealed { swipe.collapseAll() } else { onTap() }
            }
            .gesture(
                DragGesture(minimumDistance: 10)          // 鼠标按住往左拖
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        if swipe.dragId != id { swipe.begin(id) }
                        swipe.dragX = v.translation.width
                    }
                    .onEnded { _ in if swipe.dragId == id { swipe.end() } }
            )
            .onChange(of: dragging) { _, now in
                if !now && swipe.dragId == id { swipe.end() }
            }
            .onHover { inside in
                if inside { swipe.hoveredId = id } else if swipe.hoveredId == id { swipe.hoveredId = nil }
            }
    }
}

// MARK: - 回收站页面

/// 回收站：放进来的笔记可以恢复，或彻底删除（连同排盘、图片）；也可以一键清空。不会自动清理。
struct TrashView: View {
    let client: DivinationClient
    var onChanged: () -> Void = {}             // 恢复 / 删除后，让笔记列表马上重新取一次

    @State private var notes: [Note] = []
    @State private var pendingDelete: Note?
    @State private var confirmEmpty = false

    var body: some View {
        Group {
            if notes.isEmpty {
                Text("回收站是空的").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    List(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            NoteRow(note: note, maxTextWidth: geo.size.width * 0.75, windowWidth: geo.size.width)
                            HStack(spacing: 12) {
                                Text("删除于 \(String((note.deletedAt ?? "").prefix(16)))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("恢复") { restore(note) }
                                Button("彻底删除", role: .destructive) { pendingDelete = note }
                            }
                            .controlSize(.small)
                        }
                        .contextMenu {
                            Button("恢复") { restore(note) }
                            Button("彻底删除", role: .destructive) { pendingDelete = note }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(PatternBackground())
        .navigationTitle("回收站")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("清空回收站", role: .destructive) { confirmEmpty = true }
                    .disabled(notes.isEmpty)
            }
        }
        .alert("彻底删除「\(pendingDelete.map { $0.title.isEmpty ? "无标题" : $0.title } ?? "")」？",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("彻底删除", role: .destructive) {
                if let n = pendingDelete { client.noteDelete(id: n.id) }
                pendingDelete = nil
                reload()
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("笔记里的排盘和图片会一起删除，不能恢复。")
        }
        .alert("清空回收站？", isPresented: $confirmEmpty) {
            Button("清空", role: .destructive) { client.trashEmpty(); reload() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("回收站里的 \(notes.count) 篇笔记会彻底删除（连同排盘和图片），不能恢复。")
        }
        .onAppear(perform: reload)
    }

    private func restore(_ note: Note) {
        client.noteRestore(id: note.id)
        reload()
        onChanged()
    }

    private func reload() { notes = client.trashList() }
}
