import SwiftUI

/// 各术数页面的内容（填的表单、排出来的盘、是不是在结果页），由主窗口 MainView 持有。
///
/// 为什么放在页面外面：底部切换术数时页面本身会销毁（同一时间只留一个页面、一套导航；
/// 几个页面都留着的话，macOS 上几套导航同时往窗口工具栏加东西会崩），
/// 但内容存在这里，切回来用它重建页面，排好的盘还在。
@Observable
final class PageStates {
    let bazi = BaziPageState()
    let meihua = MeihuaPageState()
    let liuren = LiurenPageState()
    var ichingPage: IChingHomeView.Page = .iching      // 易经类停在哪个子页（速查 / 梅花）
}

@Observable
final class BaziPageState {
    var name = ""
    var isMale = true
    var date = DateInputModel(years: HistoricalCalendar.baziYears, initial: .now())
    var birth: Birth?                  // 排盘用的公历时刻（农历已换算）
    var chart: BaziChart?
    var showChart = false
    var errorMessage: String?
    var byPillars = false              // 按八字反推
}

@Observable
final class MeihuaPageState {
    var date = DateInputModel(years: 1950...2060, initial: .now())
    var input = MeihuaInput()          // 起卦法 + 数字 / 指定的卦
    var timeSource: TimeSource = .solar
    var pickedTime: DateParts?         // 四柱反推选中的时刻
    var result: PaipanResult?
    var errorMessage: String?
}

@Observable
final class LiurenPageState {
    var question = ""
    var input = LiurenInput()
    var result: LiurenResult?
    var showResult = false
    var errorMessage: String?
    var current = CurrentChart()                 // 「存进案例库」要存的课
    var baseParams: [String: Any] = [:]          // 点「起课」时的参数（前后时辰都从它推）
    var hourOffset = 0                           // 现在比起课时前 / 后了几个时辰
}
