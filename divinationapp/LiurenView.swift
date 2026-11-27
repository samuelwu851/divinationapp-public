import SwiftUI

/// 起课要填的东西（起课页和笔记的「插入排盘」共用）：时间、占时（活时）、月将、贵人昼夜、涉害取法、年命。
@Observable
final class LiurenInput {
    static let methodKey = "liurenShehaiMethod"

    var date = DateInputModel(years: HistoricalCalendar.baziYears, initial: .now())
    var timeSource: TimeSource = .solar
    var pickedTime: DateParts?                // 四柱反推选中的时刻
    var shi = ""                              // "" = 自动（按时间）；否则手动占时（活时）
    var yuejiang = ""                         // "" = 自动（按中气）
    var dayNight = ""                         // "" = 自动（卯至申为昼）
    /// 涉害取法："mzj" 孟仲季（默认）/ "depth" 深浅。存在本机设置里：起课页和课式页的设置改的是同一个值，
    /// 选过一次下次还是它。界面上用 @AppStorage(methodKey) 读写，这里只在交参数时取。
    static let defaultMethod = "mzj"
    var method: String { UserDefaults.standard.string(forKey: Self.methodKey) ?? Self.defaultMethod }
    /// 贵人起法："std" 甲戊庚牛羊（每句先昼后夜，默认）/ "alt" 甲(戊)庚牛羊（庚己丁癸昼夜对调）。和涉害取法一样存在本机设置里。
    static let guirenKey = "liurenGuiren"
    static let defaultGuiren = "std"
    var guiren: String { UserDefaults.standard.string(forKey: Self.guirenKey) ?? Self.defaultGuiren }
    var people: [LiurenPerson] = []

    /// 交给后端 liuren_paipan 的参数；没填好返回 (nil, 说明)。
    func params() -> ([String: Any]?, String?) {
        guard let t = timeSource == .pillars ? pickedTime : date.resolvedSolar() else {
            return (nil, timeSource == .pillars ? "请先点选一个时刻" : "日期换算失败")
        }
        var p: [String: Any] = ["date": t.params, "method": method, "guiren": guiren]
        if !shi.isEmpty { p["shi"] = shi }
        if !yuejiang.isEmpty { p["yuejiang"] = yuejiang }
        if !dayNight.isEmpty { p["day_night"] = dayNight }
        let ms = people.compactMap(\.param)
        if ms.count < people.count { return (nil, "年命的出生年要填公历年份（如 1980）") }
        p["nianming"] = ms
        return (p, nil)
    }

    /// 各项拼成一串：表单内容一变它就变（插入面板据此重新交出参数）。
    var signature: String {
        let s = date.solar
        let picked = pickedTime.map { "\($0.year)-\($0.month)-\($0.day) \($0.hour):\($0.minute)" } ?? ""
        let ps = people.map { "\($0.name),\($0.year),\($0.isMale)" }.joined(separator: ";")
        return [timeSource.rawValue, "\(date.isLunar)", "\(s.year)-\(s.month)-\(s.day) \(s.hour):\(s.minute)",
                "\(date.lunarYear)/\(date.lunarMonthIndex)/\(date.lunarDay)", picked,
                shi, yuejiang, dayNight, method, guiren, ps].joined(separator: "|")
    }

    func resetToNow() {
        let lunar = date.isLunar
        date.setSolar(.now())
        if lunar { date.setLunar(true) }
        pickedTime = nil
        shi = ""; yuejiang = ""; dayNight = ""
    }
}

