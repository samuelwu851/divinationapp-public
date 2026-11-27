import SwiftUI

/// 编辑器目标：新建 / 编辑某条（带 note_id）。
enum NoteEditTarget: Hashable {
    case new
    case edit(Int)
    case newWithChart(ChartSaveSpec)      // 从排盘页「存进案例库」：新建笔记，正文里放好这个排盘
}

/// 笔记编辑器（独立一页）：标题 + 案主多选 + 正文（网页编辑器 TipTap，见 NoteEditorWebView）。
///
/// - 新建：一进来就在数据库里建一份空笔记，之后和「编辑」走同一套流程
///   （插入排盘、图片都需要先有 note_id）。没保存就离开 → 整份删掉。
/// - 保存：标题/正文走 note_update；案主、标签、术数对比基线做差量增删。
/// - 插入某种排盘时，自动勾上对应的术数（用户可以再叉掉）。
/// - 离开时：调 note_cleanup，清掉正文里已经不引用的排盘和图片
///   （编辑中插入后又删掉的、或放弃修改的）。
struct NoteEditorView: View {
    let client: DivinationClient
    let target: NoteEditTarget
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    /// 笔记里排盘的五行颜色：只在点开的排盘窗口里勾选，记住上次的选择，卡片跟着同步
    @AppStorage(ChartDetailView.wuxingColorKey) private var chartWuxingColor = false

    @State private var noteId: Int?
    @State private var createdHere = false      // 这份笔记是本次「新建」时建的
    @State private var saved = false
    @State private var finished = false

    @State private var title = ""
    @State private var subjects: [Subject] = []
    @State private var labels: [NoteLabel] = []
    @State private var shushu: [Shushu] = []            // 用了哪些术数（按清单顺序）
    @State private var shushuCatalog: [Shushu] = []     // 术数清单
    @State private var bodyChanged = false      // 网页编辑器通知「正文改过」
    @State private var loaded = false

    // 基线：载入时的原始值，用来判断「有没有未保存的修改」
    @State private var baseTitle = ""
    @State private var baseSubjectIDs: Set<Int> = []
    @State private var baseLabelIDs: Set<Int> = []
    @State private var baseShushu: Set<String> = []

    @State private var showUnsavedAlert = false
    @State private var showInsertChart = false
    @State private var confirmTrash = false
    @State private var showPickPosition = false   // 光标不在正文 → 提示先选位置
    @State private var openChart: ChartID?
    @State private var editor = NoteEditorController()
    @State private var headerHeight: CGFloat = 0      // 顶上那一块（标题…术数）的高度
    @State private var pendingShushu: String?          // 从排盘页存进来：要勾上的术数
    @State private var scrollY: CGFloat = 0           // 网页滚了多少

    private var isNew: Bool {
        switch target {
        case .new, .newWithChart: return true
        case .edit: return false
        }
    }

    /// 顶上那一块：标题、案主、标签、术数（和正文之间一条分隔线）。
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题", text: $title)
                .font(.title2).bold()
                .textFieldStyle(.plain)

            // 案主增删只改本地，点「保存」时才写后端
            SubjectPicker(client: client, selected: $subjects)

            // 标签、术数两行挨在一起：「＋」按钮固定在最左，已选的往右排，放不下可以左右滑
            VStack(alignment: .leading, spacing: 2) {
                // 标签（算什么事）：同样只改本地，保存时写后端
                LabelPicker(client: client, selected: $labels, onLabelDeleted: { labelDeleted($0) })
                // 术数：同样只改本地，保存时写后端；插入排盘会自动勾上对应的术数
                ShushuPicker(catalog: shushuCatalog, selected: $shushu)
            }

