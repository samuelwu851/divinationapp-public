import SwiftUI

/// 笔记里「插入排盘」的面板：先选术数（八字 / 易经速查 / 梅花易数，以及注册进来的其他类型），再填参数。
/// 排盘由后端 chart_create 完成并存进这份笔记，拿回 id 后交给编辑器插入卡片。
struct ChartInsertSheet: View {
    /// 分段控件的一项：内置三种，或注册表里的类型（tag 用后端排盘类型名）。
    private struct Tab: Hashable { let type: String; let title: String }
    private static let builtinTabs = [Tab(type: "bazi", title: "八字"),
                                      Tab(type: "iching", title: "易经速查"),
                                      Tab(type: "meihua", title: "梅花易数")]
    private var tabs: [Tab] {
        Self.builtinTabs + ChartKindRegistry.kinds.map { Tab(type: $0.type, title: $0.title) }
    }

    let client: DivinationClient
    let noteId: Int
    var subjects: [Subject] = []          // 这份笔记当前的案主（八字可一键带入案主的生日）
    var onInserted: (_ chartId: Int, _ type: String) -> Void     // 排盘 id + 排盘类型（编辑器据此自动勾上术数）

    @Environment(\.dismiss) private var dismiss

    @State private var kind = "bazi"
    @State private var errorMessage: String?

    // 八字
    @State private var name = ""
    @State private var isMale = true
    @State private var birth = DateInputModel(years: HistoricalCalendar.baziYears, initial: .now(defaultYear: 1990))
    @State private var subjectDetails: [SubjectDetail] = []   // 案主的完整资料（含生日、性别）
    @State private var filledFrom: Int?                       // 刚从哪位案主带入（高亮用）
    @State private var incompleteHint: String?                // 点了资料不全的案主 → 说明缺什么

    // 易经速查：本卦 / 变卦，点爻变卦（同易经速查的变卦模式）
    @State private var original: Hexagram?
    @State private var changed: Hexagram?

    // 梅花易数（时间起卦）
    @State private var moment = DateInputModel(years: 1950...2060, initial: .now())

    // 注册表里的类型：表单交出来的参数
    @State private var pluginParams: [String: Any]?