/// 大六壬起课页：占事 + 起课表单 →「起课」请后端 liuren_paipan，进结果页 LiurenChartView。
/// 结果页右上角的笔可以把这一课存进案例库（占事存成所问之事）。
struct LiurenView: View {
    /// 内容存在页面外面（PageStates），切到别的术数再回来还在。
    @Bindable var s: LiurenPageState
    @AppStorage(LiurenInput.methodKey) private var method = LiurenInput.defaultMethod
    @AppStorage(LiurenInput.guirenKey) private var guiren = LiurenInput.defaultGuiren
    private var question: String { get { s.question } nonmutating set { s.question = newValue } }
    private var input: LiurenInput { get { s.input } nonmutating set { s.input = newValue } }
    private var result: LiurenResult? { get { s.result } nonmutating set { s.result = newValue } }
    private var showResult: Bool { get { s.showResult } nonmutating set { s.showResult = newValue } }
    private var errorMessage: String? { get { s.errorMessage } nonmutating set { s.errorMessage = newValue } }
    private var current: CurrentChart { get { s.current } nonmutating set { s.current = newValue } }
    private var baseParams: [String: Any] { get { s.baseParams } nonmutating set { s.baseParams = newValue } }
    private var hourOffset: Int { get { s.hourOffset } nonmutating set { s.hourOffset = newValue } }

    private let client = DivinationClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("大六壬").font(.largeTitle).bold()

                    LiurenInputForm(input: input, client: client, question: $s.question)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.callout)
                    }

                    HStack(spacing: 24) {
                        Button("重置") { input.resetToNow(); errorMessage = nil }
                        Button { qike() } label: {
                            Text("起课").font(.headline).padding(.horizontal, 28).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)          // 不显示竖滚动条：四柱反推列出结果、页面变长时不会整体左右跳
            // 设置里改了涉害取法：设置优先，正在看的课马上按新取法重排（前后挪过的时辰保留）
            .onChange(of: method) { _, m in
                guard result != nil, !baseParams.isEmpty else { return }
                baseParams["method"] = m
                _ = show(paramsAt(hourOffset))
            }
            .onChange(of: guiren) { _, g in      // 贵人起法同理
                guard result != nil, !baseParams.isEmpty else { return }
                baseParams["guiren"] = g
                _ = show(paramsAt(hourOffset))
            }
            .navigationDestination(isPresented: $s.showResult) {
                if let result {
                    LiurenChartView(r: result, question: question,
                                    timeStep: LiurenTimeStep(offset: hourOffset, step: { step($0) },
                                                             reset: { step(-hourOffset) }))
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) { SaveChartButton(current: current) }
                        }
                }
            }
        }
    }

    private func qike() {
        let (p, why) = input.params()
        guard let params = p else { errorMessage = why; return }
        guard show(params) else { return }
        baseParams = params
        hourOffset = 0
        showResult = true
    }

    /// 前 / 后 n 个时辰（课式页上的 ◀ ▶），reset 就是退回到起课时那一刻。
    /// 时间加减 2n 小时；手动指定了占时（活时）的，占时也跟着挪 n 位。月将、贵人、年命等不变。
    private func step(_ n: Int) {
        guard n != 0 else { return }
        let offset = hourOffset + n
        if show(paramsAt(offset)) { hourOffset = offset }
    }

    /// 起课时的参数往前 / 后挪 offset 个时辰。
    private func paramsAt(_ offset: Int) -> [String: Any] {
        guard offset != 0, let d = baseParams["date"] as? [String: Any],
              let base = DateParts(params: d) else { return baseParams }
        var p = baseParams
        p["date"] = base.shifted(hours: offset * 2).params
        if let shi = baseParams["shi"] as? String, let i = Liuren.zhi.firstIndex(of: shi) {
            p["shi"] = Liuren.zhi[((i + offset) % 12 + 12) % 12]
        }
        return p
    }

    /// 请后端排盘并显示；存进案例库的也换成这一课。失败返回 false（原来的课不动）。
    private func show(_ params: [String: Any]) -> Bool {
        let (r, err) = client.liuren(params)
        guard let r else { errorMessage = "起课失败：" + (err ?? "引擎无响应"); return false }
        errorMessage = nil
        result = r
        current.spec = ChartSaveSpec(type: "daliuren", params: params,
                                     question: question.trimmingCharacters(in: .whitespacesAndNewlines))
        return true
    }
}

