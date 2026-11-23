import SwiftUI

/// 按四柱反推时间（八字页、梅花易数共用）：选年月日时四柱 →「查找时间」→ 列出公元 1–2200 年里对得上的时刻，
/// 点一个 → onPick（交出那个时辰中间的一刻）。
/// - 年柱、日柱：天干、地支分开选（一开始空着）；天干列全，地支只列和天干同阴阳的；
/// - 月柱、时柱：一个下拉列 12 个整柱，天干由五虎遁（年干）/ 五鼠遁（日干）推出；没选年干 / 日干时按不了。
struct PillarsReverseInput: View {
    let client: DivinationClient
    var pickTitle = "点一个排盘："
    var onPick: (DateParts) -> Void

    @State private var yearGan: Int?
    @State private var yearZhi: Int?
    @State private var dayGan: Int?
    @State private var dayZhi: Int?
    @State private var monthZhi: Int?
    @State private var hourZhi: Int?
    @State private var matches: [ReverseMatch]?
    @State private var errorMessage: String?
    @State private var pickedId: String?


    private static let ganChars = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    private static let zhiChars = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)

    // 五虎遁：某年干的寅月天干；五鼠遁：某日干的子时天干
    private static func monthGan(yearGan: Int, zhi: Int) -> Int { ((yearGan % 5) * 2 + 2 + (zhi - 2 + 12) % 12) % 10 }
    private static func hourGan(dayGan: Int, zhi: Int) -> Int { ((dayGan % 5) * 2 + zhi) % 10 }
    private static let monthOrder = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 1]     // 正月（寅）起

    private var monthPillar: String? {
        guard let g = yearGan, let z = monthZhi else { return nil }
        return Self.ganChars[Self.monthGan(yearGan: g, zhi: z)] + Self.zhiChars[z]
    }
    private var hourPillar: String? {
        guard let g = dayGan, let z = hourZhi else { return nil }
        return Self.ganChars[Self.hourGan(dayGan: g, zhi: z)] + Self.zhiChars[z]
    }
    private func pillar(_ g: Int?, _ z: Int?) -> String? {
        guard let g, let z else { return nil }
        return Self.ganChars[g] + Self.zhiChars[z]
    }
    private var allChosen: Bool {
        pillar(yearGan, yearZhi) != nil && monthPillar != nil && pillar(dayGan, dayZhi) != nil && hourPillar != nil
    }

    var body: some View {
        VStack(spacing: 18) {
            pillarsInput
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            if let matches { matchList(matches) }
        }
    }

    /// 四柱：年柱、日柱分开选干和支；月柱、时柱各一个下拉（五虎遁 / 五鼠遁列出 12 个）。
    private var pillarsInput: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 26) {
                column("年柱", pillar(yearGan, yearZhi)) {
                    ganZhiPickers(gan: $yearGan, zhi: $yearZhi)
                }
                column("月柱", monthPillar) {
                    // 没选年干就不能选：月干要靠年干推
                    Picker("", selection: $monthZhi) {
                        Text("—").tag(Int?.none)
                        ForEach(Self.monthOrder, id: \.self) { z in
                            Text(yearGan.map { Self.ganChars[Self.monthGan(yearGan: $0, zhi: z)] + Self.zhiChars[z] } ?? "")
                                .tag(Int?.some(z))
                        }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(yearGan == nil)
                    .help(yearGan == nil ? "先选年干（月干由年干推出：五虎遁）" : "")
                }
                column("日柱", pillar(dayGan, dayZhi)) {
                    ganZhiPickers(gan: $dayGan, zhi: $dayZhi)
                }
                column("时柱", hourPillar) {
                    // 没选日干就不能选：时干要靠日干推
                    Picker("", selection: $hourZhi) {
                        Text("—").tag(Int?.none)
                        ForEach(0..<12, id: \.self) { z in
                            Text(dayGan.map { Self.ganChars[Self.hourGan(dayGan: $0, zhi: z)] + Self.zhiChars[z] } ?? "")
                                .tag(Int?.some(z))
                        }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(dayGan == nil)
                    .help(dayGan == nil ? "先选日干（时干由日干推出：五鼠遁）" : "")
                }
            }
            Button { findTimes() } label: {
                Text("查找时间").font(.headline).padding(.vertical, 8).padding(.horizontal, 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allChosen)
            Text("在公元 1–2200 年里找四柱都对得上的时刻；1582 年以前按儒略历").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 一柱：标题 + 选好后的干支（大字，五行上色；没选好显示空位）+ 下面的选择。
    private func column<C: View>(_ title: String, _ value: String?, @ViewBuilder _ pickers: () -> C) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let value {
                BaziPillarsView(pillars: [value])
            } else {
                VStack(spacing: 2) {
                    Text("　").font(.largeTitle)
                    Text("　").font(.largeTitle)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25), style: StrokeStyle(dash: [3, 3])))
            }
            pickers()
        }
    }

    /// 天干 + 地支两个下拉：天干永远列全 10 个；地支只列和天干同阴阳的（阳干配阳支）。
    /// 先选了地支、再选一个阴阳不同的天干：地支清空，重新选。
    private func ganZhiPickers(gan: Binding<Int?>, zhi: Binding<Int?>) -> some View {
        VStack(spacing: 4) {
            Picker("", selection: Binding(get: { gan.wrappedValue }, set: { g in
                gan.wrappedValue = g
                if let g, let z = zhi.wrappedValue, z % 2 != g % 2 { zhi.wrappedValue = nil }
            })) {
                Text("干").tag(Int?.none)
                ForEach(0..<10, id: \.self) { g in Text(Self.ganChars[g]).tag(Int?.some(g)) }
            }
            .labelsHidden().fixedSize()
            Picker("", selection: zhi) {
                Text("支").tag(Int?.none)
                ForEach(0..<12, id: \.self) { z in
                    if gan.wrappedValue.map({ $0 % 2 == z % 2 }) ?? true { Text(Self.zhiChars[z]).tag(Int?.some(z)) }
                }
            }
            .labelsHidden().fixedSize()
        }
    }

    private func matchList(_ list: [ReverseMatch]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.isEmpty ? "公元 1–2200 年里没有对得上的时刻" : "找到 \(list.count) 个时刻，\(pickTitle)")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(list) { m in
                Button {
                    pickedId = m.id
                    onPick(DateParts(year: m.pickParts.year, month: m.pickParts.month, day: m.pickParts.day,
                                     hour: m.pickParts.hour, minute: m.pickParts.minute))
                } label: {
                    HStack {
                        Text("\(m.start) – \(m.end.suffix(5))").monospacedDigit()
                        Spacer()
                        Text(m.lunar).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(pickedId == m.id ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.10)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 480)
    }

    private func findTimes() {
        guard let y = pillar(yearGan, yearZhi), let m = monthPillar, let d = pillar(dayGan, dayZhi),
              let h = hourPillar else { return }
        let (res, err): (ReverseResult?, String?) = client.callWithError("bazi_reverse", [
            "year": y, "month": m, "day": d, "hour": h])
        if let res { matches = res.results; errorMessage = nil; pickedId = nil } else { matches = nil; errorMessage = err }
    }


}
