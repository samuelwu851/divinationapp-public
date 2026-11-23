import SwiftUI

/// 梅花易数的三种起卦法（页面和笔记「插入排盘」共用）。后端见 meihua/service.qigua_request。
/// - 时间起卦：选日期时间（公历 / 农历），用 DateInputModel
/// - 数字起卦：三个正整数；前两个除以 8 取余定上卦、下卦，第三个除以 6 取余定动爻（余 0 = 上爻）
/// - 指定起卦：直接选上卦、下卦和一个动爻
enum MeihuaMethod: String, CaseIterable, Identifiable {
    case time = "时间起卦"
    case number = "数字起卦"
    case specified = "指定起卦"
    var id: String { rawValue }
}

/// 选时间的三种方式：公历、农历（滚轮），或者按四柱反推（PillarsReverseInput）。
enum TimeSource: String, CaseIterable, Identifiable {
    case solar = "公历"
    case lunar = "农历"
    case pillars = "四柱反推"
    var id: String { rawValue }
}

/// 公历 / 农历 / 四柱反推 三段切换。公历、农历直接切 DateInputModel；四柱反推另外显示反推界面。
struct TimeSourceSwitch: View {
    @Binding var source: TimeSource
    let date: DateInputModel

    var body: some View {
        Picker("", selection: Binding(get: { source }, set: { s in
            source = s
            if s != .pillars { date.setLunar(s == .lunar) }
        })) {
            ForEach(TimeSource.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
    }
}

/// 八卦（先天数 1–8 的顺序：乾1 兑2 离3 震4 巽5 坎6 艮7 坤8）。
let meihuaTrigrams = ["乾", "兑", "离", "震", "巽", "坎", "艮", "坤"]
let meihuaLines = ["初爻", "二爻", "三爻", "四爻", "五爻", "上爻"]

/// 数字起卦 / 指定起卦要填的东西。
struct MeihuaInput: Equatable {
    var method: MeihuaMethod = .time
    var numbers: [String] = ["", "", ""]
    var upper = 1       // 先天数 1–8
    var lower = 1
    var moving = 1      // 1–6

    /// 交给后端的参数。time = 选的时刻（公历 / 农历 / 四柱反推选出来的）：
    /// 时间起卦用它起卦；数字起卦、指定起卦只用它排四柱显示（卦和时间无关）。没选好返回 (nil, 说明)。
    func params(time: DateParts?) -> ([String: Any]?, String?) {
        guard let t = time else { return (nil, "请先选好时间（四柱反推要点选一个时刻）") }
        switch method {
        case .time:
            return (t.params, nil)
        case .number:
            let ns = numbers.map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard ns.allSatisfy({ ($0 ?? 0) > 0 }) else { return (nil, "数字起卦要填三个正整数") }
            return (t.params.merging(["method": "number", "numbers": ns.compactMap { $0 }]) { $1 }, nil)
        case .specified:
            return (t.params.merging(["method": "specified", "upper": upper, "lower": lower, "moving": moving]) { $1 }, nil)
        }
    }
}

/// 结果页 / 排盘窗口里说明是怎么起的卦（时间起卦看四柱，不用这句）。
func meihuaMethodText(method: String?, numbers: [Int]?, upper: Int?, lower: Int?, moving: Int?) -> String? {
    switch method {
    case "number":
        return "数字起卦：" + (numbers ?? []).map(String.init).joined(separator: " · ")
    case "specified":
        func t(_ n: Int?) -> String { n.flatMap { (1...8).contains($0) ? meihuaTrigrams[$0 - 1] : nil } ?? "?" }
        let line = moving.flatMap { (1...6).contains($0) ? meihuaLines[$0 - 1] : nil } ?? "?"
        return "指定起卦：上\(t(upper)) 下\(t(lower))，\(line)动"
    default:
        return nil
    }
}

/// 数字起卦 / 指定起卦的输入（时间起卦用日期滚轮，不在这里）。
struct MeihuaManualInput: View {
    @Binding var input: MeihuaInput

    var body: some View {
        switch input.method {
        case .time:
            EmptyView()
        case .number:
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        TextField(["第一个数", "第二个数", "第三个数"][i], text: $input.numbers[i])
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.title3)
                            .padding(.vertical, 6)
                            .frame(width: 110)
                            .background(RoundedRectangle(cornerRadius: 8).fill(YearWheel.fieldFill))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(YearWheel.fieldStroke, lineWidth: 1))
                    }
                }
            }
        case .specified:
            HStack(spacing: 18) {
                picker("上卦", $input.upper, meihuaTrigrams)
                picker("下卦", $input.lower, meihuaTrigrams)
                picker("动爻", $input.moving, meihuaLines)
            }
        }
    }

    private func picker(_ title: String, _ sel: Binding<Int>, _ names: [String]) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: sel) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in Text(n).tag(i + 1) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