            Divider()
        }
    }

    /// 当前是否有未保存的改动。
    private var isDirty: Bool {
        title != baseTitle
            || bodyChanged
            || Set(subjects.map(\.id)) != baseSubjectIDs
            || Set(labels.map(\.id)) != baseLabelIDs
            || Set(shushu.map(\.code)) != baseShushu
    }

    var body: some View {
        // 正文（网页）铺满整页；标题、案主、标签、术数盖在网页顶上留出的空白上，
        // 页面往下滚时跟着一起往上滚走，只剩网页里的工具栏停在最上面；往上滚再一点点露出来。
        ZStack(alignment: .top) {
            if let noteId {
                NoteEditorWebView(controller: editor)
                    .sheet(isPresented: $showInsertChart) {
                        ChartInsertSheet(client: client, noteId: noteId, subjects: subjects) { id, type in
                            editor.insertChart(id: id)
                            addShushu(code: type)                  // 插了什么排盘就勾上什么术数
                        }
                    }
                    .sheet(item: $openChart) { c in        // 只有非 macOS 会用到（macOS 开独立窗口）
                        ChartDetailView(client: client, chartId: c.id)
                    }
            } else {
                VStack {
                    Spacer().frame(height: headerHeight)
                    if loaded { Text("笔记创建失败").foregroundStyle(.red) }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: 800)                      // 和网页正文一样最多 760（+ 左右边距）、居中
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    headerHeight = h
                    editor.setTopInset(h)                  // 网页顶上留出同样高的空白
                }
                // 网页滚了多少，这块就往上挪多少（最多挪到完全看不见）→ 看起来是一起滚
                .offset(y: -min(scrollY, headerHeight))
        }
        .clipped()                                         // 往上挪出去的部分不要盖到窗口工具栏
        // ⌘F：在笔记里查找。焦点在标题、案主输入框时也能用（网页自己也接 ⌘F / Ctrl+F）
        .background {
            Button("") { editor.openFind() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .background(PatternBackground())
        .navigationTitle(isNew ? "新建笔记" : "编辑笔记")
        .navigationBarBackButtonHidden(true)                 // 换成自定义返回，便于拦截
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { attemptBack() } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("删除") { confirmTrash = true }
                    .disabled(noteId == nil)
                Button("插入排盘") { requestInsertChart() }
                    .disabled(noteId == nil)
                Button("保存") { save() }
                    .disabled(noteId == nil || !isDirty)
            }
        }
        .alert("把这篇笔记移到回收站？", isPresented: $confirmTrash) {
            Button("移到回收站", role: .destructive) { moveToTrash() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("可以在回收站里恢复。还没保存的修改不会保留。")
        }
        .alert("请先选择插入位置", isPresented: $showPickPosition) {
            Button("好") {}
        } message: {
            Text("在正文里点一下，把光标放到要插入排盘的地方，再点「插入排盘」。")
        }
        .alert("有未保存的修改", isPresented: $showUnsavedAlert) {
            Button("保存并返回") { save() }
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("当前的标题、正文、案主、标签或术数改动还没保存，确定要离开吗？")
        }
        .onAppear {
            #if os(macOS)
            if !loaded { CasebookBackup.openEditors += 1 }   // 有笔记在编辑时不让恢复备份
            #endif
            load()
        }
        .onDisappear(perform: finish)
        .onChange(of: chartWuxingColor) { _, on in editor.setWuxingColor(on) }   // 排盘窗口里勾选 → 卡片同步
        .onReceive(NotificationCenter.default.publisher(for: ChartAnnotationView.changedNotification)) { n in
            if let id = n.object as? Int { editor.refreshChart(id: id) }           // 排盘窗口里改了所问之事 / 特点
        }
    }

    private func load() {
        guard !loaded else { return }
        shushuCatalog = client.shushuList()
        var content = ""
        switch target {
        case .new:
            if let n = client.noteCreate(title: "", body: "") {
                noteId = n.id
                createdHere = true
            }
        case .newWithChart(let spec):
            // 先建笔记，再排盘存进去，正文 = 这张排盘卡片 + 一个空段落（可以接着写）
            if let n = client.noteCreate(title: "", body: "") {
                noteId = n.id
                createdHere = true
                if let cid = client.chartCreate(noteId: n.id, type: spec.type, params: spec.params, question: spec.question) {
                    let doc: [String: Any] = ["type": "doc", "content": [
                        ["type": "chart", "attrs": ["id": cid]],
                        ["type": "paragraph"],
                    ]]
                    if let data = try? JSONSerialization.data(withJSONObject: doc) {
                        content = String(data: data, encoding: .utf8) ?? ""
                    }
                    pendingShushu = spec.type              // 基线记好以后再勾上术数（算作未保存的改动）
                }
            }
        case .edit(let id):
            if let n = client.noteGet(id: id) {
                noteId = id
                title = n.title
                content = n.body ?? ""
                subjects = n.subjects ?? []
                labels = n.labels ?? []
                shushu = n.shushu ?? []
            }
        }
        // 记录基线（新建则全为空）
        baseTitle = title
        baseSubjectIDs = Set(subjects.map(\.id))
        baseLabelIDs = Set(labels.map(\.id))
        baseShushu = Set(shushu.map(\.code))
        loaded = true
        if let code = pendingShushu {
            addShushu(code: code)
            bodyChanged = true                              // 正文里已经有排盘了：没保存就离开要提示
        }

        guard let noteId else { return }
        editor.wuxingColor = chartWuxingColor
        editor.onChange = { bodyChanged = true }
        editor.onLabelDeleted = { labelDeleted($0, fromEditor: true) }
        editor.onScroll = { scrollY = $0 }
        editor.onOpenChart = { id in
            #if os(macOS)
            openWindow(id: "chart", value: id)    // 独立窗口：可以边看排盘边写笔记
            #else
            openChart = ChartID(id: id)
            #endif
        }
        editor.load(noteId: noteId, content: content)
    }

    /// 某个标签被彻底删除了（在笔记标签浮窗里删，或在排盘卡片旁的浮窗里删）：
    /// 数据库里所有关联已经级联删掉，这里同步界面——去掉胶囊、从基线里也去掉（否则会误判成「有未保存的修改」），
    /// 再通知另一边（网页里的排盘卡片 / 笔记标签行）。
    private func labelDeleted(_ id: Int, fromEditor: Bool = false) {
        labels.removeAll { $0.id == id }
        baseLabelIDs.remove(id)
        if !fromEditor { editor.labelDeleted(id: id) }
    }

    /// 勾上一个术数（已勾上 / 不在清单里就不动），保持清单顺序。
    private func addShushu(code: String) {
        guard !shushu.contains(where: { $0.code == code }),
              shushuCatalog.contains(where: { $0.code == code }) else { return }
        let picked = Set(shushu.map(\.code)).union([code])
        shushu = shushuCatalog.filter { picked.contains($0.code) }
    }

    /// 「插入排盘」：光标在正文里才打开排盘面板，排完插到光标处；否则提示先在正文里点一下。
    private func requestInsertChart() {
        Task {
            if await editor.cursorInBody() { showInsertChart = true } else { showPickPosition = true }
        }
    }

    /// 移到回收站，然后离开编辑器（没保存的修改丢弃）。新建、从没保存过的笔记直接彻底删掉（见 finish）。
    private func moveToTrash() {
        guard let id = noteId else { return }
        if !(createdHere && !saved) { client.noteTrash(id: id) }
        onSaved()
        dismiss()
    }

    /// 返回：有未保存改动就弹提示，否则直接走。
    private func attemptBack() {
        if isDirty { showUnsavedAlert = true } else { dismiss() }
    }

    private func save() {
        guard let id = noteId else { return }
        Task {
            guard let body = await editor.currentJSON() else { return }
            _ = client.noteUpdate(id: id, title: title, body: body)
            // 案主：对比基线做差量增删
            let now = Set(subjects.map(\.id))
            for sid in now.subtracting(baseSubjectIDs) { _ = client.noteSubjectAdd(noteId: id, subjectId: sid) }
            for sid in baseSubjectIDs.subtracting(now) { _ = client.noteSubjectRemove(noteId: id, subjectId: sid) }
            // 标签：先去掉删掉的，再按界面上的先后顺序加新的（预览按添加先后显示）
            let nowLabels = Set(labels.map(\.id))
            for lid in baseLabelIDs.subtracting(nowLabels) { client.noteLabelRemove(noteId: id, labelId: lid) }
            for l in labels where !baseLabelIDs.contains(l.id) { client.noteLabelAdd(noteId: id, labelId: l.id) }
            // 术数：同样差量增删
            let nowShushu = Set(shushu.map(\.code))
            for c in baseShushu.subtracting(nowShushu) { client.noteShushuRemove(noteId: id, code: c) }
            for c in nowShushu.subtracting(baseShushu) { client.noteShushuAdd(noteId: id, code: c) }
            saved = true
            onSaved()
            dismiss()
        }
    }

    /// 离开编辑器（保存、放弃、关窗都会走到这里）：新建且没保存 → 整份删；否则清理没引用的排盘和图片。
    private func finish() {
        guard !finished else { return }
        #if os(macOS)
        CasebookBackup.openEditors = max(0, CasebookBackup.openEditors - 1)
        #endif
        guard let id = noteId else { finished = true; return }
        finished = true
        if createdHere && !saved {
            client.noteDelete(id: id)
        } else {
            client.noteCleanup(id: id)
        }
        editor.tearDown()
        onSaved()
    }
}

