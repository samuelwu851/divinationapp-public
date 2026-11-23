import SwiftUI

/// 案主列表（笔记窗口底部「人」图标进来）：搜索 + 全部案主（最近改过的在前），点一位进详情。
struct SubjectListView: View {
    let client: DivinationClient
    var open: (NotesRoute) -> Void

    @State private var subjects: [Subject] = []
    @State private var query = ""

    private var shown: [Subject] {
        let q = query.trimmingCharacters(in: .whitespaces)
        // 英文不区分大小写（同笔记搜索）
        return q.isEmpty ? subjects : subjects.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.remark ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索案主（名字或备注）", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
            .padding(12)

            Divider()

            if shown.isEmpty {
                Text(subjects.isEmpty ? "还没有案主（写笔记时可以新建）" : "没有符合的案主")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { s in
                    SubjectRow(subject: s)
                        .contentShape(Rectangle())
                        .onTapGesture { open(.subject(s.id)) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(PatternBackground())
        .navigationTitle("案主")
        .onAppear { subjects = client.subjectList() }        // 从详情返回时刷新（可能改了名、删了）
    }
}

/// 案主列表的一行：名字 + 备注（一行） | 右边笔记数。
private struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.title2)
                if let r = subject.remark, !r.isEmpty {
                    Text(r)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text("\(subject.noteCount ?? 0) 篇笔记")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// 案主详情：改名字 / 性别 / 生日 / 备注（点「保存」才写入）、删除案主，下面是和他关联的所有笔记。
struct SubjectDetailView: View {
    let client: DivinationClient
    let subjectId: Int
    var open: (NotesRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var remark = ""
    @State private var baseName = ""
    @State private var baseRemark = ""
    // 性别、生日：都可以不填。生日不填就没有时间；时间单独可不填（不知道时辰）
    @State private var gender: Int?                 // 1 男 / 0 女 / nil 未填
    @State private var hasBirthday = false
    // 生日用历史公历（1582 年以前儒略历，同八字）：系统日期选择器只认格里历，所以自己做年 / 月 / 日
    @State private var birthYear = 1990
    @State private var birthMonth = 1
    @State private var birthDay = 1
    @State private var hasBirthtime = false
    @State private var birthTime = SubjectDetailView.defaultBirth
    @State private var baseFields = BirthFields()
    @State private var notes: [Note] = []
    @State private var loaded = false
    @State private var missing = false
    @State private var showDelete = false
    @State private var showUnsaved = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDirty: Bool { name != baseName || remark != baseRemark || currentFields != baseFields }

    /// 生日 / 时间 / 性别 → 交给后端的字符串形式（也用来比较有没有改动）。
    private struct BirthFields: Equatable {
        var birthday: String?
        var birthtime: String?
        var gender: Int?
    }

    private var currentFields: BirthFields {
        BirthFields(birthday: hasBirthday ? String(format: "%04d-%02d-%02d", birthYear, birthMonth, birthDay) : nil,
                    birthtime: hasBirthday && hasBirthtime ? Self.timeFormatter.string(from: birthTime) : nil,
                    gender: gender)
    }

    private static let defaultBirth: Date =
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 1990, month: 1, day: 1, hour: 12)) ?? Date()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)      // 不跟系统日历走（用户可能设成农历/日本年号）
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let timeFormatter = formatter("HH:mm")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if missing {
                Text("这个案主已被删除").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("名字", text: $name)
                    .font(.title2).bold()
                    .textFieldStyle(.plain)

                birthSection

                VStack(alignment: .leading, spacing: 4) {
                    Text("备注").font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $remark)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 90)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
                }

                Divider()

