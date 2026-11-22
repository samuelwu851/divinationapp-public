import Foundation

struct Hexagram: Codable {
    let value: Int
    let name: String            // 本卦全名
    let order: Int
    let lines: [Int]
    let hexagramText: HexagramText
    // 京房八宫。可选：笔记里加八宫之前存下的排盘快照没有这些字段，不能因此解码失败
    var palace: Palace?
    var cuoguaPalace: Palace?
    var zongguaPalace: Palace?
    var huguaPalace: Palace?
    // 上下卦及五行（五行颜色用）。同样可选，兼容旧快照
    var trigrams: Trigrams?
    var cuoguaTrigrams: Trigrams?
    var zongguaTrigrams: Trigrams?
    var huguaTrigrams: Trigrams?

    // —— 三个衍生卦（扁平字段，对应 JSON：cuogua / cuogua_lines / cuogua_text …）——
    let cuogua: String
    let cuoguaLines: [Int]
    let cuoguaText: HexagramText
    let zonggua: String
    let zongguaLines: [Int]
    let zongguaText: HexagramText
    let hugua: String
    let huguaLines: [Int]
    let huguaText: HexagramText

    /// 把三个衍生卦整理成统一结构，方便界面遍历。computed 属性不参与解码。
    var derived: [DerivedHexagram] {
        [
            DerivedHexagram(label: "互卦", name: hugua,   lines: huguaLines,   text: huguaText,   palace: huguaPalace,   trigrams: huguaTrigrams),
            DerivedHexagram(label: "综卦", name: zonggua, lines: zongguaLines, text: zongguaText, palace: zongguaPalace, trigrams: zongguaTrigrams),
            DerivedHexagram(label: "错卦", name: cuogua,  lines: cuoguaLines,  text: cuoguaText,  palace: cuoguaPalace,  trigrams: cuoguaTrigrams),
        ]
    }
}

/// 京房八宫：属于哪一宫、第几世。界面显示成「乾宫 · 一世」。
struct Palace: Codable, Hashable {
    let name: String          // 宫名（三爻卦名）：乾 / 坎 / 艮 / 震 / 巽 / 離 / 坤 / 兌
    let stage: String         // 本宫 / 一世 … 五世 / 游魂 / 归魂
    var text: String { "\(name)宫 · \(stage)" }
}

/// 上下卦（三爻卦）及其五行。
struct Trigrams: Codable, Hashable {
    struct Part: Codable, Hashable {
        let name: String      // 乾 / 坎 …
        let wuxing: String    // 金 / 水 …
    }
    let lower: Part
    let upper: Part
}

struct HexagramText: Codable {
    let still: String           // 卦辞
    let lines: [String]         // 爻辞
}

/// 参卦的一组：本卦 → 变卦时，下卦或上卦这个三爻卦「原 → 变」起出的两个参卦。
/// 对应后端 cangua 命令 groups 里的一项。
struct CanGuaGroup: Codable, Identifiable {
    let part: String          // lower / upper
    let partName: String      // 下卦 / 上卦
    let from: String          // 原（三爻卦名）
    let to: String            // 变
    let guas: [CanGua]        // 参卦一（上原下变）、参卦二（上变下原）
    var id: String { part }
}

/// 一个参卦：卦名 + 六爻 + 卦辞爻辞。
struct CanGua: Codable {
    let label: String         // 参卦一 / 参卦二
    let value: Int
    let name: String
    let lines: [Int]
    let text: HexagramText
    var palace: Palace?       // 八宫（旧快照里没有）
    var trigrams: Trigrams?

    /// 转成衍生卦的统一结构，直接复用 DerivedHexagramCell（小卦图 + 点开看辞）。
    var derived: DerivedHexagram { DerivedHexagram(label: label, name: name, lines: lines, text: text, palace: palace, trigrams: trigrams) }
}

/// cangua 命令的响应（只取 groups）。
struct CanGuaResult: Codable {
    let groups: [CanGuaGroup]
}

/// 一个衍生卦（错 / 综 / 互）的统一表示，供界面和弹窗使用。
struct DerivedHexagram: Identifiable {
    let label: String           // 错卦 / 综卦 / 互卦
    let name: String            // 卦名
    let lines: [Int]
    let text: HexagramText
    var palace: Palace? = nil // 八宫：只在点开的浮窗里显示
    var trigrams: Trigrams? = nil
    var id: String { label }
}
