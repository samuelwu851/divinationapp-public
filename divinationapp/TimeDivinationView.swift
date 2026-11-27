import SwiftUI

/// 梅花易数页：时间起卦 / 数字起卦 / 指定起卦（见 MeihuaMethod.swift）。内容存在 PageStates 里：切走再回来，排好的盘还在。
/// 选时间：公历或农历；日期(年/月/日)、时间(时/分) 用跨平台滚轮 WheelPicker 滚动选择（年份也可输入）。
/// 农历先请后端换成公历，再走原来的命令。
/// 排盘：meihua 定本卦/动爻/变卦，bazi_pillars（bazi 包）给左上角八字/公历/农历，lookup 取两卦完整数据，yilin 取崔氏易林，cangua 取参卦。
struct TimeDivinationView: View {
    /// 内容存在页面外面（PageStates），切到别的术数再回来还在。
    @Bindable var s: MeihuaPageState
    private var date: DateInputModel { get { s.date } nonmutating set { s.date = newValue } }
    private var input: MeihuaInput { get { s.input } nonmutating set { s.input = newValue } }
    private var timeSource: TimeSource { get { s.timeSource } nonmutating set { s.timeSource = newValue } }
    private var pickedTime: DateParts? { get { s.pickedTime } nonmutating set { s.pickedTime = newValue } }
    private var result: PaipanResult? { get { s.result } nonmutating set { s.result = newValue } }
    private var errorMessage: String? { get { s.errorMessage } nonmutating set { s.errorMessage = newValue } }
    @State private var showDatePicker = false   // 日期滚轮浮窗
    @State private var showTimePicker = false   // 时间滚轮浮窗

    private let client = DivinationClient()
    @Environment(CurrentChart.self) private var current      // 「存进案例库」要存的盘（排出来才有）
    @AppStorage("wuxingColorOn") private var wuxingColorOn = false   // 五行颜色（和易经速查共用）

    private var dateString: String {
        date.isLunar ? date.dateLabel
                     : String(format: "%04d-%02d-%02d", date.solar.year, date.solar.month, date.solar.day)
    }
    private var timeString: String { String(format: "%02d:%02d", date.solar.hour, date.solar.minute) }

    var body: some View {
        Group {
            if let r = result {
                resultPage(r)
            } else {
                inputPage
            }
        }
        .onChange(of: result == nil) { _, _ in
            current.spec = result.flatMap { ChartSaveSpec(type: "meihua", params: $0.params) }
        }
        .onAppear { current.spec = result.flatMap { ChartSaveSpec(type: "meihua", params: $0.params) } }
    }

    // MARK: - 选时间页（两行：日期 / 时间，滚轮选择）

