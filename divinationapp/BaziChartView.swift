import SwiftUI

/// 八字全盘结果页。分上下两部分：
/// - 上方（彩色排盘）：四柱 + 当前选中的大运/流年/流月，同一种「柱」格式——
///   十神(黑) + 五行色干支 + 藏干(五行色字+黑十神) + 纳音；不显示年份/岁数。
/// - 下方（无色列表）：大运/流年/流月三条可点横排，干支不上色，上方标年份/岁数
///   （流年只标年份、无岁数）。大运默认选中「今年所在的那一步」，非本时代则选第一步。
struct BaziChartView: View {
    let chart: BaziChart
    let name: String
    let birth: Birth
    /// 放在「公历 / 农历」下面那条分割线之下的内容（笔记里点开时：所问之事 + 特点）；八字页面不用
    var annotation: AnyView? = nil
    /// 乾造 / 坤造右边的姓名输入框（笔记里点开时可以改姓名）；八字页面不用，直接显示姓名
    var nameEditor: AnyView? = nil

    private let client = DivinationClient()

    @State private var dayunIndex: Int
    @State private var selectedYear: Int?       // 选中的流年
    @State private var liuyue: [BaziLiuYue] = []
    @State private var selectedMonth: Int?      // 选中的流月

    // 藏干区固定高度（最多 3 行），好让四柱纳音落在同一行对齐。
    private let cangganAreaHeight: CGFloat = 64

    init(chart: BaziChart, name: String, birth: Birth, annotation: AnyView? = nil, nameEditor: AnyView? = nil) {
        self.chart = chart
        self.name = name
        self.birth = birth
        self.annotation = annotation
        self.nameEditor = nameEditor
        let cur = Calendar.current.component(.year, from: Date())
        _dayunIndex = State(initialValue: Self.defaultDaYunIndex(chart.dayun, currentYear: cur))
    }

    /// 今年落在哪一步大运 [startYear, startYear+10)；都不在（非本时代）→ 第一步。
    static func defaultDaYunIndex(_ dayun: [BaziDaYun], currentYear: Int) -> Int {
        dayun.firstIndex { currentYear >= $0.startYear && currentYear < $0.startYear + 10 } ?? 0
    }

    private var selectedDaYun: BaziDaYun? {
        chart.dayun.indices.contains(dayunIndex) ? chart.dayun[dayunIndex] : nil
    }
    private var selectedLiuNian: BaziLiuNian? {
        guard let y = selectedYear else { return nil }
        return selectedDaYun?.liunian.first { $0.year == y }
    }
    private var selectedLiuYue: BaziLiuYue? {
        guard let m = selectedMonth else { return nil }
        return liuyue.first { $0.month == m }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                if let annotation {
                    annotation                  // 所问之事 + 特点（左对齐）
                    Divider()
                }
                topChart        // 上方：彩色排盘（四柱 + 选中大运/流年/流月）
                Divider()
                qiyunLine       // 起运/交运：夹在八字与大运列表之间
                bottomLists     // 下方：无色可选横排
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(name.isEmpty ? "八字排盘" : name)
    }

