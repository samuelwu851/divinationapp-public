import SwiftUI

/// 笔记里「插入排盘」的面板：先选术数（八字 / 易经速查 / 梅花易数），再填参数。
/// 排盘由后端 chart_create 完成并存进这份笔记，拿回 id 后交给编辑器插入卡片。
struct ChartInsertSheet: View {
    enum Kind: String, CaseIterable {
        case bazi = "八字"
        case iching = "易经速查"
        case meihua = "梅花易数"
    }

    let client: DivinationClient
    let noteId: Int
    var onInserted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .bazi
    @State private var errorMessage: String?

    // 八字
    @State private var name = ""
    @State private var isMale = true
    @State private var birth: DateParts = .now(defaultYear: 1990)

    // 易经速查：本卦 / 变卦，点爻变卦（同易经速查的变卦模式）
    @State private var original: Hexagram?
    @State private var changed: Hexagram?

    // 梅花易数（时间起卦）
    @State private var moment: DateParts = .now()

    var body: some View {
        VStack(spacing: 20) {
            Picker("", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            ScrollView {
                Group {
                    switch kind {
                    case .bazi: baziForm
                    case .iching: ichingForm
                    case .meihua: meihuaForm
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
        }
        .onChange(of: kind) { _, _ in errorMessage = nil }
    }

    // MARK: - 八字（同八字排盘页：姓名 + 性别 + 公历滚轮）

    private var baziForm: some View {
        VStack(spacing: 24) {
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
            DateWheels(parts: $birth, years: Array(1900...2100))
        }
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
            DateWheels(parts: $moment, years: Array(1950...2060))
            HStack(spacing: 16) {
                Text("地点：北京（默认）").foregroundStyle(.secondary)
                Button("现在") { moment = .now() }
            }
        }
    }

    // MARK: - 插入

    private func insert() {
        let id: Int?
        switch kind {
        case .bazi:
            var p = birth.params
            p["name"] = name.trimmingCharacters(in: .whitespaces)
            p["is_male"] = isMale
            id = client.chartCreate(noteId: noteId, type: "bazi", params: p)
        case .iching:
            guard let org = original, let chg = changed else { return }
            id = client.chartCreate(noteId: noteId, type: "iching",
                                    params: ["org_value": org.value, "chg_value": chg.value])
        case .meihua:
            id = client.chartCreate(noteId: noteId, type: "meihua", params: moment.params)
        }
        guard let id else { errorMessage = "排盘失败：引擎无响应"; return }
        onInserted(id)
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

    /// 当前年月的天数（换月后用来收回无效的日）。
    var dayRange: [Int] {
        let cal = Calendar.current
        if let d = cal.date(from: DateComponents(year: year, month: month)),
           let r = cal.range(of: .day, in: .month, for: d) { return Array(r) }
        return Array(1...31)
    }
}

/// 年 / 月 / 日 / 时 / 分 五个滚轮（同八字排盘页的样式）。
private struct DateWheels: View {
    @Binding var parts: DateParts
    let years: [Int]

    var body: some View {
        HStack(spacing: 12) {
            WheelPicker(title: "年", values: years, selection: $parts.year,
                        visibleRows: 3, valueFont: .title2).frame(width: 104)
            WheelPicker(title: "月", values: Array(1...12), format: { "\($0)月" },
                        selection: $parts.month, visibleRows: 3, valueFont: .title2).frame(width: 80)
            WheelPicker(title: "日", values: parts.dayRange, format: { "\($0)日" },
                        selection: $parts.day, visibleRows: 3, valueFont: .title2).frame(width: 80)
            WheelPicker(title: "时", values: Array(0...23), selection: $parts.hour,
                        visibleRows: 3, valueFont: .title2).frame(width: 80)
            WheelPicker(title: "分", values: Array(0...59), selection: $parts.minute,
                        visibleRows: 3, valueFont: .title2).frame(width: 80)
        }
        .onChange(of: parts.month) { _, _ in clampDay() }
        .onChange(of: parts.year) { _, _ in clampDay() }
    }

    private func clampDay() {
        if parts.day > parts.dayRange.count { parts.day = parts.dayRange.count }
    }
}
