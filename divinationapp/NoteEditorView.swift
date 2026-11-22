import SwiftUI

/// 编辑器目标：新建 / 编辑某条（带 note_id）。
enum NoteEditTarget: Hashable {
    case new
    case edit(Int)
}

/// 笔记编辑器（独立一页）：标题 + 案主多选 + 正文（网页编辑器 TipTap，见 NoteEditorWebView）。
///
/// - 新建：一进来就在数据库里建一份空笔记，之后和「编辑」走同一套流程
///   （插入排盘、图片都需要先有 note_id）。没保存就离开 → 整份删掉。
/// - 保存：标题/正文走 note_update；案主对比基线做差量增删。
/// - 离开时：调 note_cleanup，清掉正文里已经不引用的排盘和图片
///   （编辑中插入后又删掉的、或放弃修改的）。
struct NoteEditorView: View {
    let client: DivinationClient
    let target: NoteEditTarget
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var noteId: Int?
    @State private var createdHere = false      // 这份笔记是本次「新建」时建的
    @State private var saved = false
    @State private var finished = false

    @State private var title = ""
    @State private var subjects: [Subject] = []
    @State private var bodyChanged = false      // 网页编辑器通知「正文改过」
    @State private var loaded = false

    // 基线：载入时的原始值，用来判断「有没有未保存的修改」
    @State private var baseTitle = ""
    @State private var baseSubjectIDs: Set<Int> = []

    @State private var showUnsavedAlert = false
    @State private var showInsertChart = false
    @State private var showPickPosition = false   // 光标不在正文 → 提示先选位置
    @State private var openChart: ChartID?
    @State private var editor = NoteEditorController()

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    /// 当前是否有未保存的改动。
    private var isDirty: Bool {
        title != baseTitle
            || bodyChanged
            || Set(subjects.map(\.id)) != baseSubjectIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题", text: $title)
                .font(.title2).bold()
                .textFieldStyle(.plain)

            // 案主增删只改本地，点「保存」时才写后端
            SubjectPicker(client: client, selected: $subjects)

            Divider()

            if let noteId {
                NoteEditorWebView(controller: editor)
                    .padding(.horizontal, -20)                  // 网页自己留了左右边距
                    .sheet(isPresented: $showInsertChart) {
                        ChartInsertSheet(client: client, noteId: noteId) { editor.insertChart(id: $0) }
                    }
                    .sheet(item: $openChart) { c in        // 只有非 macOS 会用到（macOS 开独立窗口）
                        ChartDetailView(client: client, chartId: c.id)
                    }
            } else if loaded {
                Text("笔记创建失败").foregroundStyle(.red)
                Spacer()
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
                Button("插入排盘") { requestInsertChart() }
                    .disabled(noteId == nil)
                Button("保存") { save() }
                    .disabled(noteId == nil || !isDirty)
            }
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
            Text("当前的标题、正文或案主改动还没保存，确定要离开吗？")
        }
        .onAppear(perform: load)
        .onDisappear(perform: finish)
    }

    private func load() {
        guard !loaded else { return }
        var content = ""
        switch target {
        case .new:
            if let n = client.noteCreate(title: "", body: "") {
                noteId = n.id
                createdHere = true
            }
        case .edit(let id):
            if let n = client.noteGet(id: id) {
                noteId = id
                title = n.title
                content = n.body ?? ""
                subjects = n.subjects ?? []
            }
        }
        // 记录基线（新建则全为空）
        baseTitle = title
        baseSubjectIDs = Set(subjects.map(\.id))
        loaded = true

        guard let noteId else { return }
        editor.onChange = { bodyChanged = true }
        editor.onOpenChart = { id in
            #if os(macOS)
            openWindow(id: "chart", value: id)    // 独立窗口：可以边看排盘边写笔记
            #else
            openChart = ChartID(id: id)
            #endif
        }
        editor.load(noteId: noteId, content: content)
    }

    /// 「插入排盘」：光标在正文里才打开排盘面板，排完插到光标处；否则提示先在正文里点一下。
    private func requestInsertChart() {
        Task {
            if await editor.cursorInBody() { showInsertChart = true } else { showPickPosition = true }
        }
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
            saved = true
            onSaved()
            dismiss()
        }
    }

    /// 离开编辑器（保存、放弃、关窗都会走到这里）：新建且没保存 → 整份删；否则清理没引用的排盘和图片。
    private func finish() {
        guard !finished, let id = noteId else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选案主：悬浮时右上角出现小叉，点击删除
            if !selected.isEmpty {
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
            }

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
