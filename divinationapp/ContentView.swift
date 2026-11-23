import SwiftUI

struct ContentView: View {
    @State private var store = IChingStore()
    @Environment(CurrentChart.self) private var current      // 「存进案例库」要存的盘
    @AppStorage("wuxingColorOn") private var wuxingColorOn = false   // 五行颜色（易经速查、梅花易数共用）

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 开关放左上角：五行颜色 + 变卦模式（右上角留给切换术数的 ⋯）
                HStack(spacing: 16) {
                    Toggle("五行颜色", isOn: $wuxingColorOn).fixedSize()
                    Toggle("变卦模式", isOn: $store.showChanged).fixedSize()
                    Spacer()
                }

                if let org = store.original {
                    if store.showChanged, let chg = store.changed {
                        // 本卦|变卦 + 崔氏易林 + 错综互 + 参卦（抽成 DualGuaView，梅花易数也复用）
                        DualGuaView(original: org, changed: chg,
                                    changingLines: store.changingLines, yilin: store.yilin,
                                    cangua: store.cangua,
                                    onFlipOriginal: { store.flipOriginal(line: $0) },
                                    onFlipChanged: { store.flipChanged(line: $0) })
                    } else {
                        // 速查模式：完整面板（内联爻辞/卦辞/错综互）
                        HexagramPanelView(hex: org, onFlip: { store.flipOriginal(line: $0) })
                    }
                } else if let msg = store.errorMessage {
                    Text("出错了：\(msg)").foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)     // 内容区占满宽度，居中不随滚动条增减而左右跳动
            .environment(\.wuxingColorOn, wuxingColorOn)
        }
        .scrollIndicators(.never)           // 不显示竖滚动条 → 拉高时不再左右抖动
        .onAppear { store.load(); updateCurrent() }
        .onChange(of: store.original?.value) { _, _ in updateCurrent() }
        .onChange(of: store.changed?.value) { _, _ in updateCurrent() }
        .onChange(of: store.showChanged) { _, _ in updateCurrent() }
    }

    /// 现在这个盘（存进案例库用）：本卦；开了变卦模式再加变卦。
    private func updateCurrent() {
        guard let org = store.original else { current.spec = nil; return }
        let chg = store.showChanged ? (store.changed ?? org) : org
        current.spec = ChartSaveSpec(type: "iching", params: ["org_value": org.value, "chg_value": chg.value])
    }
}

/// 一个卦的面板。两种模式：
/// - 完整版(compact=false)：卦名 + 六爻+爻辞 + 用九/用六 + 卦辞 + 错综互（速查用）。
/// - 紧凑版(compact=true)：只有卦名 + 六爻；点卦名弹浮窗看卦辞/爻辞（变卦模式用）。
/// onFlip 把被点的爻位(1-6)回调给外面。
struct HexagramPanelView: View {
    let hex: Hexagram
    var compact: Bool = false
    var changingLines: Set<Int> = []     // 动爻下标(0-5)
    var showArrow: Bool = false          // 动爻右侧是否画 →（本卦为 true）
    var readOnly: Bool = false           // 只读：点爻/点卦名都只弹爻辞浮窗，不变卦
    let onFlip: (Int) -> Void

    @State private var showDetail = false   // 紧凑版：卦名点开的浮窗
    @Environment(\.wuxingColorOn) private var colorOn