/// 标签行 / 术数行的共同排版：左边固定一个「＋」按钮，右边是已选胶囊（新加的排在最后），
/// 放不下时右边这段可以左右滑动。不留滚动条的位置，两行才能挨在一起。
private struct ChipRow<Add: View, Chips: View>: View {
    @ViewBuilder var add: () -> Add
    @ViewBuilder var chips: () -> Chips

    static var height: CGFloat { 32 }

    var body: some View {
        HStack(spacing: 6) {
            add()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { chips() }
                    .padding(.top, 6).padding(.trailing, 8)       // 给胶囊右上角的小叉留空间
            }
        }
        .frame(height: Self.height)
    }
}

/// 「＋ 标签」「＋ 术数」按钮的样子：虚线胶囊。
private struct AddChipLabel: View {
    let title: String
    var body: some View {
        Label(title, systemImage: "plus")
            .font(.subheadline)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.top, 6)                                     // 和右边胶囊对齐（胶囊上方给小叉留了 6）
    }
}

/// 可去掉的胶囊：悬浮时右上角出现小叉。
private struct RemovableChip: View {
    let text: String
    var help: String? = nil
    let fill: Color
    let foreground: Color
    var onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 120)                                 // 太长 → 后面省略号
            .help(help ?? text)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
            .foregroundStyle(foreground)
            .overlay(alignment: .topTrailing) {
                if hovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.white, .gray)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            .onHover { hovered = $0 }
    }
}