    private var inputPage: some View {
        ScrollView {
        VStack(spacing: 24) {
            Text("梅花易数").font(.largeTitle).bold()

            Picker("", selection: $s.input.method) {
                ForEach(MeihuaMethod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            if input.method != .time {
                MeihuaManualInput(input: $s.input)
            }
            // 时间：时间起卦用来起卦；数字 / 指定起卦只用来排八字
            Text(input.method == .time ? "起卦时间" : "时间（只用来排八字）")
                .font(.callout).foregroundStyle(.secondary)
            timeInput

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }

            HStack(spacing: 24) {
                Button("重置") { resetToNow() }
                Button("排盘") { paipan() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 40)
        .padding(.top, 90)
        .padding(.bottom, 40)
        // 靠上排：切换起卦法时标题和三个选项不动（原来上下居中，下面内容一变高矮，标题就跟着跳）
        .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// 时间：公历 / 农历（日期、时间两行，点开滚轮），或按四柱反推选一个时刻。
    @ViewBuilder
    private var timeInput: some View {
        TimeSourceSwitch(source: $s.timeSource, date: date)
        if timeSource == .pillars {
            PillarsReverseInput(client: client, pickTitle: "点一个作为时间：") { t in
                pickedTime = t
                date.setSolar(t)                             // 切回公历时也是这个时刻
            }
            if let t = pickedTime {
                Text(String(format: "已选：%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute))
                    .font(.callout)
            }
        } else {
            solarLunarRows
        }
    }

    private var solarLunarRows: some View {
        VStack(spacing: 24) {

            // 两行：日期 / 时间，显示当前值；点击弹出对应的滚轮浮窗。
            VStack(spacing: 0) {
                // 日期行
                HStack {
                    Text("日期").font(.title3)
                    Spacer()
                    Text(dateString).font(.title3).foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .onTapGesture { showDatePicker = true }
                .popover(isPresented: $showDatePicker) {
                    DateInputWheels(model: date, showTime: false, valueFont: .title3,
                                    yearWidth: 96, columnWidth: 72)
                    .padding()
                    .presentationCompactAdaptation(.popover)   // iPhone 上也用浮窗而非整屏
                }

                Divider()

                // 时间行
                HStack {
                    Text("时间").font(.title3)
                    Spacer()
                    Text(timeString).font(.title3).foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .onTapGesture { showTimePicker = true }
                .popover(isPresented: $showTimePicker) {
                    DateInputWheels(model: date, showDate: false, valueFont: .title3, columnWidth: 72)
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.horizontal, 20)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 420)

            Text("地点：北京（默认）").foregroundStyle(.secondary)
        }
    }

    private func resetToNow() {
        let lunar = date.isLunar
        date.setSolar(.now())
        if lunar { date.setLunar(true) }               // 保持当前的公历 / 农历方式
        input = MeihuaInput(method: input.method)       // 起卦法不变，数字 / 卦清空
        pickedTime = nil
        errorMessage = nil
    }

    // MARK: - 排盘

    private func paipan() {
        let time = timeSource == .pillars ? pickedTime : date.resolvedSolar()
        let (p, why) = input.params(time: time)
        guard let params = p else { errorMessage = why; return }
        let (res, err) = client.meihua(params)
        guard let m = res else { errorMessage = "排盘失败：" + (err ?? "引擎无响应"); return }
        guard let ben = client.lookup(m.benGua.value),
              let bian = client.lookup(m.bianGua.value) else {
            errorMessage = "排盘失败：取卦数据出错"; return
        }
        guard let at = time else { return }
        result = PaipanResult(
            params: params,
            bazi: client.baziPillars(year: at.year, month: at.month, day: at.day, hour: at.hour, minute: at.minute),
            original: ben,
            changed: bian,
            changingLines: [m.movingLine - 1],
            yilin: client.yilin(org: m.benGua.value, chg: m.bianGua.value),
            cangua: client.cangua(org: m.benGua.value, chg: m.bianGua.value)
        )
    }

    // MARK: - 结果页（左上角返回 + 时间信息 + 中心卦）

    private func resultPage(_ r: PaipanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 左上角：返回（回到选时间页，保留已选的）+ 五行颜色；右上角留给切换术数的 ⋯
                HStack(spacing: 16) {
                    Button { result = nil } label: {
                        Image(systemName: "chevron.backward").font(.title2)
                    }
                    .buttonStyle(.plain)
                    Toggle("五行颜色", isOn: $wuxingColorOn).fixedSize()
                    Spacer()
                }

                timeInfoPanel(r.bazi)              // 公历、农历、四柱（数字 / 指定起卦是起卦这一刻的）

                DualGuaView(original: r.original, changed: r.changed,
                            changingLines: r.changingLines, yilin: r.yilin, cangua: r.cangua,
                            readOnly: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(40)
            .environment(\.wuxingColorOn, wuxingColorOn)
        }
    }

    /// 左上角：公历 + 农历 + 八字（四柱，按五行上色，字号同卦名）。
    private func timeInfoPanel(_ b: BaziPillarsResult?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let b {
                Text(b.inputTime).font(.body)
                Text(b.lunarTime).font(.body)
                BaziPillarsDetailView(pillars: b.pillars)           // 四柱 + 藏干 + 纳音
            } else {
                Text("八字信息获取失败").foregroundStyle(.red)
            }
        }
    }
}

/// 一次排盘的结果（梅花易数页本地持有，不入 store）。
struct PaipanResult {
    let params: [String: Any]          // 交给后端的起卦参数（存进笔记时原样用）
    let bazi: BaziPillarsResult?
    let original: Hexagram
    let changed: Hexagram
    let changingLines: Set<Int>
    let yilin: String?
    let cangua: [CanGuaGroup]
}
