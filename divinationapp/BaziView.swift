import SwiftUI

/// 八字排盘输入页。填姓名/性别/出生时间（公历）→「开始排盘」进入新页面出全盘。
/// v1 只支持公历输入（后端 bazi_chart 目前只收公历）；农历/四柱输入留作后续。
struct BaziView: View {
    @State private var name = ""
    @State private var isMale = true

    // 出生时间（公历）
    @State private var year: Int
    @State private var month: Int
    @State private var day: Int
    @State private var hour: Int
    @State private var minute: Int

    @State private var chart: BaziChart?
    @State private var showChart = false
    @State private var errorMessage: String?

    private let client = DivinationClient()

    init() {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        _year   = State(initialValue: c.year   ?? 1990)
        _month  = State(initialValue: c.month  ?? 1)
        _day    = State(initialValue: c.day    ?? 1)
        _hour   = State(initialValue: c.hour   ?? 0)
        _minute = State(initialValue: c.minute ?? 0)
    }

    /// 当前年月的公历日范围。
    private var dayRange: [Int] {
        let cal = Calendar.current
        if let d = cal.date(from: DateComponents(year: year, month: month)),
           let r = cal.range(of: .day, in: .month, for: d) { return Array(r) }
        return Array(1...31)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text("八字排盘").font(.largeTitle).bold()

                    // 姓名 + 性别 同一行
                    HStack(spacing: 16) {
                        Text("姓名").font(.title3)
                        TextField("请输入姓名", text: $name)
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
                        .frame(width: 130)
                    }

                    // 出生时间（公历）滚轮，字号调大便于老年用户
                    HStack(spacing: 12) {
                        WheelPicker(title: "年", values: Array(1900...2100), selection: $year, visibleRows: 3, valueFont: .title2).frame(width: 104)
                        WheelPicker(title: "月", values: Array(1...12),
                                    format: { "\($0)月" }, selection: $month, visibleRows: 3, valueFont: .title2).frame(width: 80)
                        WheelPicker(title: "日", values: dayRange,
                                    format: { "\($0)日" }, selection: $day, visibleRows: 3, valueFont: .title2).frame(width: 80)
                        WheelPicker(title: "时", values: Array(0...23), selection: $hour, visibleRows: 3, valueFont: .title2).frame(width: 80)
                        WheelPicker(title: "分", values: Array(0...59), selection: $minute, visibleRows: 3, valueFont: .title2).frame(width: 80)
                    }

                    Button { paipan() } label: {
                        Text("开始排盘").font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .onChange(of: month) { _, _ in clampDay() }
                .onChange(of: year) { _, _ in clampDay() }
            }
            .navigationDestination(isPresented: $showChart) {
                if let chart {
                    BaziChartView(chart: chart, name: name,
                                  birth: Birth(year: year, month: month, day: day, hour: hour, minute: minute))
                }
            }
        }
    }

    private func clampDay() {
        if day > dayRange.count { day = dayRange.count }
    }

    private func paipan() {
        guard let c = client.baziChart(year: year, month: month, day: day,
                                       hour: hour, minute: minute, isMale: isMale) else {
            errorMessage = "排盘失败：引擎无响应"; return
        }
        errorMessage = nil
        chart = c
        showChart = true
    }
}

/// 出生公历时刻（排流月时要带着命主生辰再问后端）。
struct Birth: Hashable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
}
