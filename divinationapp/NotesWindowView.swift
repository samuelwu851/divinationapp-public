import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 笔记（案例库）独立窗口：顶部搜索栏 + 笔记列表，右下角悬浮「笔」按钮新建。
/// 列表点一条 → 进编辑器（编辑）；点笔 → 进编辑器（新建）。编辑器是独立一页（NavigationStack 推入）。
struct NotesWindowView: View {
    private let client = DivinationClient()

    @State private var search = ""
    @State private var notes: [Note] = []
    @State private var editTarget: NoteEditTarget?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    list
                }

                // 右下角悬浮「笔」按钮（样式参考发推按钮：实心圆 + 阴影）
                Button { editTarget = .new } label: {
                    PenIcon(color: .white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .padding(16)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .frame(minWidth: 300, minHeight: 360)
            .background(PatternBackground())          // 与排盘同款背景纹理
            .navigationDestination(item: $editTarget) { target in
                NoteEditorView(client: client, target: target) { reload() }
            }
            #if os(macOS)
            .background(NotesWindowAccessor())         // 注册到窗口管理器（贴合主窗）
            #endif
        }
        .onAppear { reload() }
    }

    // MARK: - 顶部搜索栏（先把样子做出来，功能后说）

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索笔记", text: $search)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
        .padding(12)
    }

    // MARK: - 笔记列表

    private var list: some View {
        Group {
            if notes.isEmpty {
                VStack(spacing: 6) {
                    Text("还没有笔记").foregroundStyle(.secondary)
                    Text("点右下角的笔新建").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    List(notes) { note in
                        NoteRow(note: note,
                                maxTextWidth: geo.size.width * 0.75,   // 标题/预览最多占 3/4 宽
                                windowWidth: geo.size.width)           // 时间按窗宽决定全显/省略
                            .contentShape(Rectangle())
                            .onTapGesture { editTarget = .edit(note.id) }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)   // 透出背景纹理
                }
            }
        }
    }

    private func reload() { notes = client.noteList() }
}

/// 列表里的一条笔记。
/// 左：案主胶囊(可多个) + 标题，下方正文预览；右上：label（算什么事，预留）；右下：创建/修改时间（自适应）。
private struct NoteRow: View {
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
                            Text(s.name)
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
private struct NotesWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { CasebookWindowManager.shared.registerNotes(w) }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
