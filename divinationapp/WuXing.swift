import SwiftUI

/// 五行：天干地支单字 → 颜色（用于八字上色）。
enum WuXing {
    case wood, fire, earth, metal, water

    var color: Color {
        switch self {
        case .wood:  return .green
        case .fire:  return .red
        case .earth: return Color(red: 0.55, green: 0.35, blue: 0.15)  // 咖啡色
        case .metal: return .yellow
        case .water: return .blue
        }
    }

    /// 天干地支单字 → 五行。
    static func of(_ c: Character) -> WuXing? {
        switch c {
        case "甲", "乙", "寅", "卯":                return .wood
        case "丙", "丁", "巳", "午":                return .fire
        case "戊", "己", "辰", "戌", "丑", "未":     return .earth
        case "庚", "辛", "申", "酉":                return .metal
        case "壬", "癸", "子", "亥":                return .water
        default:                                   return nil
        }
    }
}

/// 一个干支单字，按五行上色（无 emoji）。
struct GanZhiChar: View {
    let c: Character
    var body: some View {
        Text(String(c))
            .foregroundStyle(WuXing.of(c)?.color ?? .primary)
            .bold()
    }
}

/// 四柱展示：四柱并排，每柱天干在上、地支在下，按五行上色。
/// 梅花易数等多处共用。
struct BaziPillarsView: View {
    let pillars: [String]          // [年柱, 月柱, 日柱, 时柱]，每柱两字
    var charFont: Font = .largeTitle

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(pillars.enumerated()), id: \.offset) { _, pillar in
                let chars = Array(pillar)
                VStack(spacing: 2) {
                    if chars.count >= 1 { GanZhiChar(c: chars[0]).font(charFont) }
                    if chars.count >= 2 { GanZhiChar(c: chars[1]).font(charFont) }
                }
            }
        }
    }
}

/// 四柱 + 藏干 + 纳音（梅花易数等用：不要十神、大运流年那些）。
/// 每柱：天干、地支（大字，五行上色），下面一行藏干（小字，五行上色），再下面纳音（和藏干一样大，黑色）。
struct BaziPillarsDetailView: View {
    let pillars: BaziPillars
    var charFont: Font = .largeTitle

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array([pillars.year, pillars.month, pillars.day, pillars.hour].enumerated()), id: \.offset) { _, p in
                let chars = Array(p.ganzhi)
                VStack(spacing: 3) {
                    if chars.count >= 1 { GanZhiChar(c: chars[0]).font(charFont) }
                    if chars.count >= 2 { GanZhiChar(c: chars[1]).font(charFont) }
                    HStack(spacing: 2) {                                // 藏干
                        ForEach(Array(p.canggan.enumerated()), id: \.offset) { _, g in
                            if let c = g.gan.first { GanZhiChar(c: c).font(.callout) }
                        }
                    }
                    Text(p.nayin).font(.callout).foregroundStyle(.primary)      // 纳音：和藏干一样大，黑色
                }
                .help("藏干：\(p.canggan.map(\.gan).joined(separator: "、"))　纳音：\(p.nayin)")
            }
        }
    }
}

// MARK: - 卦的五行颜色（易经速查 / 梅花易数「五行颜色」开关）

/// 卦爻的五行颜色：传统五色（木青、火赤、土黄、金白、水黑），但都调柔和，避免满屏鲜艳看花眼。
/// 金是白色：用柔和的灰白（亮白看久了累眼），比米色背景深一档，再加一圈细灰边。
enum GuaWuXingColor {
    static func fill(_ wuxing: String?) -> Color {
        switch wuxing {
        case "木": return Color(hex: 0x6E9873)   // 青：灰绿
        case "火": return Color(hex: 0xB45A50)   // 赤：砖红
        case "土": return Color(hex: 0xC4A24F)   // 黄：赭黄
        case "金": return Color(hex: 0xEEEBE5)   // 白：用柔和的灰白，不用亮白（看久了累眼）
        case "水": return Color(hex: 0x33363A)   // 黑：深灰黑
        default:   return .primary              // 没开五行颜色：原来的黑色
        }
    }

    static func stroke(_ wuxing: String?) -> Color? {
        wuxing == "金" ? Color(hex: 0xACA89F) : nil      // 细灰边，和米色背景分开
    }
}

/// 一根爻里的一段（阳爻一段，阴爻两段）：按五行填色，金加描边。
struct YaoBar: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    var wuxing: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(GuaWuXingColor.fill(wuxing))
            .overlay {
                if let s = GuaWuXingColor.stroke(wuxing) {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(s, lineWidth: 1)
                }
            }
            .frame(width: width, height: height)
    }
}

/// 「五行颜色」开关，用环境值往下传：所有画卦的视图自己读，不用一层层传参数。
private struct WuxingColorOnKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var wuxingColorOn: Bool {
        get { self[WuxingColorOnKey.self] }
        set { self[WuxingColorOnKey.self] = newValue }
    }
}

/// 第 index 爻（0 = 初爻）属于下卦还是上卦，取对应的五行。
/// 新数据由后端给出 trigrams；旧的排盘快照没有这一项，就按六爻自己推（和网页卡片的兜底一致）。
func yaoWuxing(_ index: Int, _ trigrams: Trigrams?, lines: [Int]) -> String? {
    if let trigrams { return index < 3 ? trigrams.lower.wuxing : trigrams.upper.wuxing }
    guard lines.count == 6 else { return nil }
    let part = index < 3 ? lines[0..<3] : lines[3..<6]              // 从下往上的三爻
    return trigramWuxingFallback[part.map(String.init).joined()]
}

/// 三爻卦（从下往上的阴阳）→ 五行：乾兌金，離火，震巽木，坎水，艮坤土。只给旧快照兜底用。
private let trigramWuxingFallback: [String: String] = [
    "111": "金", "110": "金", "101": "火", "100": "木",    // 乾 兌 離 震
    "011": "木", "010": "水", "001": "土", "000": "土",    // 巽 坎 艮 坤
]
