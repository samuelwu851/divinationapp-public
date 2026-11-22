import SwiftUI

/// 编辑器目标：新建 / 编辑某条（带 note_id）。
enum NoteEditTarget: Hashable {
    case new
    case edit(Int)
}

/// 笔记编辑器（独立一页）：标题 + 案主多选 + 正文。保存走 note_create / note_update。
/// 说明：后端 note_update 目前只更新 title/body，不改案主——所以「编辑」时案主只读。
struct NoteEditorView: View {
    let client: DivinationClient
    let target: NoteEditTarget
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var subjects: [Subject] = []
    @State private var loaded = false

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("标题", text: $title)
                    .font(.title2).bold()
                    .textFieldStyle(.plain)

                SubjectPicker(client: client, selected: $subjects, editable: isNew)

                Divider()

                TextEditor(text: $bodyText)
                    .font(.body)
                    .frame(minHeight: 320)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("正文（支持 markdown，后续渲染）")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(20)
        }
        .background(PatternBackground())
        .navigationTitle(isNew ? "新建笔记" : "编辑笔记")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(title.isEmpty && bodyText.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let id) = target, let n = client.noteGet(id: id) {
            title = n.title
            bodyText = n.body ?? ""
            subjects = n.subjects ?? []
        }
    }

    private func save() {
        switch target {
        case .new:
            _ = client.noteCreate(title: title, body: bodyText, subjectIds: subjects.map(\.id))
        case .edit(let id):
            _ = client.noteUpdate(id: id, title: title, body: bodyText)
        }
        onSaved()
        dismiss()
    }
}

/// 案主多选：已选胶囊 + 输入搜索下拉（选已有 / 新建同名）。
struct SubjectPicker: View {
    let client: DivinationClient
    @Binding var selected: [Subject]
    var editable: Bool = true

    @State private var query = ""
    @State private var matches: [Subject] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选案主
            if !selected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selected) { s in
                            HStack(spacing: 4) {
                                Text(s.name).font(.subheadline)
                                if editable {
                                    Button { remove(s) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.caption)
                                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.gray.opacity(0.18)))
                        }
                    }
                }
            }

            if editable {
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
        if !selected.contains(s) { selected.append(s) }
        query = ""; matches = []
    }

    private func remove(_ s: Subject) {
        selected.removeAll { $0.id == s.id }
    }

    private func createAndAdd() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let s = client.subjectCreate(name: name) else { return }
        add(s)
    }
}
