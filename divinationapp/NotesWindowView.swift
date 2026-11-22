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
                List(notes) { note in
                    NoteRow(note: note)
                        .contentShape(Rectangle())
                        .onTapGesture { editTarget = .edit(note.id) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)   // 透出背景纹理
            }
        }
    }

    private func reload() { notes = client.noteList() }
}

/// 列表里的一条笔记。
/// 左：案主胶囊(可多个) + 标题，下方正文预览；右上：label（算什么事，预留）；右下：创建/修改时间（自适应）。
private struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧：案主 + 标题 + 预览
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(note.subjects ?? []) { s in
                        Text(s.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.18)))
                    }
                    Text(note.title.isEmpty ? "无标题" : note.title)
                        .font(.title3).bold()
                        .lineLimit(1)
                }
                if let p = note.preview, !p.isEmpty {
                    Text(String(p.prefix(16)))        // 预览只取前 16 字
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // 右侧：上=label，下=时间
            VStack(alignment: .trailing, spacing: 4) {
                if let labels = note.labels, !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels.prefix(3), id: \.self) { l in
                            Text(l).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                Spacer(minLength: 2)
                stampLine("创建", note.createdAt)
                stampLine("改", note.updatedAt)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56)
    }

    /// 时间戳，按可用宽度自适应：全(年月日 时分) → 年月日+省略 → 年月日。
    @ViewBuilder
    private func stampLine(_ label: String, _ raw: String) -> some View {
        let date = String(raw.prefix(10))
        let time = raw.count >= 16 ? String(raw.dropFirst(11).prefix(5)) : ""
        ViewThatFits(in: .horizontal) {
            Text("\(label) \(date) \(time)")
            Text("\(label) \(date) …")
            Text("\(label) \(date)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
