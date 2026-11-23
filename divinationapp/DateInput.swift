import SwiftUI

/// 公历 / 农历 两种方式选时间（八字、梅花易数共用）。
///
/// - 公历：年月日按历史公历（1582 年以前儒略历，见 HistoricalCalendar）。
/// - 农历：月份按「某农历年的月份结构」从后端加载（含闰月、每月 29/30 天）。
/// - 切换公历/农历时互相换算，保持是同一个时刻；时、分两边共用。
/// - 排盘一律用公历：调用方拿 `resolvedSolar(_:)`（农历会请后端换算），再走原来的排盘命令。
@Observable
final class DateInputModel {
    let years: ClosedRange<Int>
    var isLunar = false
    var solar: DateParts                 // 公历年月日 + 时分（时分两种方式共用）

    // 农历
    var lunarYear: Int
    var lunarMonths: [LunarMonth] = []
    var lunarMonthIndex = 0              // 下标（闰月会让月号重复，所以绑下标）
    var lunarDay = 1

    @ObservationIgnored private let client = DivinationClient()

    init(years: ClosedRange<Int>, initial: DateParts) {
        self.years = years
        self.solar = initial
        self.lunarYear = initial.year
    }

    var currentLunarMonth: LunarMonth? {
        lunarMonths.indices.contains(lunarMonthIndex) ? lunarMonths[lunarMonthIndex] : nil
    }
    var currentLunarMonthDays: Int { currentLunarMonth?.days ?? 30 }

    /// 切换公历 / 农历：把当前选的时刻换算过去，两边保持同一天。
    func setLunar(_ on: Bool) {
        guard on != isLunar else { return }
        if on {
            loadLunar(fromSolar: solar)
        } else if let s = lunarAsSolar() {
            solar = s
        }
        isLunar = on
    }

    /// 直接设定一个公历时刻（如带入案主生日）：切回公历显示。
    func setSolar(_ parts: DateParts) {
        solar = parts
        isLunar = false
    }

    /// 农历年份变了：重载月份结构，收回越界的月 / 日。
    func refreshLunarMonths() {
        let old = currentLunarMonth
        lunarMonths = client.lunarMonths(year: lunarYear) ?? []
        // 尽量停在同一个月（同月号、同是否闰月），没有就同月号的非闰月，再不行收到最后一个月
        lunarMonthIndex = lunarMonths.firstIndex { $0.month == old?.month && $0.isLeap == old?.isLeap }
            ?? lunarMonths.firstIndex { $0.month == old?.month && !$0.isLeap }
            ?? max(0, min(lunarMonthIndex, lunarMonths.count - 1))
        clampLunarDay()
    }

    func clampLunarDay() {
        if lunarDay > currentLunarMonthDays { lunarDay = currentLunarMonthDays }
    }

    func clampSolarDay() {
        solar.day = HistoricalCalendar.clamp(day: solar.day, year: solar.year, month: solar.month)
    }

    /// 排盘用的公历时刻。农历请后端换算；换算失败（如超出范围）返回 nil。
    func resolvedSolar() -> DateParts? {
        isLunar ? lunarAsSolar() : solar
    }

    /// 显示用：「1990年 正月 初一」或「1990年1月1日」（不含时间）。
    var dateLabel: String {
        if isLunar, let m = currentLunarMonth {
            return "农历 \(lunarYear)年 \(m.label)\(lunarDayLabel(lunarDay))"
        }
        return "\(solar.year)年\(solar.month)月\(solar.day)日"
    }

    // MARK: - 换算

    private func loadLunar(fromSolar s: DateParts) {
        guard let sl = client.solarToLunar(year: s.year, month: s.month, day: s.day, hour: s.hour, minute: s.minute) else {
            lunarYear = s.year
            lunarMonths = client.lunarMonths(year: lunarYear) ?? []
            return
        }
        lunarYear = sl.lunarYear
        lunarMonths = client.lunarMonths(year: sl.lunarYear) ?? []
        lunarMonthIndex = lunarMonths.firstIndex { $0.month == sl.lunarMonth && $0.isLeap == sl.isLeap } ?? 0
        lunarDay = min(sl.lunarDay, currentLunarMonthDays)
    }

    private func lunarAsSolar() -> DateParts? {
        guard let m = currentLunarMonth,
              let s = client.lunarToSolar(year: lunarYear, month: m.month, day: lunarDay, isLeap: m.isLeap,
                                          hour: solar.hour, minute: solar.minute) else { return nil }
        return s
    }
}

/// 农历日名：初一…初十、十一…十九、二十、廿一…廿九、三十。
func lunarDayLabel(_ d: Int) -> String {
    let units = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    switch d {
    case 1...10:  return "初" + units[d]
    case 11...19: return "十" + units[d - 10]
    case 20:      return "二十"
    case 21...29: return "廿" + units[d - 20]
    case 30:      return "三十"
    default:      return "\(d)"
    }
}

/// 公历 / 农历 分段切换。
struct CalendarModeSwitch: View {
    let model: DateInputModel

    var body: some View {
        Picker("", selection: Binding(get: { model.isLunar }, set: { model.setLunar($0) })) {
            Text("公历").tag(false)
            Text("农历").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 160)
    }
}

/// 年月日（公历或农历）滚轮，可选带上时、分。年份可滚可输入（YearWheel）。
struct DateInputWheels: View {
    @Bindable var model: DateInputModel
    var showDate = true
    var showTime = true
    var valueFont: Font = .title2
    var yearWidth: CGFloat = 104
    var columnWidth: CGFloat = 80

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showDate {
                if model.isLunar {
                    YearWheel(years: model.years, selection: $model.lunarYear, valueFont: valueFont).frame(width: yearWidth)
                    WheelPicker(title: "月", values: Array(0..<max(model.lunarMonths.count, 1)),
                                format: { model.lunarMonths.indices.contains($0) ? model.lunarMonths[$0].label : "—" },
                                selection: $model.lunarMonthIndex, visibleRows: 3, valueFont: valueFont)
                        .frame(width: columnWidth + 8)
                    WheelPicker(title: "日", values: Array(1...model.currentLunarMonthDays),
                                format: { lunarDayLabel($0) },
                                selection: $model.lunarDay, visibleRows: 3, valueFont: valueFont)
                        .frame(width: columnWidth + 8)
                } else {
                    YearWheel(years: model.years, selection: $model.solar.year, valueFont: valueFont).frame(width: yearWidth)
                    WheelPicker(title: "月", values: Array(1...12), format: { "\($0)月" },
                                selection: $model.solar.month, visibleRows: 3, valueFont: valueFont).frame(width: columnWidth)
                    WheelPicker(title: "日", values: model.solar.dayRange, format: { "\($0)日" },
                                selection: $model.solar.day, visibleRows: 3, valueFont: valueFont).frame(width: columnWidth)
                }
            }
            if showTime {
                WheelPicker(title: "时", values: Array(0...23), selection: $model.solar.hour,
                            visibleRows: 3, valueFont: valueFont).frame(width: columnWidth)
                WheelPicker(title: "分", values: Array(0...59), selection: $model.solar.minute,
                            visibleRows: 3, valueFont: valueFont).frame(width: columnWidth)
            }
        }
        .onChange(of: model.lunarYear) { _, _ in if model.isLunar { model.refreshLunarMonths() } }
        .onChange(of: model.lunarMonthIndex) { _, _ in model.clampLunarDay() }
        .onChange(of: model.solar.year) { _, _ in model.clampSolarDay() }
        .onChange(of: model.solar.month) { _, _ in model.clampSolarDay() }
    }
}
