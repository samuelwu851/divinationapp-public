import SwiftUI

/// 历史公历（和后端 lunar_python 一致）：1582-10-15 以前用儒略历（每 4 年一闰），之后用格里历；
/// 1582 年 10 月 5 日到 14 日在历史上不存在（改历时跳过）。古人的生日按史书上的日期输入即可。
/// 只用来给日期滚轮列出「这个月有哪几天」，排盘本身在后端。
enum HistoricalCalendar {
    /// 八字支持的年份范围（同后端 bazi.service.YEAR_MIN / YEAR_MAX）。
    static let baziYears = 1...2200

    static func isLeapYear(_ y: Int) -> Bool {
        y < 1583 ? y % 4 == 0 : (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    /// 某年某月有哪几天（1582 年 10 月是 1–4、15–31 日）。
    static func days(year: Int, month: Int) -> [Int] {
        if year == 1582 && month == 10 { return Array(1...4) + Array(15...31) }
        let lengths = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return Array(1...lengths[max(0, min(11, month - 1))])
    }

    /// 换了年月后，原来的日不存在 → 挪到最近的有效日（落在 1582 年 10 月 5–14 日 → 15 日；超过月末 → 月末）。
    static func clamp(day: Int, year: Int, month: Int) -> Int {
        let ds = days(year: year, month: month)
        if ds.contains(day) { return day }
        return ds.first(where: { $0 > day }) ?? ds.last ?? 1
    }
}

/// 年份：滚轮 + 下面的输入框。年份跨度大（如公元 1–2200 年）时直接输入更快：
/// 输入后回车或点别处就跳过去，超出范围自动收到边界；滚动滚轮时输入框跟着变。
struct YearWheel: View {
    let years: ClosedRange<Int>
    @Binding var selection: Int
    var visibleRows: Int = 3
    var valueFont: Font = .title2

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            WheelPicker(title: "年", values: Array(years), selection: $selection,
                        visibleRows: visibleRows, valueFont: valueFont)
            TextField("输入年份", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .help("可以直接输入年份（\(years.lowerBound)–\(years.upperBound)），回车跳过去")
        }
        .onAppear { text = String(selection) }
        .onChange(of: selection) { _, v in if !focused { text = String(v) } }
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let v = Int(digits) {
            selection = min(max(v, years.lowerBound), years.upperBound)
        }
        text = String(selection)
    }
}
