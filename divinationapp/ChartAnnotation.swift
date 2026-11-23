import SwiftUI

/// 排盘窗口里的「所问之事 + 特点」（左对齐）：
/// - 所问之事：一行输入框，回车或点别处就存；
/// - 特点：横排胶囊（最多显示 8 个字，悬停看全名），可以左右滑；最左边「＋ 特点」弹出小浮窗搜索 / 新建 / 删除；
///   悬浮胶囊出现小叉去掉。
/// 改了以后发通知，笔记正文里的排盘卡片跟着刷新（NoteEditorView 收到后让网页重画）。
struct ChartAnnotationView: View {
    let client: DivinationClient
    let chartId: Int

    @State private var question: String
    @State private var savedQuestion: String
    @State private var tags: [ChartTag]
    @State private var showAdd = false
    @State private var hovered: Int?
    @FocusState private var editing: Bool

    /// 某个排盘的所问之事 / 特点改了（object = 排盘 id）。
    static let changedNotification = Notification.Name("chartAnnotationChanged")

    init(client: DivinationClient, chartId: Int, question: String, tags: [ChartTag]) {
        self.client = client
        self.chartId = chartId
        _question = State(initialValue: question)
        _savedQuestion = State(initialValue: question)
        _tags = State(initialValue: tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("所问之事").font(.callout).foregroundStyle(.secondary)
                TextField("可不填", text: $question)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($editing)
                    .onSubmit(saveQuestion)
                    .onChange(of: editing) { _, now in if !now { saveQuestion() } }
            }
            tagRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear(perform: saveQuestion)                 // 关窗前没按回车也存
    }

    // MARK: - 特点

    private var tagRow: some View {
        HStack(spacing: 6) {
            Button { showAdd = true } label: {
                Label("特点", systemImage: "plus")
                    .font(.subheadline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAdd, arrowEdge: .bottom) {
                TagSearchPopover(client: client, excludedIDs: Set(tags.map(\.id)),
                                 onPick: { name in add(name) },
                                 onDeleted: { id in tags.removeAll { $0.id == id }; changed() })
            }
            .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {        // 特点多了左右滑
                HStack(spacing: 6) {
                    ForEach(tags) { t in chip(t) }
                }
                .padding(.top, 6).padding(.trailing, 8)               // 给小叉留空间
            }
        }
        .frame(height: 34)
    }

    private func chip(_ t: ChartTag) -> some View {
        Text(t.name.count > 8 ? String(t.name.prefix(8)) + "…" : t.name)   // 最多 8 个字
            .font(.subheadline)
            .lineLimit(1)
            .help(t.name)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .overlay(alignment: .topTrailing) {
                if hovered == t.id {
                    Button { remove(t) } label: {
                        Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.white, .gray)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            .onHover { inside in
                if inside { hovered = t.id } else if hovered == t.id { hovered = nil }
            }
    }

    // MARK: - 存

    private func saveQuestion() {
        guard question != savedQuestion else { return }
        guard let q = client.chartQuestion(id: chartId, question: question) else { question = savedQuestion; return }
        question = q
        savedQuestion = q
        changed()
    }

    /// 加一个特点。浮窗不关（可以连续加几个），点别处才关。
    private func add(_ name: String) {
        if let t = client.chartTagAdd(chartId: chartId, name: name) { tags = t; changed() }
    }

    private func remove(_ t: ChartTag) {
        if let r = client.chartTagRemove(chartId: chartId, tagId: t.id) { tags = r; changed() }
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.changedNotification, object: chartId)
    }
}

/// 「＋ 特点」弹出的小浮窗：输入搜索（空 = 全部）、点一个加上、回车或「新建」建新特点；
/// 加了以后浮窗不关、加上的那个从列表里消失，可以接着加；点别处才关。
/// 每行最右边的 × 彻底删除这个特点（所有排盘上一起去掉，先确认）。
/// ⚠️ macOS 的 popover 只在弹出时定一次大小：固定大小，列表在里面滚动；init 里先查好，第一眼就有列表。
struct TagSearchPopover: View {
    let client: DivinationClient
    let excludedIDs: Set<Int>
    var onPick: (String) -> Void
    var onDeleted: (Int) -> Void

    @State private var query = ""
    @State private var matches: [ChartTag]
    @State private var pendingDelete: ChartTag?

    init(client: DivinationClient, excludedIDs: Set<Int>, onPick: @escaping (String) -> Void, onDeleted: @escaping (Int) -> Void) {
        self.client = client
        self.excludedIDs = excludedIDs
        self.onPick = onPick
        self.onDeleted = onDeleted
        _matches = State(initialValue: client.tagSearch(keyword: ""))
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var shown: [ChartTag] { matches.filter { !excludedIDs.contains($0.id) } }

    /// 选上一个：交给外面存，然后清空输入、刷新列表（新建的特点也会出现在列表里，用过的次数也更新）。
    private func pick(_ name: String) {
        onPick(name)
        query = ""
        matches = client.tagSearch(keyword: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索或新建特点", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { if !trimmed.isEmpty { pick(trimmed) } }
                    .onChange(of: query) { _, v in matches = client.tagSearch(keyword: v.trimmingCharacters(in: .whitespaces)) }
            }
            .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !trimmed.isEmpty && !matches.contains(where: { $0.name == trimmed }) {
                        Button { pick(trimmed) } label: {
                            Label("新建特点「\(trimmed)」", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(shown) { t in
                        HStack {
                            Text(t.name).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 4)
                            Button { pendingDelete = t } label: {
                                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("彻底删除这个特点")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { pick(t.name) }
                    }
                    if shown.isEmpty && trimmed.isEmpty {
                        Text("还没有特点，输入名字新建").font(.callout).foregroundStyle(.secondary).padding(10)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 260, height: 280)
        .alert("彻底删除特点「\(pendingDelete?.name ?? "")」？",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let t = pendingDelete {
                    client.tagDelete(id: t.id)
                    matches.removeAll { $0.id == t.id }
                    onDeleted(t.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("有 \(pendingDelete?.uses ?? 0) 个排盘用了它，会一起去掉。")
        }
    }
}


/// 八字排盘窗口里、乾造 / 坤造右边的姓名输入框：回车或点别处就存（可以清空）。
/// 姓名也能当案主来搜：选了案主「张三」，里面有姓名是张三的八字的笔记也会出来。
struct BaziNameField: View {
    let client: DivinationClient
    let chartId: Int
    var onChanged: (String) -> Void

    @State private var name: String
    @State private var saved: String
    @FocusState private var focused: Bool

    init(client: DivinationClient, chartId: Int, name: String, onChanged: @escaping (String) -> Void) {
        self.client = client
        self.chartId = chartId
        self.onChanged = onChanged
        _name = State(initialValue: name)
        _saved = State(initialValue: name)
    }

    var body: some View {
        TextField("姓名（可不填）", text: $name)
            .textFieldStyle(.plain)
            .font(.title).bold()
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if !now { save() } }
            .onDisappear(perform: save)
            .frame(maxWidth: 260)
    }

    private func save() {
        guard name != saved else { return }
        guard let n = client.chartName(id: chartId, name: name) else { name = saved; return }
        name = n
        saved = n
        onChanged(n)
        NotificationCenter.default.post(name: ChartAnnotationView.changedNotification, object: chartId)   // 卡片跟着变
    }
}