/// 笔记用了哪些术数：左边「＋ 术数」下拉菜单（只列还没选的），右边已选胶囊（悬浮出现小叉去掉）。
struct ShushuPicker: View {
    let catalog: [Shushu]
    @Binding var selected: [Shushu]

    private var remaining: [Shushu] {
        let have = Set(selected.map(\.code))
        return catalog.filter { !have.contains($0.code) }
    }

    var body: some View {
        ChipRow {
            Menu {
                ForEach(remaining) { s in
                    Button(s.name) {
                        let picked = Set(selected.map(\.code)).union([s.code])
                        selected = catalog.filter { picked.contains($0.code) }   // 按清单顺序
                    }
                }
            } label: {
                AddChipLabel(title: "术数")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(remaining.isEmpty)
        } chips: {
            ForEach(selected) { s in
                RemovableChip(text: s.name, fill: Color.secondary.opacity(0.15), foreground: .primary) {
                    selected.removeAll { $0.code == s.code }
                }
            }
        }
    }
}

/// 笔记标签：左边「＋ 标签」（弹出小浮窗搜索 / 新建 / 删除标签），右边已选标签胶囊（强调色，新加的排在最后）；
/// 悬浮胶囊出现小叉去掉。
struct LabelPicker: View {
    let client: DivinationClient
    @Binding var selected: [NoteLabel]
    var onLabelDeleted: (Int) -> Void = { _ in }    // 标签被彻底删除（通知外面同步）