    var body: some View {
        // 速查(完整)模式下有 maxWidth:.infinity 的卦辞/错综互会把 VStack 撑满全宽，
        // 若整体 .leading 卦名/卦图就被顶到最左——完整模式用 .center 保持居中；
        // 紧凑(变卦)模式保留 .leading，让卦名与带箭头的卦图左对齐。
        VStack(alignment: compact ? .leading : .center, spacing: 12) {
            // 卦名：限宽到卦图(180)并居中 → 与下方卦图对齐
            Text(hex.name).font(.largeTitle).bold()
                .frame(width: 180, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { if compact || readOnly { showDetail = true } }
                .popover(isPresented: $showDetail) { HexagramDetailView(hex: hex) }

            // 六爻（点击 = 变爻）
            VStack(alignment: .leading, spacing: 4) {
                ForEach((0..<hex.lines.count).reversed(), id: \.self) { index in
                    HStack(spacing: 12) {
                        LineView(isYang: hex.lines[index] == 1,
                                 wuxing: colorOn ? yaoWuxing(index, hex.trigrams, lines: hex.lines) : nil)   // 上下卦各自的五行色
                            .onTapGesture { if readOnly { showDetail = true } else { onFlip(index + 1) } }

                        // 动爻箭头（只有 →，且只在本卦侧）
                        if showArrow {
                            Text(changingLines.contains(index) ? "→" : "")
                                .font(.title3).foregroundStyle(.black).frame(width: 22)
                        }

                        // 完整版才内联爻辞
                        if !compact, index < hex.hexagramText.lines.count {
                            Text(hex.hexagramText.lines[index])
                                .font(.title3).frame(maxWidth: 320, alignment: .leading)
                        }
                    }
                    .frame(height: 44)
                }
            }

            // 八宫：卦象下面一行小字，如「乾宫 · 一世」
            if let palace = hex.palace {
                Text(palace.text)
                    .font(.title3).foregroundStyle(.secondary)          // 字号同崔氏易林的句子，灰色
                    .frame(width: 180, alignment: .center)       // 和卦图同宽、居中对齐
            }

            // 完整版才显示：用九/用六、卦辞、错综互
            if !compact {
                Text(hex.hexagramText.lines.count == 7 ? hex.hexagramText.lines[6] : "")
                    .font(.title3).frame(height: 14)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("卦辞：\(hex.hexagramText.still)").font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)
                DerivedRow(hex: hex)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }
        }
    }
}

