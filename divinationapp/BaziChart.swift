import Foundation

/// 八字全盘的解码模型（对应后端 bazi_chart / liuyue 命令的 JSON）。
/// 解码时 DivinationClient 用 .convertFromSnakeCase，故 gan_shishen → ganShishen 等自动对应。

/// 藏干（地支里藏的天干）及其相对日主的十神。也用于大运/流年/流月的地支藏干十神。
struct CangGan: Codable, Identifiable {
    let gan: String        // 藏干天干，如 "甲"
    let shishen: String    // 相对日主的十神，如 "偏印"
    var id: String { gan }
}

/// 一柱（年/月/日/时）：干支 + 天干十神 + 纳音 + 藏干十神。
struct BaziPillar: Codable {
    let ganzhi: String        // 干支，如 "丙寅"
    let ganShishen: String    // 天干十神（日柱为 "日主"）
    let nayin: String         // 纳音
    let canggan: [CangGan]    // 地支藏干及十神
}

/// 四柱。
struct BaziPillars: Codable {
    let year: BaziPillar
    let month: BaziPillar
    let day: BaziPillar
    let hour: BaziPillar
}

/// 起运（岁、月、日）。
struct BaziQiyun: Codable {
    let years: Int
    let months: Int
    let days: Int
}

/// 交运口诀：逢某干之年、某节后某天换大运。`text` 为后端拼好的现成文案。
struct BaziJiaoyun: Codable {
    let yearGan: String      // year_gan，某年的年干
    let jie: String          // 节气名
    let offsetDays: Int      // offset_days，节后第几天
    let text: String         // 「逢戊年立春后27天换大运」
}

/// 流年：某年干支 + 天干十神 + 藏干十神 + 纳音。
struct BaziLiuNian: Codable, Identifiable {
    let year: Int
    let ganzhi: String
    let ganShishen: String
    let canggan: [CangGan]
    let nayin: String
    var id: Int { year }
}

/// 一步大运：干支 + 十神 + 藏干 + 纳音 + 起运年/岁 + 交节信息，并内嵌该步 10 个流年。
struct BaziDaYun: Codable, Identifiable {
    let ganzhi: String
    let ganShishen: String
    let canggan: [CangGan]
    let nayin: String
    let startYear: Int        // 该步大运起始公历年
    let startAge: Int         // 起始虚岁
    let jie: String           // 交运所在节
    let offsetDays: Int       // 交运落在该节后第几天
    let liunian: [BaziLiuNian]
    var id: Int { startYear }
}

/// 八字全盘（bazi_chart）。
struct BaziChart: Codable {
    let gender: String        // "乾造" / "坤造"
    let inputTime: String     // 公历时刻 "YYYY-MM-DD HH:MM"
    let lunarTime: String     // 农历中文
    let pillars: BaziPillars
    let qiyun: BaziQiyun
    let startSolar: String    // 起运精确时刻
    let jiaoyun: BaziJiaoyun  // 交运口诀
    let dayun: [BaziDaYun]
}

/// 流月：某月（1=正月…12=腊月）干支 + 十神 + 藏干 + 纳音。
struct BaziLiuYue: Codable, Identifiable {
    let month: Int
    let ganzhi: String
    let ganShishen: String
    let canggan: [CangGan]
    let nayin: String
    var id: Int { month }
}

/// 某流年的 12 流月（liuyue）。
struct BaziLiuYueResult: Codable {
    let year: Int
    let months: [BaziLiuYue]
}
