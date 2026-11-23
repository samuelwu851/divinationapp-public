import SwiftUI

/// 梅花易数（时间起卦）页。不用 store：本地 @State 即可——每次从菜单进来都是全新实例，自动回到选时间页。
/// 选时间：公历或农历；日期(年/月/日)、时间(时/分) 用跨平台滚轮 WheelPicker 滚动选择（年份也可输入）。
/// 农历先请后端换成公历，再走原来的命令。
/// 排盘：meihua 定本卦/动爻/变卦，bazi_pillars（bazi 包）给左上角八字/公历/农历，lookup 取两卦完整数据，yilin 取崔氏易林，cangua 取参卦。
struct TimeDivinationView: View {
    @State private var date = DateInputModel(years: 1950...2060, initial: .now())

    @State private var result: PaipanResult?
    @State private var errorMessage: String?
    @State private var showDatePicker = false   // 日期滚轮浮窗
    @State private var showTimePicker = false   // 时间滚轮浮窗

    private let client = DivinationClient()
    @AppStorage("wuxingColorOn") private var wuxingColorOn = false   // 五行颜色（和易经速查共用）

    private var dateString: String {
        date.isLunar ? date.dateLabel
                     : String(format: "%04d-%02d-%02d", date.solar.year, date.solar.month, date.solar.day)
    }
    private var timeString: String { String(format: "%02d:%02d", date.solar.hour, date.solar.minute) }

    var body: some View {
        if let r = result {
            resultPage(r)
        } else {
            inputPage
        }
    }

    // MARK: - 选时间页（两行：日期 / 时间，滚轮选择）

    private var inputPage: some View {
        VStack(spacing: 24) {
            Text("梅花易数").font(.largeTitle).bold()

            CalendarModeSwitch(model: date)                 // 公历 / 农历

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
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // 居中填满，内容一屏可见
    }

    private func resetToNow() {
        let lunar = date.isLunar
        date.setSolar(.now())
        if lunar { date.setLunar(true) }               // 保持当前的公历 / 农历方式
        errorMessage = nil
    }

    // MARK: - 排盘

    private func paipan() {
        guard let s = date.resolvedSolar() else {
            errorMessage = "农历日期换算失败"; return
        }
        let (year, month, day, hour, minute) = (s.year, s.month, s.day, s.hour, s.minute)
        guard let m = client.meihua(year: year, month: month, day: day, hour: hour, minute: minute) else {
            errorMessage = "排盘失败：引擎无响应（检查 lunar_python 是否已打包）"; return
        }
        guard let ben = client.lookup(m.benGua.value),
              let bian = client.lookup(m.bianGua.value) else {
            errorMessage = "排盘失败：取卦数据出错"; return
        }
        result = PaipanResult(
            bazi: client.baziPillars(year: year, month: month, day: day, hour: hour, minute: minute),
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
                // 左上角返回：回到选时间页（保留已选时间）；右上角五行颜色（和易经速查共用同一个设置）
                HStack {
                    Button { result = nil } label: {
                        Image(systemName: "chevron.backward").font(.title2)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Toggle("五行颜色", isOn: $wuxingColorOn).fixedSize()
                }

                timeInfoPanel(r.bazi)

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
                BaziPillarsView(pillars: b.ganzhis)
            } else {
                Text("八字信息获取失败").foregroundStyle(.red)
            }
        }
    }
}

/// 一次排盘的结果（梅花易数页本地持有，不入 store）。
struct PaipanResult {
    let bazi: BaziPillarsResult?
    let original: Hexagram
    let changed: Hexagram
    let changingLines: Set<Int>
    let yilin: String?
    let cangua: [CanGuaGroup]
}
