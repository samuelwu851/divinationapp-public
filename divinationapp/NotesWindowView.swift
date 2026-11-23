import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 笔记窗口里的页面（NavigationStack 的路径）：编辑器、案主列表、某位案主。
enum NotesRoute: Hashable {
    case editor(NoteEditTarget)
    case subjects
    case subject(Int)
    case trash
}

/// 笔记（案例库）独立窗口：顶部搜索栏 + 筛选（标签 / 案主 / 术数）+ 笔记列表；
/// 底部菜单栏（同主窗口的胶囊样式）：笔 = 新建笔记，人 = 案主。
/// 点列表一条 → 进编辑器。编辑器、案主页都是推入的下一页（左上角返回）。
struct NotesWindowView: View {
    /// 笔记窗最窄 518：编辑器工具栏按这个宽度排成一行，再窄会折成好几行、正文被挤成一条（见 note-editor.html）。
    /// 设在 NavigationStack 外面，推进去的编辑器、案主页也一样受限。
    static let minWidth: CGFloat = 518

    private let client = DivinationClient()

    @State private var path: [NotesRoute] = []
    @State private var filter = NoteFilter()
    @State private var notes: [Note] = []

    // 筛选下拉菜单的选项（每次回到列表时刷新）
    @State private var allLabels: [NoteLabel] = []
    @State private var allSubjects: [Subject] = []
    @State private var allShushu: [Shushu] = []
    @State private var chartForms: [ChartSearchForm] = []
    @State private var showChartSearch = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    searchBar
                    chartSearchButton                      // 搜索框右边：按排盘搜
                }
                filterBar
                Divider()
                list
                Divider()
                bottomBar
            }
            .frame(minWidth: Self.minWidth, minHeight: 360)
            .background(PatternBackground())          // 与排盘同款背景纹理
            .navigationDestination(for: NotesRoute.self) { route in
                switch route {
                case .editor(let target):
                    NoteEditorView(client: client, target: target) { reload() }
                case .subjects:
                    SubjectListView(client: client) { path.append($0) }
                case .subject(let id):
                    SubjectDetailView(client: client, subjectId: id) { path.append($0) }
                case .trash:
                    TrashView(client: client) { reload() }       // 恢复后主列表马上刷新
                }
            }
            .onAppear { reload() }                     // 从编辑器 / 案主页返回时也刷新
            .onChange(of: filter) { _, _ in reloadNotes() }
            // 排盘页点了「存进案例库」：推进编辑器，新建一篇带这个排盘的笔记
            .onChange(of: CasebookOpener.shared.pending) { _, _ in openPending() }
            .onAppear { openPending() }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: CasebookBackup.restoredNotification)) { _ in
                path = []                                  // 恢复了备份：回到列表、重新取数据
                filter = NoteFilter()
                reload()
            }
            #endif
            #if os(macOS)
            .background(NotesWindowAccessor())         // 注册到窗口管理器（贴合主窗）
            #endif
        }
        .frame(minWidth: Self.minWidth)                 // 编辑器 / 案主页推进来也不能再窄
    }

    // MARK: - 顶部：关键字搜索（标题 + 正文）

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索标题、正文、所问之事、特点", text: $filter.keyword)
                .textFieldStyle(.plain)
            if !filter.keyword.isEmpty {
                Button { filter.keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.top, 12)
    }

    /// 搜索框右边的「搜索排盘」按钮：选了排盘条件时变成强调色、带数字。
    private var chartSearchButton: some View {
        Button { showChartSearch = true } label: {
            HStack(spacing: 3) {
                Image(systemName: filter.chartBlocks.isEmpty
                      ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 20))
                if !filter.chartBlocks.isEmpty {
                    Text("\(filter.chartBlocks.count)").font(.caption).bold()
                }
            }
            .foregroundStyle(filter.chartBlocks.isEmpty ? Color.secondary : Color.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("搜索排盘")
        .padding(.trailing, 12)
        .padding(.top, 12)
        .popover(isPresented: $showChartSearch, arrowEdge: .bottom) {
            ChartSearchPanel(forms: chartForms, blocks: $filter.chartBlocks)
        }
    }

    // MARK: - 筛选：标签 / 案主 / 术数（每类可多选；所有条件同时满足）

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterPicker(title: "标签", items: allLabels, selection: $filter.labels, name: \.name, searchable: true)
            FilterPicker(title: "案主", items: allSubjects, selection: $filter.subjects, name: \.name, searchable: true)
            FilterPicker(title: "术数", items: allShushu, selection: $filter.shushu, name: \.name, searchable: false)
            Spacer(minLength: 0)
            if !filter.isEmpty {
                Button("清除筛选") { filter = NoteFilter() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 笔记列表

    private var list: some View {
        Group {
            if notes.isEmpty {
                VStack(spacing: 6) {
                    if filter.isEmpty {
                        Text("还没有笔记").foregroundStyle(.secondary)
                        Text("点下面的笔新建").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("没有符合条件的笔记").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NoteList(notes: notes, onOpen: { path.append(.editor(.edit($0))) },
                         onTrash: { client.noteTrash(id: $0); reload() })
            }
        }
    }

    // MARK: - 底部菜单栏：笔 = 新建笔记，人 = 案主（同主窗口的胶囊样式）

    private var bottomBar: some View {
        HStack(spacing: 6) {
            barButton(help: "新建笔记") { path.append(.editor(.new)) } icon: {
                PenIcon(color: .secondary, lineWidth: 1.8)
            }
            barButton(help: "案主") { path.append(.subjects) } icon: {
                PersonIcon(color: .secondary, lineWidth: 1.8)
            }
            barButton(help: "回收站") { path.append(.trash) } icon: {
                Image(systemName: "trash").font(.system(size: 19)).foregroundStyle(.secondary)
            }
        }
        .padding(5)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)   // 整条胶囊水平居中
    }

    private func barButton<I: View>(help: String, action: @escaping () -> Void,
                                    @ViewBuilder icon: () -> I) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 26, height: 26)
                .padding(.vertical, 8)
                .padding(.horizontal, 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 数据

    private func reload() {
        allLabels = client.labelList()
        allSubjects = client.subjectList()
        allShushu = client.shushuList()
        if chartForms.isEmpty { chartForms = client.chartSearchForms() }
        // 选中的标签 / 案主已经被删了（或改了名）→ 跟着更新，避免拿旧条件去搜
        filter.labels = filter.labels.compactMap { l in allLabels.first { $0.id == l.id } }
        filter.subjects = filter.subjects.compactMap { s in allSubjects.first { $0.id == s.id } }
        reloadNotes()
    }

    private func reloadNotes() { notes = client.noteList(filter) }

    private func openPending() {
        guard let spec = CasebookOpener.shared.pending else { return }
        CasebookOpener.shared.pending = nil
        path = [.editor(.newWithChart(spec))]
    }
}

/// 筛选胶囊（可多选，同一类选多个 = 都要满足）：没选时显示「标签 ▾」；选了一个显示它的名字，
/// 选了多个显示「疾病 等2个」（强调色）。名字最多显示 10 个字，太长用省略号。
///
/// 点胶囊弹出小浮窗（不用 Menu：Menu 点一项就会收起，没法连续多选）。浮窗点别处才关。
/// - searchable（标签、案主）：顶部搜索框（英文不分大小写）；已选的高亮排在最上面，右边 × 取消；
///   没选的按原来的顺序排在下面，点一下选上。取消后自然回到原来的位置（未选列表永远按原顺序）。
/// - 不 searchable（术数）：固定顺序的清单，点一下勾上 / 取消。
private struct FilterPicker<Item: Identifiable & Equatable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: [Item]
    let name: KeyPath<Item, String>
    let searchable: Bool

    @State private var show = false
    @State private var query = ""

    private var labelText: String {
        switch selection.count {
        case 0: return title
        case 1: return shortName(selection[0][keyPath: name])
        default: return "\(shortName(selection[0][keyPath: name])) 等\(selection.count)个"
        }
    }

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 4) {
                Text(labelText).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(selection.isEmpty ? Color.gray.opacity(0.12) : Color.accentColor.opacity(0.15)))
            .foregroundStyle(selection.isEmpty ? Color.secondary : Color.accentColor)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(selection.map { $0[keyPath: name] }.joined(separator: "、"))   // 悬停看全部已选（全名）
        .popover(isPresented: $show, arrowEdge: .bottom) {
            popoverContent
                // ⚠️ macOS 的 popover 只在弹出那一刻定一次大小，所以用固定大小，列表在里面滚动
                .frame(width: 240, height: searchable ? 300 : 360)
        }
        .onChange(of: show) { _, now in if !now { query = "" } }
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            if searchable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索\(title)", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
                .padding(10)
                Divider()
            }
            ScrollView {
                // 不用 LazyVStack + 同一个 id：同一个标签从「没选」挪到「已选」时，SwiftUI 会按 id 认成同一行、
                // 沿用旧的样子（没有高亮和 ×）。所以两段分别加前缀 id，让它们是不同的行。
                VStack(alignment: .leading, spacing: 2) {
                    if searchable {
                        ForEach(selection) { item in selectedRow(item).id("selected-\(item.id)") }   // 已选：高亮在最上面
                        if !selection.isEmpty && !unselectedMatches.isEmpty { Divider().padding(.vertical, 4) }
                        ForEach(unselectedMatches) { item in plainRow(item).id("unselected-\(item.id)") }  // 没选的：原顺序
                        if unselectedMatches.isEmpty && selection.isEmpty {
                            Text(items.isEmpty ? "还没有\(title)" : "没有符合的\(title)")
                                .font(.callout).foregroundStyle(.secondary).padding(10)
                        }
                    } else {
                        ForEach(items) { item in checkRow(item) }               // 术数：固定顺序，打勾
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.visible)
        }
    }

    /// 没选的、并且匹配搜索词的（按 items 原来的顺序）。
    private var unselectedMatches: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            !isSelected(item) && (q.isEmpty || item[keyPath: name].localizedCaseInsensitiveContains(q))
        }
    }

    private func isSelected(_ item: Item) -> Bool { selection.contains { $0.id == item.id } }

    /// 选上一项；已经选过就不再加（防止界面还没刷新时连点，同一项被加好几次）。
    private func select(_ item: Item) {
        guard !isSelected(item) else { return }
        selection.append(item)
    }

    private func selectedRow(_ item: Item) -> some View {
        HStack(spacing: 6) {
            Text(shortName(item[keyPath: name])).lineLimit(1)
            Spacer(minLength: 4)
            Button { selection.removeAll { $0.id == item.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.accentColor.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("取消")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
        .foregroundStyle(Color.accentColor)
        .help(item[keyPath: name])
    }

    private func plainRow(_ item: Item) -> some View {
        Text(shortName(item[keyPath: name]))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { select(item) }
            .help(item[keyPath: name])
    }

    private func checkRow(_ item: Item) -> some View {
        let on = isSelected(item)
        return HStack(spacing: 6) {
            Text(item[keyPath: name])
            Spacer(minLength: 4)
            if on { Image(systemName: "checkmark") }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor.opacity(0.15) : Color.clear))
        .foregroundStyle(on ? Color.accentColor : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected(item) { selection.removeAll { $0.id == item.id } } else { select(item) }
        }
    }

    /// 名字最多 10 个字，超出用省略号。
    private func shortName(_ s: String) -> String {
        s.count > 10 ? String(s.prefix(10)) + "…" : s
    }
}

/// 笔记列表（主列表和案主页共用）：点一条 → onOpen(笔记 id)。
/// 删除（放进回收站）三种方式：右键「移到回收站」；两指往左滑 / 鼠标按住往左拖 → 点红色垃圾桶。
struct NoteList: View {
    let notes: [Note]
    var onOpen: (Int) -> Void
    var onTrash: (Int) -> Void

    @State private var swipe = SwipeState()

    var body: some View {
        GeometryReader { geo in
            List(notes) { note in
                SwipeToTrashRow(id: note.id, swipe: swipe,
                                onTap: { onOpen(note.id) },
                                onTrash: { swipe.reset(); onTrash(note.id) }) {
                    NoteRow(note: note,
                            maxTextWidth: geo.size.width * 0.75,   // 标题/预览最多占 3/4 宽
                            windowWidth: geo.size.width)           // 时间按窗宽决定全显/省略
                }
                .contextMenu {
                    Button("移到回收站", role: .destructive) { swipe.reset(); onTrash(note.id) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)   // 透出背景纹理
        }
        .onChange(of: notes.map(\.id)) { _, _ in swipe.reset() }   // 列表内容变了（删除、恢复、筛选）：全部合上
        #if os(macOS)
        .onAppear { swipe.reset(); swipe.startTrackpad() }   // 从回收站等页面回来：全部合上
        .onDisappear { swipe.stopTrackpad() }
        #endif
    }
}

/// 列表里的一条笔记。
/// 左：案主胶囊(可多个) + 标题，下方正文预览；右上：label（算什么事，预留）；右下：创建/修改时间（自适应）。
struct NoteRow: View {
    let note: Note
    let maxTextWidth: CGFloat        // 标题/预览的最大显示宽度（= 窗宽 3/4，拉长则显示更多）
    let windowWidth: CGFloat         // 当前窗宽，用来决定时间显全还是省略

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧：标题 → 案主 → 正文预览（自上而下）
            VStack(alignment: .leading, spacing: 6) {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxTextWidth, alignment: .leading)

                if let subs = note.subjects, !subs.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(subs) { s in
                            Text(s.name.count > 10 ? String(s.name.prefix(10)) + "…" : s.name)   // 最多 10 个字
                                .help(s.name)
                                .font(.title2)
                                .foregroundStyle(.primary)          // 黑色
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.18)))
                        }
                    }
                }

                if let p = note.preview, !p.isEmpty {
                    Text(p)
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)                  // 黑色
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: maxTextWidth, alignment: .leading)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // 右侧：上=label，下=时间
            VStack(alignment: .trailing, spacing: 4) {
                if let labels = note.labels, !labels.isEmpty {
                    LabelChipsLine(labels: labels)
                }
                if let shushu = note.shushu, !shushu.isEmpty {
                    ShushuChipsLine(shushu: shushu)               // 用了哪些术数（标签下面）
                }
                Spacer(minLength: 2)
                stampLine("创建", note.createdAt)
                stampLine("改", note.updatedAt)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 88)
    }

    /// 时间戳：默认窗宽只显示年月日（时间用省略号），窗口拉宽到阈值后显示到分钟。
    @ViewBuilder
    private func stampLine(_ label: String, _ raw: String) -> some View {
        let date = String(raw.prefix(10))
        let time = raw.count >= 16 ? String(raw.dropFirst(11).prefix(5)) : ""
        let showFull = windowWidth > 560     // 默认 518 → 省略；拉宽到此才全显
        Text(showFull && !time.isEmpty ? "\(label) \(date) \(time)" : "\(label) \(date) …")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// 预览右侧的术数：最多 3 个（按术数清单的顺序），每个按色系上色；悬停看全部。
struct ShushuChipsLine: View {
    let shushu: [Shushu]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(shushu.prefix(3)) { s in ShushuChip(shushu: s) }
            if shushu.count > 3 {
                Text("…").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help(shushu.map(\.name).joined(separator: "、"))
    }
}

/// 一个术数胶囊：实心底色 + 白字。颜色都调得柔和（参考五行颜色），一排看下来不刺眼。
struct ShushuChip: View {
    let shushu: Shushu

    var body: some View {
        Text(shushu.name)
            .font(.caption2).fontWeight(.medium)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Self.color(shushu.tone)))
            .foregroundStyle(.white)
    }

    /// 色系 → 底色（白字都看得清：和白色的对比度都在 4 左右以上）。
    static func color(_ tone: String?) -> Color {
        switch tone {
        case "yi":    return Color(hex: 0x33363A)   // 易学（易经、六爻、梅花…）：深灰黑，同五行「水」
        case "ren":   return Color(hex: 0x4A6A8C)   // 六壬类（大六壬、小六壬、金口诀）：灰蓝
        case "qimen": return Color(hex: 0x3F7F7A)   // 奇门遁甲：青（偏蓝的绿）
        case "red":   return Color(hex: 0xB45A50)   // 八字、太乙神数：砖红，同五行「火」
        case "ziwei": return Color(hex: 0x75608F)   // 紫微斗数：灰紫
        case "earth": return Color(hex: 0x9C7C33)   // 风水：土黄（比五行「土」深一档，白字才看得清）
        default:      return Color(hex: 0x7D7870)   // 随笔等：暖灰
        }
    }
}

