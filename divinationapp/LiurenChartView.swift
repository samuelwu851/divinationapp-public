import SwiftUI

/// 大六壬课式页。不用格子框，按传统课式排字：
/// - 三传：每行 六亲 遁干 天盘支 天将；
/// - 四课：从右往左一二三四，每列 天将 / 上神 / 下神（四课不显示遁干）；
/// - 天地盘：地盘位置固定、不写出来，只排天盘一圈。上下两边从外到内是 遁干、天将、天盘支，
///   左右两边同理（遁干在最外）。中间只写课体。
/// 干支、天将都按五行上色；六亲、遁干（天地盘）用灰色；空亡的天盘支加框，遁干位置写 ◎。
struct LiurenChartView: View {
    let r: LiurenResult
    var question = ""
    /// 嵌在案例库详情窗口里：外面已经有滚动，这里不再包 ScrollView。
    var embedded = false
    /// 前后时辰的按钮（起课页给；案例库详情里没有）。
    var timeStep: LiurenTimeStep? = nil
    @AppStorage(LiurenSideItems.storageKey) private var sideItems = ""
    @AppStorage(LiurenScript.key) private var traditional = true      // 繁体 / 简体（设置里切，默认繁体）
    @State private var showSettings = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScrollView { content }.navigationTitle("大六壬")
            }
        }
        .sheet(isPresented: $showSettings) {
            LiurenChartSettings(all: r.shenshaList ?? [], showsMethod: !embedded)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            // 三传、四课、天地盘排成一列，以页面中线居中对齐；
            // 左栏叠在左边，高度到天地盘最下面一排为止，多了就滚动；年命叠在右上角
            VStack(spacing: 36) {
                sanChuan
                siKe
                tianDiPan
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) { sidePanel }
            .overlay(alignment: .topTrailing) { mingPanel }
            if let sha = r.shensha { shenSha(sha) }
        }
        .padding(30)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 顶部：占事、四柱、月将

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !question.isEmpty {
                Text(question).font(.title3).bold()
            }
            HStack(alignment: .center, spacing: 24) {
                let pillars = [r.input.year, r.input.month, r.input.day, r.input.hour]
                if pillars.allSatisfy({ $0 != nil }) {
                    BaziPillarsView(pillars: pillars.compactMap { $0 }, charFont: .title)
                } else {
                    HStack(spacing: 4) { colored(r.day).font(.title); Text(tc("日")).font(.title3) }
                }
                if let timeStep { stepButtons(timeStep) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        colored(r.shi); Text(tc("时"))
                        Text("·").foregroundStyle(.secondary)
                        colored(r.yuejiang); Text(tc("将"))
                        if let qi = r.input.qi { Text("（\(tc(qi))）").foregroundStyle(.secondary) }
                    }
                    Text(tc("\(r.dayNight)贵（\(r.guiren == "alt" ? "甲(戊)庚牛羊" : "甲戊庚牛羊")） · \(r.method == "mzj" ? "孟仲季法" : "深浅法")"))
                        .foregroundStyle(.secondary)
                }
                .font(.title3)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
                .buttonStyle(.plain)
                .help("设置")
            }
        }
    }

    /// 四柱旁边，竖着排：▲ 上一个时辰　↻ 回到起课时　▼ 下一个时辰；挪过了在右边写「后 2 个时辰」。
    /// 按设置转成繁体（简体就原样）。
    private func tc(_ s: String) -> String { traditional ? LiurenScript.trad(s) : s }

    private func stepButtons(_ t: LiurenTimeStep) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                Button { t.step(-1) } label: { Image(systemName: "arrowtriangle.up.fill") }
                    .help("上一个时辰")
                Button { t.reset() } label: { Image(systemName: "arrow.clockwise") }
                    .help("回到起课的时辰")
                    .disabled(t.offset == 0)
                    .opacity(t.offset == 0 ? 0.75 : 1)          // 没挪过时稍淡一点，但不至于看不清
                Button { t.step(1) } label: { Image(systemName: "arrowtriangle.down.fill") }
                    .help("下一个时辰")
            }
            .font(.title3)
            .foregroundStyle(Color.primary.opacity(0.55))      // 中灰：浅色、深色模式下都看得清，不抢干支的颜色
            .buttonStyle(.plain)
            Text(t.offset == 0 ? "" : "\(t.offset < 0 ? "前" : (traditional ? "後" : "后"))\(abs(t.offset))\(tc("时"))辰")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
        }
        .fixedSize()
    }

    // MARK: - 右上角：年命（本命、行年）

    private var mingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(r.nianming.enumerated()), id: \.offset) { i, m in
                if i > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    let gender = m.gender ?? ""
                    if !m.name.isEmpty || !gender.isEmpty {
                        HStack(spacing: 8) {
                            if !m.name.isEmpty { Text(m.name).font(.headline) }
                            if !gender.isEmpty { Text(gender).font(.headline).foregroundStyle(.secondary) }
                        }
                    }
                    labeled(tc("本命")) { colored(m.birth) }
                    if let x = m.xingnian, let gz = x.ganzhi {
                        labeled(tc("行年")) { colored(gz) }
                    }
                }
            }
        }
        .font(.title2)
        .fixedSize()
    }

    // MARK: - 左栏：用户选的项（默认 月将、旬空、旬首、旬丁、旬尾），可滚动

    private var sidePanel: some View {
        let keys = sideItems == "none" ? [] : LiurenSideItems.decode(sideItems)
        let all = r.shenshaList ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(keys, id: \.self) { k in sideRow(k, all: all) }
            }
            .font(.title2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 170)
    }

    @ViewBuilder
    private func sideRow(_ key: String, all: [LiurenResult.Sha]) -> some View {
        let title = tc(LiurenSideItems.label(key, all: all))
        switch key {
        case "base:月将": labeled(title) { colored(r.yuejiang) }
        case "base:旬空": labeled(title) { colored(r.kong.joined()) }
        case "base:旬首": labeled(title) { colored(r.xun) }
        case "base:旬丁": labeled(title) { colored(Liuren.xunDing(r.xun)) }
        case "base:旬尾": labeled(title) { colored(Liuren.xunWei(r.xun)) }
        default:
            if let s = all.first(where: { LiurenSideItems.shaKey($0) == key }) {
                labeled(title) { colored(s.branches.joined()) }
            }
        }
    }

    private func labeled<V: View>(_ title: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.title3).foregroundStyle(.secondary)
            v()
        }
    }

    // MARK: - 三传：六亲 遁干 天盘支 天将 空亡标记

    /// 三传后面的标记：◎ 空亡（这一传本身是旬空），⊙ 陷空（这一传所临的地盘支是旬空）。
    private func kongMarks(_ c: LiurenResult.Pos) -> String {
        let di = r.pan.first { $0.zhi == c.zhi }?.di ?? ""
        return (c.kong ? "◎" : "") + (r.kong.contains(di) ? "⊙" : "")
    }

    private var sanChuan: some View {
        Grid(horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(Array(r.sanchuan.chuan.enumerated()), id: \.offset) { _, c in
                GridRow {
                    Text(tc(Liuren.qinShort(c.qin))).foregroundStyle(.secondary)
                    if let g = c.dun { colored(g) } else { Text("　") }
                    zhi(c.zhi, kong: c.kong)
                    jiang(c.jiang)
                    Text(kongMarks(c)).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                        .help("◎ 空亡　⊙ 陷空（所临地盘落空）")
                }
            }
        }
        .font(.title)
        .padding(.leading, 76)          // 比右边标记列宽一点，三传主体稍微靠右，和四课、天地盘看起来对齐
    }

    // MARK: - 四课：从右往左一二三四；天将 / 上神 / 下神（不标空亡）

    private var siKe: some View {
        Grid(horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow { ForEach([3, 2, 1, 0], id: \.self) { jiang(r.sike[$0].jiang) } }
            GridRow { ForEach([3, 2, 1, 0], id: \.self) { zhi(r.sike[$0].zhi, kong: false) } }
            GridRow { ForEach([3, 2, 1, 0], id: \.self) { colored(r.sike[$0].down ?? "") } }
        }
        .font(.title)
    }

    // MARK: - 天地盘

    /// 8×8 排字：第 2–5 列 / 行是四边的天盘，外两圈是天将、遁干。
    /// 上边对地盘 巳午未申，下边 寅丑子亥，左边 辰卯，右边 酉戌。
    private var tianDiPan: some View {
        let top = ["巳", "午", "未", "申"]
        let bottom = ["寅", "丑", "子", "亥"]
        return Grid(horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow { blank(2); ForEach(top, id: \.self) { dunAt($0) }; blank(2) }
            GridRow { blank(2); ForEach(top, id: \.self) { jiangAt($0) }; blank(2) }
            GridRow { blank(2); ForEach(top, id: \.self) { zhiAt($0) }; blank(2) }
            sideRow(left: "辰", right: "酉")
            sideRow(left: "卯", right: "戌")
            GridRow { blank(2); ForEach(bottom, id: \.self) { zhiAt($0) }; blank(2) }
            GridRow { blank(2); ForEach(bottom, id: \.self) { jiangAt($0) }; blank(2) }
            GridRow { blank(2); ForEach(bottom, id: \.self) { dunAt($0) }; blank(2) }
        }
        .font(.title)
        .overlay {                                   // 课体放在整个天地盘的正中
            Text(tc(r.sanchuan.keTi)).font(.title3).foregroundStyle(.secondary)
        }
    }

    private func sideRow(left: String, right: String) -> some View {
        GridRow {
            dunAt(left); jiangAt(left); zhiAt(left)
            blank(2)
            zhiAt(right); jiangAt(right); dunAt(right)
        }
    }

    private func pos(_ di: String) -> LiurenResult.Pos { r.pan[Liuren.zhi.firstIndex(of: di) ?? 0] }
    private func zhiAt(_ di: String) -> some View { zhi(pos(di).zhi, kong: pos(di).kong) }
    private func jiangAt(_ di: String) -> some View { jiang(pos(di).jiang) }
    private func dunAt(_ di: String) -> some View { dun(pos(di).dun, gray: true) }

    @ViewBuilder
    private func blank(_ n: Int) -> some View {
        ForEach(0..<n, id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
    }

    // MARK: - 神煞（按十二支，只列有的）

    private func shenSha(_ list: [LiurenResult.ShaBranch]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list.filter { !$0.items.isEmpty }, id: \.branch) { b in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        colored(b.branch).font(.title3)
                        Text(tc(b.items.map(\.name).joined(separator: "  ")))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text(tc("神煞")).font(.title3).bold()
        }
    }

    // MARK: - 小部件

    /// 干支串按五行逐字上色。
    private func colored(_ s: String) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(s.enumerated()), id: \.offset) { _, c in GanZhiChar(c: c) }
        }
    }

    /// 天盘支：五行色加粗；空亡加框。
    private func zhi(_ z: String, kong: Bool) -> some View {
        colored(z)
            .padding(.horizontal, 3)
            .overlay {
                if kong { RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5), lineWidth: 1.5) }
            }
            .help(kong ? "空亡" : "")
    }

    /// 天将简称，按天将五行上色。
    private func jiang(_ j: String) -> some View {
        Text(tc(Liuren.jiangShort(j)))
            .foregroundStyle(Liuren.jiangWuXing(j)?.color ?? .primary)
    }

    /// 遁干：空亡没有遁干，写 ◎。三传里按五行上色，天地盘里灰色。
    private func dun(_ g: String?, gray: Bool) -> some View {
        Group {
            if let g {
                if gray { Text(g).foregroundStyle(.secondary) } else { colored(g) }
            } else {
                Text("◎").foregroundStyle(.secondary)
            }
        }
    }
}