                Text("相关笔记（\(notes.count)）").font(.headline)
                if notes.isEmpty {
                    Text("还没有关联的笔记").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NoteList(notes: notes, onOpen: { open(.editor(.edit($0))) },
                             onTrash: { client.noteTrash(id: $0); load() })
                        .padding(.horizontal, -20)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(PatternBackground())
        .navigationTitle("案主")
        .navigationBarBackButtonHidden(true)                 // 自定义返回：有没保存的修改先提示
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { if isDirty { showUnsaved = true } else { dismiss() } } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("删除", role: .destructive) { showDelete = true }
                    .disabled(missing)
                Button("保存") { save() }
                    .disabled(missing || !isDirty || trimmedName.isEmpty)
            }
        }
        .alert("删除案主「\(baseName)」？", isPresented: $showDelete) {
            if notes.isEmpty {
                Button("删除", role: .destructive) {
                    client.subjectDelete(id: subjectId)
                    dismiss()
                }
            } else {
                // 有笔记：问清楚笔记要不要一起删
                Button("只删除案主，保留笔记") {
                    client.subjectDelete(id: subjectId, withNotes: false)
                    dismiss()
                }
                Button("案主和 \(notes.count) 篇笔记都删除", role: .destructive) {
                    client.subjectDelete(id: subjectId, withNotes: true)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(notes.isEmpty ? "这个案主没有关联的笔记。"
                               : "这个案主关联了 \(notes.count) 篇笔记。\n「只删除案主」：笔记都保留，只是不再关联他。\n「都删除」：笔记放进回收站，以后还能恢复。")
        }
        .alert("有未保存的修改", isPresented: $showUnsaved) {
            Button("保存并返回") { save(); dismiss() }
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("案主的名字、性别、生日或备注改动还没保存。")
        }
        .onAppear(perform: load)                             // 从笔记编辑器返回时也刷新笔记列表
    }

    /// 性别（未填 / 男 / 女）+ 生日（可不填）+ 时间（可不填，不知道时辰）。
    private var birthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("性别").font(.callout).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                Picker("", selection: $gender) {
                    Text("未填").tag(Int?.none)
                    Text("男").tag(Int?.some(1))
                    Text("女").tag(Int?.some(0))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 12) {
                Text("生日").font(.callout).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                Toggle("", isOn: $hasBirthday).labelsHidden().toggleStyle(.checkbox)
                if hasBirthday {
                    BirthDateFields(year: $birthYear, month: $birthMonth, day: $birthDay)
                } else {
                    Text("未填").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // 时间单独一行（默认窗口宽度放不下和日期同一行）；不知道时辰就不勾
            if hasBirthday {
                HStack(spacing: 12) {
                    Text("时间").font(.callout).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                    Toggle("", isOn: $hasBirthtime).labelsHidden().toggleStyle(.checkbox)
                    if hasBirthtime {
                        DatePicker("", selection: $birthTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    } else {
                        Text("未填（不知道时辰）").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func load() {
        guard let d = client.subjectGet(id: subjectId) else { missing = true; return }
        notes = d.notes
        if !loaded {                                         // 名字 / 备注等只在第一次载入，别覆盖正在改的内容
            apply(d)
            loaded = true
        }
    }

    /// 把后端的案主数据填进界面，并记成基线（判断有没有未保存的修改）。
    private func apply(_ d: SubjectDetail) {
        name = d.name; remark = d.remark
        gender = d.gender
        hasBirthday = d.birthday != nil
        if let b = d.birthday {
            let ymd = b.split(separator: "-").compactMap { Int($0) }
            if ymd.count == 3 { birthYear = ymd[0]; birthMonth = ymd[1]; birthDay = ymd[2] }
        }
        hasBirthtime = d.birthtime != nil
        if let t = d.birthtime, let time = Self.timeFormatter.date(from: t) { birthTime = time }
        baseName = d.name; baseRemark = d.remark
        baseFields = currentFields
        notes = d.notes
    }

    private func save() {
        let f = currentFields
        guard !trimmedName.isEmpty,
              let d = client.subjectUpdate(id: subjectId, name: trimmedName, remark: remark,
                                           birthday: f.birthday, birthtime: f.birthtime, gender: f.gender) else { return }
        apply(d)
    }
}

/// 案主生日的年 / 月 / 日（历史公历，同八字滚轮：1582 年以前按儒略历，1582 年 10 月没有 5–14 日）。
/// 年份直接输入（回车或点别处生效，限 1–2200），月、日用下拉菜单；换年月后日不存在就挪到最近的有效日。
private struct BirthDateFields: View {
    @Binding var year: Int
    @Binding var month: Int
    @Binding var day: Int

    @State private var yearText = ""
    @FocusState private var yearFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("年", text: $yearText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(YearWheel.fieldFill))   // 同年份滚轮的输入框：柔和灰白
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(YearWheel.fieldStroke, lineWidth: 1))
                .frame(width: 64)
                .focused($yearFocused)
                .onSubmit(commitYear)
                .onChange(of: yearFocused) { _, now in if !now { commitYear() } }
            Text("年")
            Picker("", selection: $month) {
                ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
            }
            .labelsHidden().fixedSize()
            Picker("", selection: $day) {
                ForEach(HistoricalCalendar.days(year: year, month: month), id: \.self) { Text("\($0)日").tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        .onAppear { yearText = String(year) }
        .onChange(of: year) { _, v in if !yearFocused { yearText = String(v) }; clampDay() }
        .onChange(of: month) { _, _ in clampDay() }
    }

    private func commitYear() {
        if let v = Int(yearText.filter(\.isNumber)) {
            year = min(max(v, HistoricalCalendar.baziYears.lowerBound), HistoricalCalendar.baziYears.upperBound)
        }
        yearText = String(year)
    }

    private func clampDay() {
        day = HistoricalCalendar.clamp(day: day, year: year, month: month)
    }
}