    @State private var showAdd = false

    var body: some View {
        ChipRow {
            Button { showAdd = true } label: {
                AddChipLabel(title: "标签")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAdd, arrowEdge: .bottom) {
                LabelSearchPopover(
                    client: client,
                    excludedIDs: Set(selected.map(\.id)),
                    onPick: { l in
                        if !selected.contains(where: { $0.id == l.id }) { selected.append(l) }   // 加在最后
                        showAdd = false
                    },
                    onDeleted: { id in
                        selected.removeAll { $0.id == id }
                        onLabelDeleted(id)
                    }
                )
            }
        } chips: {
            ForEach(selected) { l in
                RemovableChip(text: l.name, fill: Color.accentColor.opacity(0.15), foreground: .accentColor) {
                    selected.removeAll { $0.id == l.id }
                }
            }
        }
    }
}

/// 「＋ 标签」弹出的小浮窗：输入搜索（空 = 全部）、点一个选上、回车或「新建」建新标签；
/// 每行最右边的 × 彻底删除这个标签（先弹确认）。
/// 单独成一个 View、自己持有 @State。
/// ⚠️ macOS 的 popover 只在弹出那一刻按内容定一次大小，之后内容变多也不会长高（实测过）。
/// 所以这里用固定大小，列表在里面滚动；并且在 init 里就先查好结果，第一眼就有列表。
struct LabelSearchPopover: View {
    let client: DivinationClient
    let excludedIDs: Set<Int>                      // 已经选上的，不再列出
    var onPick: (NoteLabel) -> Void
    var onDeleted: (Int) -> Void

    @State private var query = ""
    @State private var matches: [NoteLabel]
    @State private var pendingDelete: NoteLabel?