/// 本卦|变卦 的完整中心区：两面板并排 + 崔氏易林 + 两卦各自的错综互 + 参卦。
/// 易经速查（可变爻）和梅花易数（只读）共用——readOnly 决定点爻是变卦还是只弹爻辞。
struct DualGuaView: View {
    let original: Hexagram
    let changed: Hexagram
    let changingLines: Set<Int>
    let yilin: String?
    var cangua: [CanGuaGroup] = []       // 参卦（没有动爻时为空，不显示）
    var readOnly: Bool = false
    var onFlipOriginal: (Int) -> Void = { _ in }
    var onFlipChanged: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 18) {
            // 本卦 | 变卦 并排
            HStack(alignment: .top, spacing: 48) {
                HexagramPanelView(hex: original, compact: true,
                                  changingLines: changingLines,
                                  showArrow: true,            // 本卦侧画 → 指向变卦
                                  readOnly: readOnly,
                                  onFlip: onFlipOriginal)
                HexagramPanelView(hex: changed, compact: true,
                                  changingLines: changingLines,
                                  showArrow: false,
                                  readOnly: readOnly,
                                  onFlip: onFlipChanged)
            }

            // 崔氏易林：两卦下方
            if let yilin {
                Divider()
                VStack(spacing: 6) {
                    Text("崔氏易林").font(.headline)
                    Text(yilin).font(.title3).frame(maxWidth: 600)
                }
            }

            // 错 / 综 / 互：在易林下方（本卦、变卦各一组）
            HStack(alignment: .top, spacing: 48) {
                VStack(spacing: 6) {
                    Text("本卦").font(.caption).foregroundStyle(.secondary)
                    DerivedRow(hex: original)
                }
                VStack(spacing: 6) {
                    Text("变卦").font(.caption).foregroundStyle(.secondary)
                    DerivedRow(hex: changed)
                }
            }
            .padding(.top, 8)

            // 参卦：错综互六个卦的下方。每组 = 下卦或上卦「原→变」起的两个参卦（参卦一 上原下变，参卦二 上变下原）
            if !cangua.isEmpty {
                Divider()
                VStack(spacing: 10) {
                    Text("参卦").font(.headline)
                    HStack(alignment: .top, spacing: 48) {
                        ForEach(cangua) { g in
                            VStack(spacing: 6) {
                                Text("\(g.partName)　\(g.from) → \(g.to)")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 36) {
                                    ForEach(g.guas, id: \.label) { DerivedHexagramCell(derived: $0.derived) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 错 / 综 / 互 三个小卦一排（点各自弹 popover）。
struct DerivedRow: View {
    let hex: Hexagram
    var body: some View {
        HStack(spacing: 36) {
            ForEach(hex.derived) { d in
                DerivedHexagramCell(derived: d)
            }
        }
    }
}

/// 单根爻的画法：阳 = 一整条；阴 = 中间断开两段。
struct LineView: View {
    let isYang: Bool
    var wuxing: String? = nil          // 五行颜色：nil = 原来的黑色

    var body: some View {
        HStack(spacing: 12) {
            if isYang {
                YaoBar(width: 172, height: 26, radius: 4, wuxing: wuxing)
            } else {
                YaoBar(width: 80, height: 26, radius: 4, wuxing: wuxing)
                YaoBar(width: 80, height: 26, radius: 4, wuxing: wuxing)
            }
        }
        .frame(width: 180)                 // 固定总宽，阴阳两种对齐
        .contentShape(Rectangle())         // 整行(含阴爻中间空隙)都能点
    }
}

// 用于互卦、综卦、错卦的小号【单爻】
struct MiniLine: View {
    let isYang: Bool
    var wuxing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if isYang {
                YaoBar(width: 60, height: 8, radius: 2, wuxing: wuxing)
            } else {
                YaoBar(width: 27, height: 8, radius: 2, wuxing: wuxing)
                YaoBar(width: 27, height: 8, radius: 2, wuxing: wuxing)
            }
        }
        .frame(width: 60)
    }
}

/// 用于互卦、综卦、错卦的小号【整卦图】：六根 MiniLine 自下而上叠起来。
struct MiniHexagram: View {
    let lines: [Int]            // lines[0] = 初爻(最下)
    var trigrams: Trigrams? = nil
    @Environment(\.wuxingColorOn) private var colorOn
    var body: some View {
        VStack(spacing: 4) {
            ForEach((0..<lines.count).reversed(), id: \.self) { i in
                MiniLine(isYang: lines[i] == 1, wuxing: colorOn ? yaoWuxing(i, trigrams, lines: lines) : nil)
            }
        }
    }
}

/// 一个衍生卦的小卡片：卦名 + 小卦图 + 类型标签；点自己弹出详情 popover。
struct DerivedHexagramCell: View {
    let derived: DerivedHexagram
    @State private var showing = false          // 本 cell 自己的弹窗开关

    var body: some View {
        VStack(spacing: 8) {
            Text(derived.name).font(.headline)        // 卦名在上
            MiniHexagram(lines: derived.lines, trigrams: derived.trigrams)   // 卦图在中（五行颜色按上下卦）
            Text(derived.label)                        // 错/综/互 在下
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())                     // 整块可点
        .onTapGesture { showing = true }               // 点→弹出自己的 popover
        .popover(isPresented: $showing) {              // 从这个小卦冒出来；点别处关闭
            DerivedDetailView(derived: derived)
        }
    }
}

/// 衍生卦详情弹窗：卦名、卦辞、带爻题前缀的爻辞（初爻在最前）。
struct DerivedDetailView: View {
    let derived: DerivedHexagram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 卦名旁边标八宫（小卦只在浮窗里显示八宫）
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(derived.label)：\(derived.name)").font(.title).bold()
                if let palace = derived.palace {
                    Text(palace.text).font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text("卦辞：\(derived.text.still)")
                .font(.title3)

            Divider()

            ForEach(0..<derived.text.lines.count, id: \.self) { i in
                if i < 6 {
                    Text("\(yaoTitle(index: i, isYang: derived.lines[i] == 1))　\(derived.text.lines[i])")
                } else {
                    Text(derived.text.lines[i])
                }
            }
        }
        .padding(28)
        .frame(minWidth: 320)
    }
}

/// 本卦 / 变卦 的详情浮窗（变卦模式点卦名弹出）：卦名、卦辞、带爻题的爻辞。
struct HexagramDetailView: View {
    let hex: Hexagram

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hex.name).font(.title).bold()
                .frame(maxWidth: .infinity, alignment: .center)

            Text("卦辞：\(hex.hexagramText.still)").font(.title3)

            Divider()

            ForEach(0..<hex.hexagramText.lines.count, id: \.self) { i in
                if i < 6 {
                    Text("\(yaoTitle(index: i, isYang: hex.lines[i] == 1))　\(hex.hexagramText.lines[i])")
                } else {
                    Text(hex.hexagramText.lines[i])
                }
            }
        }
        .padding(28)
        .frame(minWidth: 320)
    }
}

/// 根据爻位(0=初…5=上)和阴阳，拼出爻题：初九 / 九二 / 上六 …
func yaoTitle(index: Int, isYang: Bool) -> String {
    let yinYang = isYang ? "九" : "六"
    switch index {
    case 0: return "初\(yinYang)"                       // 初九 / 初六
    case 5: return "上\(yinYang)"                       // 上九 / 上六
    default: return "\(yinYang)\(["二","三","四","五"][index - 1])" // 九二 / 六三…
    }
}