/// 预览右上角的标签：最多 3 个，三个合起来的宽度固定（maxWidth），永远横排一行。
/// 放不下时从后面开始截断：先截第 3 个，不够再截第 2 个，被截的那个显示成「疾…」，而不是整个消失。
/// 做法：三个胶囊的 layoutPriority 依次是 3、2、1 —— HStack 先满足优先级高的，低的自动截断成省略号。
struct LabelChipsLine: View {
    let labels: [NoteLabel]
    static let maxWidth: CGFloat = 120

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(labels.prefix(3).enumerated()), id: \.element.id) { i, l in
                Text(l.name).font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 20)                      // 至少留「一个字 + …」，不会被压成半个字
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                    .layoutPriority(Double(3 - i))           // 越靠前越优先完整显示
            }
        }
        .frame(maxWidth: Self.maxWidth, alignment: .trailing)
        .help(labels.map(\.name).joined(separator: "、"))   // 悬停看全部标签
    }
}

#if os(macOS)
/// 把当前（笔记）窗口注册到 CasebookWindowManager，使其贴合主窗并跟随。
private struct NotesWindowAccessor: View {
    var body: some View {
        WindowReader { CasebookWindowManager.shared.registerNotes($0) }   // 进了窗口的那一刻才注册（见 WindowReader）
    }
}
#endif