    init(client: DivinationClient, excludedIDs: Set<Int>,
         onPick: @escaping (NoteLabel) -> Void, onDeleted: @escaping (Int) -> Void) {
        self.client = client
        self.excludedIDs = excludedIDs
        self.onPick = onPick
        self.onDeleted = onDeleted
        _matches = State(initialValue: client.labelSearch(keyword: ""))   // 弹出前就有内容
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("搜索或新建标签，如：疾病、感情", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(addTyped)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if matches.filter({ !excludedIDs.contains($0.id) }).isEmpty && trimmed.isEmpty {
                        Text("还没有标签，输入名字后回车即可新建")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    ForEach(matches.filter { !excludedIDs.contains($0.id) }) { l in
                        HStack(spacing: 6) {
                            Button { onPick(l) } label: {
                                Text(l.name)
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .help(l.name)
                            .buttonStyle(.plain)
                            Button { pendingDelete = l } label: {
                                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("彻底删除这个标签")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                    if !trimmed.isEmpty && !matches.contains(where: { $0.name == trimmed }) {
                        Button(action: addTyped) {
                            Label("新建标签「\(trimmed)」", systemImage: "plus.circle")
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(Color.accentColor)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible)                      // 标签多了：一直显示滚动条
        }
        .padding(12)
        .frame(width: 284, height: 280, alignment: .top)       // 固定大小，见上方说明
        .onChange(of: query) { _, _ in refresh() }
        .alert("删除标签「\(pendingDelete?.name ?? "")」？",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let l = pendingDelete, client.labelDelete(id: l.id) {
                    onDeleted(l.id)
                    refresh()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            let uses = pendingDelete?.uses ?? 0
            Text(uses > 0
                 ? "有 \(uses) 处笔记或排盘正在用这个标签，删除后它们上面的这个标签都会被去掉，无法恢复。"
                 : "删除后无法恢复。")
        }
    }

    private func refresh() {
        matches = client.labelSearch(keyword: trimmed)
    }

    /// 回车或点「新建」：同名已有就用已有的（标签名字唯一），没有就新建。
    private func addTyped() {
        guard !trimmed.isEmpty else { return }
        if let l = matches.first(where: { $0.name == trimmed }) ?? client.labelCreate(name: trimmed) { onPick(l) }
    }
}

/// 给 .sheet(item:) 用的排盘 id。
struct ChartID: Identifiable {
    let id: Int
}

/// 案主多选：已选胶囊 + 输入搜索下拉（选已有 / 新建同名）。
struct SubjectPicker: View {
    let client: DivinationClient
    @Binding var selected: [Subject]
    var allowAdd: Bool = true                     // 是否显示「搜索/新建」输入框
    var allowRemove: Bool = true                  // 悬浮是否出现删除小叉
    var onAdd: ((Subject) -> Void)? = nil         // 自定义添加（编辑态调后端）；nil = 仅改本地
    var onRemove: ((Subject) -> Void)? = nil      // 自定义删除（编辑态调后端）；nil = 仅改本地

    @State private var query = ""
    @State private var matches: [Subject] = []
    @State private var hovered: Int?        // 悬浮中的案主 id → 显示删除小叉

    /// 案主胶囊这一行的固定高度（胶囊 + 上方给小叉留的空间）。
    private let chipRowHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选案主：悬浮时右上角出现小叉，点击删除。
            // 没有案主时这一行也留着（固定高度），正文的位置不会因为加减案主而上下跳。
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selected) { s in
                        Text(s.name)
                            .font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.18)))
                            .overlay(alignment: .topTrailing) {
                                if allowRemove && hovered == s.id {
                                    Button { remove(s) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.callout)
                                            .foregroundStyle(.white, .gray)
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                }
                            }
                            .onHover { inside in
                                if inside { hovered = s.id }
                                else if hovered == s.id { hovered = nil }
                            }
                    }
                }
                .padding(.top, 6).padding(.trailing, 6)   // 给右上角小叉留出不被裁切的空间
            }
            .frame(height: chipRowHeight)

            if allowAdd {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    TextField("案主：输入以搜索或新建", text: $query)
                        .textFieldStyle(.plain)
                        .onChange(of: query) { _, v in refresh(v) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.10)))

                if !query.isEmpty {
                    dropdown
                }
            }
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches) { s in
                Button { add(s) } label: {
                    Text(s.name).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }.buttonStyle(.plain)
            }
            // 没有完全同名的 → 允许新建
            if !matches.contains(where: { $0.name == query }) {
                Button { createAndAdd() } label: {
                    Label("新建案主「\(query)」", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(Color.accentColor)
                }.buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    private func refresh(_ v: String) {
        matches = v.isEmpty ? [] : client.subjectSearch(keyword: v)
    }

    private func add(_ s: Subject) {
        if !selected.contains(where: { $0.id == s.id }) {
            if let onAdd { onAdd(s) }             // 编辑态：交给外部（调后端）
            else { selected.append(s) }           // 新建态：仅改本地
        }
        query = ""; matches = []
    }

    private func remove(_ s: Subject) {
        if let onRemove { onRemove(s) }                   // 编辑态：交给外部（调后端）
        else { selected.removeAll { $0.id == s.id } }     // 新建态：仅改本地
    }

    private func createAndAdd() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let s = client.subjectCreate(name: name) else { return }
        add(s)
    }
}
