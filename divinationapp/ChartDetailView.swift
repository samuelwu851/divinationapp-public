import SwiftUI

/// 点开笔记里的排盘卡片：显示完整排盘（复用八字全盘页、易经的本卦/变卦视图）。
/// 数据来自存下来的快照（snapshot），不重新排盘——笔记记录的是「当时排出来的盘」。
/// macOS 上放在独立窗口里（见 divinationappApp 的 "chart" 窗口），可以边看边编辑笔记；
/// 其他平台用 sheet 弹出（inWindow = false，带「关闭」按钮）。
struct ChartDetailView: View {
    let client: DivinationClient
    let chartId: Int
    var inWindow = false

    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?
    /// 笔记里排盘的五行颜色：这个窗口里勾选，记住上次的选择；笔记正文里的卡片同步（NoteEditorView 读同一个键）。
    /// 和易经速查 / 梅花易数页面的「五行颜色」分开记，互不影响。
    static let wuxingColorKey = "noteChartWuxingColorOn"
    @AppStorage(ChartDetailView.wuxingColorKey) private var wuxingColorOn = false

    enum Loaded {
        case bazi(BaziChart, name: String, birth: Birth)
        case iching(title: String, original: Hexagram, changed: Hexagram, yilin: String?, cangua: [CanGuaGroup]?)
        case meihua(bazi: BaziResult, original: Hexagram, changed: Hexagram, yilin: String?, cangua: [CanGuaGroup]?)
        case unsupported
        case missing
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if !inWindow {                       // 独立窗口自带关闭按钮
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
                }
        }
        .environment(\.wuxingColorOn, wuxingColorOn)
        .frame(minWidth: 650, idealWidth: 760, minHeight: 600, idealHeight: 780)   // 比原来宽约 1/5，八字七柱、本卦|变卦都放得下
        .background(PatternBackground())
        .onAppear { if loaded == nil { loaded = Self.load(client.chartGet(id: chartId)) } }
    }

    /// 五行颜色勾选框：放在内容右上角（同易经速查），不放工具栏——工具栏里会套一层胶囊背景。
    /// 只有易经、梅花有；八字本来就按五行上色。
    private var wuxingToggle: some View {
        HStack {
            Spacer()
            Toggle("五行颜色", isOn: $wuxingColorOn).fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loaded {
        case .bazi(let chart, let name, let birth):
            BaziChartView(chart: chart, name: name, birth: birth)
        case .iching(let title, let org, let chg, let yilin, let cangua):
            ScrollView {
                VStack(spacing: 18) {
                    wuxingToggle
                    Text(title.isEmpty ? "易经速查" : title).font(.title2).bold()
                    guaView(org, chg, yilin, cangua)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("易经速查")
        case .meihua(let bazi, let org, let chg, let yilin, let cangua):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    wuxingToggle
                    VStack(alignment: .leading, spacing: 8) {        // 同梅花易数结果页左上角
                        Text(bazi.inputTime).font(.body)
                        Text(bazi.lunar).font(.body)
                        BaziPillarsView(pillars: [bazi.year, bazi.month, bazi.day, bazi.hour])
                    }
                    guaView(org, chg, yilin, cangua).frame(maxWidth: .infinity)
                }
                .padding(32)
            }
            .navigationTitle("梅花易数")
        case .unsupported:
            message("这个版本还不支持显示这种排盘")
        case .missing:
            message("这个排盘已被删除")
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 有动爻：本卦|变卦并排（只读）；没有：单卦完整面板。
    @ViewBuilder
    private func guaView(_ org: Hexagram, _ chg: Hexagram, _ yilin: String?, _ cangua: [CanGuaGroup]?) -> some View {
        let moving = Set((0..<min(org.lines.count, chg.lines.count)).filter { org.lines[$0] != chg.lines[$0] })
        if moving.isEmpty {
            HexagramPanelView(hex: org, readOnly: true, onFlip: { _ in })
        } else {
            DualGuaView(original: org, changed: chg, changingLines: moving, yilin: yilin,
                        cangua: cangua ?? client.cangua(org: org.value, chg: chg.value),   // 旧快照没存参卦 → 现场算
                        readOnly: true)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 解码快照

    private struct Head: Decodable { let type: String }
    private struct Stored<P: Decodable, S: Decodable>: Decodable {
        let title: String
        let params: P
        let snapshot: S
    }
    private struct BaziParams: Decodable { let year, month, day, hour, minute: Int }
    private struct BaziSnapshot: Decodable { let name: String; let chart: BaziChart }
    private struct Empty: Decodable {}
    private struct GuaSnapshot: Decodable {
        let original: Hexagram
        let changed: Hexagram
        let yilin: String?
        let cangua: [CanGuaGroup]?      // 加参卦之前存的盘没有这一项 → 现场算
    }
    private struct MeihuaSnapshot: Decodable {
        let bazi: BaziResult
        let original: Hexagram
        let changed: Hexagram
        let yilin: String?
        let cangua: [CanGuaGroup]?
    }

    private static func load(_ data: Data?) -> Loaded {
        guard let data else { return .missing }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let head = try? dec.decode(Head.self, from: data) else { return .missing }   // 后端返回 {"error": …}
        switch head.type {
        case "bazi":
            guard let s = try? dec.decode(Stored<BaziParams, BaziSnapshot>.self, from: data) else { return .unsupported }
            let p = s.params
            return .bazi(s.snapshot.chart, name: s.snapshot.name,
                         birth: Birth(year: p.year, month: p.month, day: p.day, hour: p.hour, minute: p.minute))
        case "iching":
            guard let s = try? dec.decode(Stored<Empty, GuaSnapshot>.self, from: data) else { return .unsupported }
            return .iching(title: s.title, original: s.snapshot.original, changed: s.snapshot.changed,
                           yilin: s.snapshot.yilin, cangua: s.snapshot.cangua)
        case "meihua":
            guard let s = try? dec.decode(Stored<Empty, MeihuaSnapshot>.self, from: data) else { return .unsupported }
            return .meihua(bazi: s.snapshot.bazi, original: s.snapshot.original, changed: s.snapshot.changed,
                           yilin: s.snapshot.yilin, cangua: s.snapshot.cangua)
        default:
            return .unsupported
        }
    }
}