/// 「搜索排盘」面板：点「＋ 选择术数」加一个条件块（新加的放在最上面，旧的往下挤），
/// 每一块右上角的 × 去掉它。同一种术数可以加好几块：比如两块八字 = 笔记里要有两张八字分别满足。
/// 改了马上生效（下面的笔记列表跟着变）；浮窗点别处才关。
struct ChartSearchPanel: View {
    let forms: [ChartSearchForm]
    @Binding var blocks: [ChartQueryBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(forms) { f in
                        Button(f.title) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                blocks.insert(ChartQueryBlock(type: f.type), at: 0)   // 新的在最上面
                            }
                        }
                    }
                } label: {
                    Label("选择术数", systemImage: "plus")
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().stroke(Color.secondary.opacity(0.35),
                                                     style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                Button("全部清空") { withAnimation { blocks = [] } }
                    .disabled(blocks.isEmpty)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if blocks.isEmpty {
                        Text("点「＋ 选择术数」添加排盘条件")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach($blocks) { $block in
                        if let form = forms.first(where: { $0.type == block.type }) {
                            BlockCard(form: form, block: $block) {
                                withAnimation(.easeOut(duration: 0.15)) { blocks.removeAll { $0.id == block.id } }
                            }
                        }
                    }
                    if blocks.count > 1 {
                        Text("每一块都要有一张排盘满足；同一种术数加了几块，就要有几张这种排盘分别满足。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
        }
        // ⚠️ macOS 的 popover 只在弹出时定一次大小：用固定大小，内容在里面滚动
        .frame(width: 400, height: 420)
    }
}

/// 填整数的条件（如年份：选项太多放不进下拉框）。空着 = 不限。
/// 一边输入一边搜（输到 202 没结果，输完 2027 就出来，删空 = 不限），不用按回车；
/// 回车或点别处时再把超出范围的数收到边界。
private struct NumberCondition: View {
    let field: ChartSearchForm.Field
    @Binding var value: String?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            TextField("不限", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(YearWheel.fieldFill))      // 同年份输入框的柔和灰白
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(YearWheel.fieldStroke, lineWidth: 1))
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onChange(of: text) { _, t in value = Self.parse(t).map(String.init) }   // 边输边搜
                .help(rangeHelp)
        }
        .onAppear { text = value ?? "" }
    }

    private var rangeHelp: String {
        switch (field.min, field.max) {
        case let (lo?, hi?): return "填 \(lo)–\(hi) 的整数；空着 = 不限"
        default: return "填整数；空着 = 不限"
        }
    }

    /// 输入框里的字 → 整数；空着或填的不是数字 → nil（不限）。
    private static func parse(_ t: String) -> Int? {
        Int(t.filter { $0.isNumber || $0 == "-" })
    }

    private func commit() {
        guard let n = Self.parse(text) else {
            value = nil; text = ""; return                       // 空着或填错 = 不限
        }
        var v = n
        if let lo = field.min { v = Swift.max(v, lo) }
        if let hi = field.max { v = Swift.min(v, hi) }
        value = String(v)
        text = String(v)
    }
}

