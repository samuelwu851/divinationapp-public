import Foundation

/// 大六壬排盘结果（对应后端 liuren_paipan 的 JSON，键名蛇形转驼峰）。
struct LiurenResult: Decodable {
    /// 一个位置：天盘支和它带的天将、遁干、六亲、是否空亡。
    /// 十二宫多一个 di（地盘支），四课多一个 down（下面的地盘支或日干），行年多一个 ganzhi。
    struct Pos: Decodable {
        let zhi: String
        let jiang: String
        let dun: String?
        let qin: String
        let kong: Bool
        let di: String?
        let down: String?
        let ganzhi: String?
    }
    struct SanChuan: Decodable {
        let keTi: String
        let chuan: [Pos]
    }
    struct Ming: Decodable {
        let name: String
        var gender: String? = nil     // 男 / 女；旧的存档里没有
        let birth: String
        let benming: Pos
        let xingnian: Pos?
    }
    struct Input: Decodable {
        let year: String?
        let month: String?
        let day: String
        let hour: String?
        let shi: String
        let yuejiang: String
        let qi: String?
    }
    struct Sha: Decodable {
        let category: String
        let name: String
        let branches: [String]
    }
    struct ShaBranch: Decodable {
        struct Item: Decodable { let name: String; let category: String }
        let branch: String
        let items: [Item]
    }

    let day: String
    let yuejiang: String
    let shi: String
    let dayNight: String
    let method: String
    let guiren: String?       // "std" / "alt"；以前存的课没有这项，当 std
    let xun: String
    let kong: [String]
    let pan: [Pos]            // 地盘子到亥
    let sike: [Pos]           // 第一课到第四课
    let sanchuan: SanChuan
    let nianming: [Ming]
    let input: Input
    let shensha: [ShaBranch]?
    let shenshaList: [Sha]?
}

/// 六壬页面用到的简称和对照表。
enum Liuren {
    static let zhi = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)
    static let gan = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)

    /// 六十甲子
    static let jiazi: [String] = (0..<60).map { gan[$0 % 10] + zhi[$0 % 12] }

    /// 公历年 → 该年（立春后）的年干支。
    static func yearGanZhi(_ year: Int) -> String {
        jiazi[((year - 4) % 60 + 60) % 60]
    }

    static func jiangShort(_ j: String) -> String {
        ["贵人": "贵", "螣蛇": "蛇", "朱雀": "朱", "六合": "合", "勾陈": "勾", "青龙": "龙",
         "天空": "空", "白虎": "虎", "太常": "常", "玄武": "玄", "太阴": "阴", "天后": "后"][j] ?? j
    }

    /// 十二天将的五行（上色用）：贵勾空常土，蛇朱火，合龙木，虎阴金，玄后水。
    static func jiangWuXing(_ j: String) -> WuXing? {
        switch j {
        case "贵人", "勾陈", "天空", "太常": return .earth
        case "螣蛇", "朱雀":               return .fire
        case "六合", "青龙":               return .wood
        case "白虎", "太阴":               return .metal
        case "玄武", "天后":               return .water
        default:                          return nil
        }
    }

    /// 旬首「甲辰」→ 旬丁「丁未」、旬尾「癸丑」。
    static func xunDing(_ xun: String) -> String { xunAt(xun, 3) }
    static func xunWei(_ xun: String) -> String { xunAt(xun, 9) }
    private static func xunAt(_ xun: String, _ n: Int) -> String {
        guard let z = xun.last, let i = zhi.firstIndex(of: String(z)) else { return "" }
        return gan[n] + zhi[(i + n) % 12]
    }

    static func qinShort(_ q: String) -> String {
        ["父母": "父", "兄弟": "兄", "子孙": "子", "妻财": "财", "官鬼": "官"][q] ?? q
    }
}

/// 六壬页面的繁简：默认繁体（设置里可切）。
///
/// 只用一张「简 → 繁」逐字对照表，收的是六壬页面上会出现的字（天将、六亲、课体、神煞名、表头）。
/// 按六壬书上的写法定，不是通用转换：天后的「后」不转（不是「後」）；吊客 → 弔客，游都 → 遊都，贼克 → 賊剋。
/// 「前后几个时辰」的「后」是「後」，在用的地方单独写，不放进表里（不然天后会变天後）。
enum LiurenScript {
    static let key = "liurenTraditional"

    private static let table: [Character: Character] = ["专": "專", "丝": "絲", "丧": "喪", "书": "書", "产": "產", "仪": "儀", "会": "會", "传": "傳", "伤": "傷", "儿": "兒", "关": "關", "兽": "獸", "军": "軍", "冲": "衝", "别": "別", "医": "醫", "华": "華", "厌": "厭", "厕": "廁", "吊": "弔", "学": "學", "审": "審", "对": "對", "将": "將", "岁": "歲", "师": "師", "废": "廢", "弹": "彈", "归": "歸", "悬": "懸", "愿": "願", "戏": "戲", "战": "戰", "时": "時", "气": "氣", "润": "潤", "灾": "災", "炉": "爐", "烛": "燭", "猪": "豬", "电": "電", "盖": "蓋", "盗": "盜", "祸": "禍", "秽": "穢", "穑": "穡", "绝": "絕", "绞": "絞", "绳": "繩", "网": "網", "视": "視", "诏": "詔", "语": "語", "谩": "謾", "负": "負", "财": "財", "责": "責", "贤": "賢", "贵": "貴", "贼": "賊", "车": "車", "轩": "軒", "转": "轉", "辕": "轅", "进": "進", "连": "連", "遥": "遙", "钥": "鑰", "钱": "錢", "镜": "鏡", "长": "長", "门": "門", "间": "間", "阳": "陽", "阴": "陰", "陈": "陳", "鸡": "雞", "风": "風", "飞": "飛", "马": "馬", "驿": "驛", "鲁": "魯", "黄": "黃", "龙": "龍", "孙": "孫", "坟": "墳", "狱": "獄", "圣": "聖", "游": "遊", "机": "機", "克": "剋", "从": "從", "个": "個", "临": "臨", "删": "刪", "动": "動", "复": "復", "显": "顯", "栏": "欄", "没": "沒", "认": "認", "设": "設", "课": "課", "调": "調", "选": "選", "还": "還", "项": "項", "顺": "順", "盘": "盤", "浅": "淺", "昼": "晝", "体": "體", "亲": "親", "宫": "宮", "庙": "廟", "杀": "殺", "劳": "勞", "难": "難", "罗": "羅", "乐": "樂", "寿": "壽", "双": "雙", "头": "頭", "无": "無", "宝": "寶", "库": "庫", "处": "處", "极": "極", "余": "餘", "么": "麼", "为": "為", "们": "們", "这": "這"]

    static func trad(_ s: String) -> String {
        String(s.map { table[$0] ?? $0 })
    }
}

extension DivinationClient {
    /// 大六壬排盘。params 见 liuren/service.py 开头的说明。
    func liuren(_ params: [String: Any]) -> (LiurenResult?, String?) {
        callWithError("liuren_paipan", params)
    }
}