/// 起课表单。question 为 nil 时不显示占事框（笔记插入面板自己有「所问之事」），只显示加年命的按钮。
struct LiurenInputForm: View {
    @Bindable var input: LiurenInput
    let client: DivinationClient
    var question: Binding<String>?
    @AppStorage(LiurenInput.methodKey) private var method = LiurenInput.defaultMethod   // 和课式页设置是同一个值
    @AppStorage(LiurenInput.guirenKey) private var guiren = LiurenInput.defaultGuiren

    @State private var showDatePicker = false
    @State private var showTimePicker = false

    var body: some View {
        VStack(spacing: 22) {
            questionBox
            timeInput
            optionsBox
        }
    }

    // MARK: - 占事 + 年命

    private var questionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(question == nil ? "年命" : "占事").font(.headline)
                Spacer()
                Button { input.people.append(LiurenPerson()) } label: {
                    Label("本命", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            if let question {
                TextField("输入要分析的事情", text: question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
            }
            ForEach($input.people) { $p in
                LiurenPersonRow(person: $p) { input.people.removeAll { $0.id == p.id } }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 460)
    }

    // MARK: - 时间

    @ViewBuilder
    private var timeInput: some View {
        TimeSourceSwitch(source: $input.timeSource, date: input.date)
        if input.timeSource == .pillars {
            PillarsReverseInput(client: client, pickTitle: "点一个作为时间：") { t in
                input.pickedTime = t
                input.date.setSolar(t)
            }
            if let t = input.pickedTime {
                Text(String(format: "已选：%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute))
                    .font(.callout)
            }
        } else {
            VStack(spacing: 0) {
                row("日期", dateString) { showDatePicker = true }
                    .popover(isPresented: $showDatePicker) {
                        DateInputWheels(model: input.date, showTime: false, valueFont: .title3,
                                        yearWidth: 96, columnWidth: 72)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                    }
                Divider()
                row("时间", String(format: "%02d:%02d", input.date.solar.hour, input.date.solar.minute)) {
                    showTimePicker = true
                }
                .popover(isPresented: $showTimePicker) {
                    DateInputWheels(model: input.date, showDate: false, valueFont: .title3, columnWidth: 72)
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            }
            .padding(.horizontal, 20)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: 460)
        }
    }

    private var dateString: String {
        let d = input.date
        return d.isLunar ? d.dateLabel : String(format: "%04d-%02d-%02d", d.solar.year, d.solar.month, d.solar.day)
    }

    private func row(_ title: String, _ value: String, tap: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.title3)
            Spacer()
            Text(value).font(.title3).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }

    // MARK: - 占时、月将、贵人、涉害

    private var optionsBox: some View {
        VStack(spacing: 0) {
            pickerRow("占时", $input.shi, auto: "自动（正时）", values: Liuren.zhi.map { ($0, $0 + "时（活时）") })
            Divider()
            pickerRow("月将", $input.yuejiang, auto: "自动（中气）", values: Liuren.zhi.map { ($0, $0 + "将") })
            Divider()
            pickerRow("贵人", $input.dayNight, auto: "自动（卯至申为昼）", values: [("昼", "昼贵"), ("夜", "夜贵")])
            Divider()
            pickerRow("贵人起法", $guiren, auto: nil, values: [("std", "甲戊庚牛羊"), ("alt", "甲(戊)庚牛羊")])
            Divider()
            pickerRow("涉害", $method, auto: nil, values: [("mzj", "孟仲季法"), ("depth", "深浅法")])
        }
        .padding(.horizontal, 20)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 460)
    }

    private func pickerRow(_ title: String, _ sel: Binding<String>, auto: String?,
                           values: [(String, String)]) -> some View {
        HStack {
            Text(title).font(.title3)
            Spacer()
            Picker("", selection: sel) {
                if let auto { Text(auto).tag("") }
                ForEach(values, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

/// 年命里的一个人：称呼、出生年（公历，按立春后的年干支）、性别。
struct LiurenPerson: Identifiable {
    let id = UUID()
    var name = ""
    var year = ""
    var isMale = true

    var ganzhi: String? { Int(year.trimmingCharacters(in: .whitespaces)).map(Liuren.yearGanZhi) }

    var param: [String: Any]? {
        guard let gz = ganzhi else { return nil }
        return ["name": name, "birth": gz, "gender": isMale ? "男" : "女"]
    }
}

struct LiurenPersonRow: View {
    @Binding var person: LiurenPerson
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("称呼", text: $person.name).frame(width: 80)
            TextField("出生年", text: $person.year).frame(width: 70)
            Text(person.ganzhi ?? "—").foregroundStyle(.secondary).frame(width: 36)
            Picker("", selection: $person.isMale) {
                Text("男").tag(true)
                Text("女").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
        }
        .textFieldStyle(.roundedBorder)
        .help("出生年按立春换年：立春前出生的请填上一年")
    }
}

// MARK: - 笔记里的大六壬：插入表单 + 详情（注册进 ChartKindRegistry）

enum LiurenChartKind {
    /// App 启动时调用。
    @MainActor static func register() {
        ChartKindRegistry.register(ChartKind(
            type: "daliuren", title: "大六壬", showsWuxingToggle: false,
            makeInsertForm: { setParams in AnyView(LiurenInsertForm(setParams: setParams)) },
            makeDetail: { data in
                struct Stored: Decodable { let snapshot: LiurenResult }
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                guard let s = try? dec.decode(Stored.self, from: data) else { return nil }
                // 所问之事、特点由详情窗口统一显示在上面，这里不再重复
                return AnyView(LiurenChartView(r: s.snapshot, embedded: true))
            }))
    }
}

/// 插入面板里的表单：和起课页一样（不含占事框），内容一变就把参数交出去。
private struct LiurenInsertForm: View {
    let setParams: ([String: Any]?) -> Void
    @State private var input = LiurenInput()
    @AppStorage(LiurenInput.methodKey) private var method = LiurenInput.defaultMethod
    @AppStorage(LiurenInput.guirenKey) private var guiren = LiurenInput.defaultGuiren
    private let client = DivinationClient()

    var body: some View {
        LiurenInputForm(input: input, client: client, question: nil)
            .onAppear { setParams(input.params().0) }
            .onChange(of: input.signature) { _, _ in setParams(input.params().0) }
            .onChange(of: method) { _, _ in setParams(input.params().0) }
            .onChange(of: guiren) { _, _ in setParams(input.params().0) }
    }
}

// MARK: - 前后时辰

/// 课式页上「前一个时辰 / 重置 / 后一个时辰」三个按钮要的东西。
struct LiurenTimeStep {
    let offset: Int                       // 现在比起课时前（负）/ 后（正）了几个时辰
    let step: (Int) -> Void               // -1 前一个时辰，+1 后一个时辰
    let reset: () -> Void
}

extension DateParts {
    init?(params d: [String: Any]) {
        guard let y = d["year"] as? Int, let m = d["month"] as? Int, let day = d["day"] as? Int else { return nil }
        self.init(year: y, month: m, day: day, hour: d["hour"] as? Int ?? 0, minute: d["minute"] as? Int ?? 0)
    }

    /// 往后（负数往前）挪几个小时。跨日、跨月、跨年按历史公历走（1582 年 10 月少的那十天也跳过）。
    func shifted(hours: Int) -> DateParts {
        var r = self
        let total = hour + hours
        r.hour = ((total % 24) + 24) % 24
        var days = Int((Double(total) / 24).rounded(.down))
        while days > 0 {
            let ds = HistoricalCalendar.days(year: r.year, month: r.month)
            if let next = ds.first(where: { $0 > r.day }) {
                r.day = next
            } else {
                r.month += 1
                if r.month > 12 { r.month = 1; r.year += 1 }
                r.day = HistoricalCalendar.days(year: r.year, month: r.month).first ?? 1
            }
            days -= 1
        }
        while days < 0 {
            let ds = HistoricalCalendar.days(year: r.year, month: r.month)
            if let prev = ds.last(where: { $0 < r.day }) {
                r.day = prev
            } else {
                r.month -= 1
                if r.month < 1 { r.month = 12; r.year -= 1 }
                r.day = HistoricalCalendar.days(year: r.year, month: r.month).last ?? 1
            }
            days += 1
        }
        return r
    }
}