/// 一个条件块：标题 + 右上角 ×；勾选类字段（性别、有没有变卦）一行，下拉类字段排成网格。
private struct BlockCard: View {
    let form: ChartSearchForm
    @Binding var block: ChartQueryBlock
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(form.title).font(.subheadline).bold()
            ForEach(form.fields.filter(\.isChecks)) { field in checks(field) }
            // 下拉 / 填数字的字段：按 group 分成几组，每组一张网格，组上面一个小标题（没分组就是一整张网格）
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 4) {
                    if let title = g.title {
                        Text(title).font(.caption).bold().foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(1, form.columns)),
                              alignment: .leading, spacing: 8) {
                        ForEach(g.fields) { field in
                            if field.isNumber {
                                NumberCondition(field: field, value: $block.fields[field.key])
                            } else {
                                menu(field)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.white, .gray)
            }
            .buttonStyle(.plain)
            .help("去掉这个条件")
            .padding(6)
        }
    }

    /// 非勾选的字段按 group 分组（相邻的同组字段放一起，保持表单里的顺序）。
    private var groups: [(title: String?, fields: [ChartSearchForm.Field])] {
        var out: [(title: String?, fields: [ChartSearchForm.Field])] = []
        for f in form.fields where !f.isChecks {
            if let last = out.last, last.title == f.group {
                out[out.count - 1].fields.append(f)
            } else {
                out.append((f.group, [f]))
            }
        }
        return out
    }

    /// 互斥勾选框：勾一个 = 只要这种；再点一次取消 = 不限。
    private func checks(_ field: ChartSearchForm.Field) -> some View {
        HStack(spacing: 14) {
            if !field.label.isEmpty {
                Text(field.label).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(field.options, id: \.value) { o in
                Toggle(o.label, isOn: Binding(
                    get: { block.fields[field.key] == o.value },
                    set: { on in block.fields[field.key] = on ? o.value : nil }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }

    private func menu(_ field: ChartSearchForm.Field) -> some View {
        let selected = block.fields[field.key] ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { selected },
                set: { block.fields[field.key] = $0.isEmpty ? nil : $0 }
            )) {
                Text("不限").tag("")
                ForEach(field.options, id: \.value) { o in Text(o.label).tag(o.value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