    var body: some View {
        VStack(spacing: 20) {
            Picker("", selection: $kind) {
                ForEach(tabs, id: \.self) { Text($0.title).tag($0.type) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 120 * CGFloat(tabs.count))

            ScrollView {
                Group {
                    switch kind {
                    case "bazi": baziForm
                    case "iching": ichingForm
                    case "meihua": meihuaForm
                    default:
                        if let k = ChartKindRegistry.kind(for: kind) {
                            k.makeInsertForm { pluginParams = $0 }
                                .id(k.type)              // 换类型时表单重建，状态归零
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            HStack(spacing: 16) {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button { insert() } label: {
                    Text("插入").font(.headline).padding(.horizontal, 20)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(minWidth: 540, idealWidth: 560, minHeight: 560, idealHeight: 600)
        .background(PatternBackground())
        .onAppear {
            if original == nil {
                original = client.lookup(63)
                changed = original
            }
            if subjectDetails.isEmpty {
                subjectDetails = subjects.compactMap { client.subjectGet(id: $0.id) }
            }
        }
        .onChange(of: kind) { _, _ in errorMessage = nil; pluginParams = nil }
    }

    // MARK: - 八字（同八字排盘页：姓名 + 性别 + 公历滚轮）

    private var baziForm: some View {
        VStack(spacing: 24) {
            if !subjectDetails.isEmpty { subjectBaziRow }
            HStack(spacing: 16) {
                Text("姓名").font(.title3)
                TextField("可不填", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                    .frame(width: 200)
                Picker("", selection: $isMale) {
                    Text("男").tag(true)
                    Text("女").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }
            CalendarModeSwitch(model: birth)
            DateInputWheels(model: birth)
        }
    }

    /// 「插入案主八字：张三、李四」：点一位 → 把他的名字、性别、生日时间填进下面的表单（再点「插入」）。
    /// 生日、时间、性别要齐全才能点；不齐的灰掉，悬停说明缺什么。
    private var subjectBaziRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("插入案主八字：").font(.callout).foregroundStyle(.secondary)
                // 不用 .disabled：macOS 上禁用的控件收不到鼠标悬停，.help 提示不会出现。
                // 改成资料不全时灰色显示、点了在下面说明缺什么。
                ForEach(subjectDetails, id: \.id) { d in
                    let missing = Self.missingBirthInfo(d)
                    Text(d.name)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(filledFrom == d.id ? Color.accentColor.opacity(0.25)
                                                                      : Color.gray.opacity(0.15)))
                        .foregroundStyle(missing == nil ? Color.primary : Color.secondary)
                        .opacity(missing == nil ? 1 : 0.6)
                        .contentShape(Capsule())
                        .onTapGesture {
                            if let missing { incompleteHint = Self.incompleteText(d, missing) } else { fill(from: d) }
                        }
                        .help(missing.map { Self.incompleteText(d, $0) } ?? "带入 \(d.name) 的生日时间")
                }
            }
            if let incompleteHint {
                Text(incompleteHint).font(.caption).foregroundStyle(.secondary)
            } else if subjectDetails.allSatisfy({ Self.missingBirthInfo($0) != nil }) {
                Text("案主的生日、时间或性别还没填完整，可以在「案主」页面补上").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static func incompleteText(_ d: SubjectDetail, _ missing: String) -> String {
        "\(d.name) 的资料不完整：缺\(missing)（在案主页面补上）"
    }

    /// 案主排八字缺什么（生日、时间、性别都要有，且年份在滚轮范围内）；齐全返回 nil。
    private static func missingBirthInfo(_ d: SubjectDetail) -> String? {
        var miss: [String] = []
        if birthParts(d) == nil { miss.append(d.birthday == nil ? "生日" : (d.birthtime == nil ? "时间" : "有效的生日")) }
        if d.gender == nil { miss.append("性别") }
        return miss.isEmpty ? nil : miss.joined(separator: "、")
    }

    /// "1990-05-01" + "08:30" → DateParts；缺任何一项、格式不对或年份超出八字范围（公元 1–2200）都返回 nil。
    private static func birthParts(_ d: SubjectDetail) -> DateParts? {
        guard let b = d.birthday, let t = d.birthtime else { return nil }
        let ymd = b.split(separator: "-").compactMap { Int($0) }
        let hm = t.split(separator: ":").compactMap { Int($0) }
        guard ymd.count == 3, hm.count == 2, HistoricalCalendar.baziYears.contains(ymd[0]) else { return nil }
        return DateParts(year: ymd[0], month: ymd[1], day: ymd[2], hour: hm[0], minute: hm[1])
    }

    private func fill(from d: SubjectDetail) {
        guard let parts = Self.birthParts(d), let g = d.gender else { return }
        name = d.name
        isMale = g == 1
        birth.setSolar(parts)
        filledFrom = d.id
        incompleteHint = nil
    }

    // MARK: - 易经速查（点爻变卦）

    private var ichingForm: some View {
        VStack(spacing: 12) {
            Text("点爻可以变卦：点本卦的爻改本卦，点变卦的爻改变卦")
                .font(.callout).foregroundStyle(.secondary)
            if let org = original, let chg = changed {
                HStack(alignment: .top, spacing: 40) {
                    VStack(spacing: 6) {
                        Text("本卦").font(.caption).foregroundStyle(.secondary)
                        HexagramPanelView(hex: org, compact: true, changingLines: movingLines(org, chg),
                                          showArrow: true,
                                          onFlip: { original = client.flip(value: org.value, line: $0) ?? org })
                    }
                    VStack(spacing: 6) {
                        Text("变卦").font(.caption).foregroundStyle(.secondary)
                        HexagramPanelView(hex: chg, compact: true, changingLines: movingLines(org, chg),
                                          onFlip: { changed = client.flip(value: chg.value, line: $0) ?? chg })
                    }
                }
            } else {
                ProgressView()
            }
        }
    }

    // MARK: - 梅花易数（同时间起卦：日期 + 时间滚轮）

    private var meihuaForm: some View {
        VStack(spacing: 16) {
            CalendarModeSwitch(model: moment)
            DateInputWheels(model: moment)
            HStack(spacing: 16) {
                Text("地点：北京（默认）").foregroundStyle(.secondary)
                Button("现在") { moment.setSolar(.now()) }
            }
        }
    }

    // MARK: - 插入

    private func insert() {
        let id: Int?
        switch kind {
        case "bazi":
            guard let b = birth.resolvedSolar() else { errorMessage = "农历日期换算失败"; return }
            var p = b.params
            p["name"] = name.trimmingCharacters(in: .whitespaces)
            p["is_male"] = isMale
            id = client.chartCreate(noteId: noteId, type: "bazi", params: p)
        case "iching":
            guard let org = original, let chg = changed else { return }
            id = client.chartCreate(noteId: noteId, type: "iching",
                                    params: ["org_value": org.value, "chg_value": chg.value])
        case "meihua":
            guard let m = moment.resolvedSolar() else { errorMessage = "农历日期换算失败"; return }
            id = client.chartCreate(noteId: noteId, type: "meihua", params: m.params)
        default:
            guard let p = pluginParams else { errorMessage = "请先把参数填完整"; return }
            id = client.chartCreate(noteId: noteId, type: kind, params: p)
        }
        guard let id else { errorMessage = "排盘失败：引擎无响应"; return }
        onInserted(id, kind)
        dismiss()
    }

    private func movingLines(_ a: Hexagram, _ b: Hexagram) -> Set<Int> {
        Set((0..<min(a.lines.count, b.lines.count)).filter { a.lines[$0] != b.lines[$0] })
    }
}

/// 年月日时分。
struct DateParts {
    var year: Int, month: Int, day: Int, hour: Int, minute: Int

    static func now(defaultYear: Int? = nil) -> DateParts {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        return DateParts(year: defaultYear ?? c.year ?? 2026, month: c.month ?? 1, day: c.day ?? 1,
                         hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    var params: [String: Any] {
        ["year": year, "month": month, "day": day, "hour": hour, "minute": minute]
    }

    /// 当前年月有哪几天（历史公历：1582 年以前按儒略历，见 HistoricalCalendar）。
    var dayRange: [Int] { HistoricalCalendar.days(year: year, month: month) }
}