    // MARK: - 顶部基本信息

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let nameEditor {
                    Text(chart.gender).font(.title)
                    nameEditor                                   // 姓名：在乾造 / 坤造右边，可以改
                } else {
                    if !name.isEmpty { Text(name).font(.largeTitle).bold() }
                    Text(chart.gender).font(.title)
                }
            }
            Text("公历：\(chart.inputTime)").font(.title2).foregroundStyle(.primary)
            Text("农历：\(chart.lunarTime)").font(.title2).foregroundStyle(.primary)
        }
    }

    /// 起运 / 交运：放在八字与大运列表之间，黑色、与「乾造」同大小。
    private var qiyunLine: some View {
        Text("起运：\(chart.qiyun.years)岁\(chart.qiyun.months)月\(chart.qiyun.days)日　\(chart.jiaoyun.text)")
            .font(.title2).foregroundStyle(.primary)
    }

    // MARK: - 上方：彩色排盘（四柱 + 选中的大运/流年/流月）

    private var topChart: some View {
        HStack(alignment: .top, spacing: 4) {
            coloredPillar("年柱", chart.pillars.year.ganShishen, chart.pillars.year.ganzhi,
                          chart.pillars.year.canggan, chart.pillars.year.nayin)
            coloredPillar("月柱", chart.pillars.month.ganShishen, chart.pillars.month.ganzhi,
                          chart.pillars.month.canggan, chart.pillars.month.nayin)
            coloredPillar("日柱", chart.pillars.day.ganShishen, chart.pillars.day.ganzhi,
                          chart.pillars.day.canggan, chart.pillars.day.nayin)
            coloredPillar("时柱", chart.pillars.hour.ganShishen, chart.pillars.hour.ganzhi,
                          chart.pillars.hour.canggan, chart.pillars.hour.nayin)
            if let dy = selectedDaYun {
                coloredPillar("大运", dy.ganShishen, dy.ganzhi, dy.canggan, dy.nayin)
            }
            if let ln = selectedLiuNian {
                coloredPillar("流年", ln.ganShishen, ln.ganzhi, ln.canggan, ln.nayin)
            }
            if let ly = selectedLiuYue {
                coloredPillar("流月", ly.ganShishen, ly.ganzhi, ly.canggan, ly.nayin)
            }
        }
        .frame(maxWidth: .infinity)   // 整组柱水平居中，减少右侧留白
    }

    /// 一根彩色柱：表头(不加粗) + 主星十神(黑、略大) + 天干/地支(五行色大字) +
    /// 藏干(五行色字 + 黑十神) + 纳音(与列表同大小、四柱同一行对齐)。
    @ViewBuilder
    private func coloredPillar(_ label: String, _ shishen: String, _ ganzhi: String,
                               _ canggan: [CangGan], _ nayin: String?) -> some View {
        let chars = Array(ganzhi)
        VStack(spacing: 6) {
            Text(label).font(.subheadline).foregroundStyle(.primary)        // 7 个表头之一，不加粗、黑色
            Text(shishen).font(.body).foregroundStyle(.primary)             // 主星十神：大一号、黑色
            if chars.count >= 1 { GanZhiChar(c: chars[0]).font(.largeTitle) }  // 天干：五行色
            if chars.count >= 2 { GanZhiChar(c: chars[1]).font(.largeTitle) }  // 地支：五行色
            VStack(spacing: 2) {                                            // 藏干：五行色字 + 黑十神
                ForEach(canggan) { cg in
                    HStack(spacing: 3) {
                        GanZhiChar(c: cg.gan.first ?? " ").font(.body)
                        Text(cg.shishen).font(.subheadline).foregroundStyle(.primary)  // 十神大一号
                    }
                }
            }
            .frame(height: cangganAreaHeight, alignment: .top)              // 固定高 → 纳音同行对齐
            Text(nayin ?? " ").font(.body).foregroundStyle(.primary)        // 纳音：与藏干天干同大小、黑色
        }
        .frame(width: 67)   // 框贴着内容，柱间才真正变窄（间距来自框宽，不是 HStack spacing）
    }

    // MARK: - 下方：无色可选列表（大运 / 流年 / 流月）

    private var bottomLists: some View {
        VStack(alignment: .leading, spacing: 12) {
            listRow(title: "大运") {
                ForEach(Array(chart.dayun.enumerated()), id: \.element.id) { i, dy in
                    listCell(top: "\(dy.startYear)\n\(dy.startAge)岁", ganzhi: dy.ganzhi,
                             selected: i == dayunIndex) {
                        dayunIndex = i
                        selectedYear = nil; liuyue = []; selectedMonth = nil
                    }
                }
            }
            if let dy = selectedDaYun {
                listRow(title: "流年") {
                    ForEach(dy.liunian) { ln in
                        listCell(top: "\(ln.year)", ganzhi: ln.ganzhi,
                                 selected: ln.year == selectedYear) {
                            selectedYear = ln.year
                            selectedMonth = nil
                            loadLiuyue(ln.year)
                        }
                    }
                }
            }
            if !liuyue.isEmpty {
                listRow(title: "流月") {
                    ForEach(liuyue) { ly in
                        listCell(top: monthName(ly.month), ganzhi: ly.ganzhi,
                                 selected: ly.month == selectedMonth) {
                            selectedMonth = ly.month
                        }
                    }
                }
            }
        }
    }

    /// 一条横排：左侧标题 + 横向滚动的格子。
    @ViewBuilder
    private func listRow<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 0) {                                        // 标题竖排：与八字干支同大小、加粗、浅灰
                ForEach(Array(title.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch)).font(.largeTitle).bold().foregroundStyle(.secondary)
                }
            }
            .frame(width: 40)
            .padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1.5) { content() }                     // 格子间距再减半
                    .padding(.vertical, 2)
            }
        }
    }

    /// 无色可选格子：上方年份/岁(或月) + 干支(黑色、不上色、竖排)，选中高亮描边。
    @ViewBuilder
    private func listCell(top: String, ganzhi: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        let chars = Array(ganzhi)
        VStack(spacing: 2) {
            Text(top).font(.subheadline).foregroundStyle(.primary)     // 黑色
                .multilineTextAlignment(.center)
            VStack(spacing: 0) {                                        // 干支竖排、黑色、不上色
                ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch)).font(.title2).foregroundStyle(.primary)
                }
            }
        }
        .frame(minWidth: 40)
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.accentColor.opacity(0.18) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.2))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }

    // MARK: - 工具

    private func monthName(_ m: Int) -> String {
        let names: [String] = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        return (1...12).contains(m) ? names[m - 1] + "月" : "\(m)月"
    }

    private func loadLiuyue(_ y: Int) {
        liuyue = client.baziLiuyue(year: birth.year, month: birth.month, day: birth.day,
                                   hour: birth.hour, minute: birth.minute, targetYear: y)?.months ?? []
    }
}
