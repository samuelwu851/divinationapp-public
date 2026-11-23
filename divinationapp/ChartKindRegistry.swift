import SwiftUI

/// 笔记里可插入的「额外」排盘类型（内置的八字 / 易经速查 / 梅花易数不走这里）。
///
/// 为什么要注册表：插件（比如只在内部版才有的术数）的插入表单和详情视图写在插件自己的文件里，
/// 启动时注册进来；公共的 ChartInsertSheet / ChartDetailView 只认这张表，不用为每种新类型加分支，
/// 也就不会在公共文件里出现插件的名字。
///
/// 和后端的约定：
/// - `type` 就是后端 chart_create 的类型（插件在 CHART_BUILDERS 里注册的名字）；
/// - 笔记正文里的卡片由后端快照里的通用 `card` 画（见 casebook/charts.py），这里不用管。
struct ChartKind {
    /// 后端排盘类型，如 chart_create 的 "type"。
    let type: String
    /// 插入面板分段控件上显示的名字，也用作详情窗口标题。
    let title: String
    /// 详情窗口里要不要显示「五行颜色」勾选框。
    var showsWuxingToggle: Bool = true
    /// 插入表单。表单每次内容变化都调 `setParams`，把要传给 chart_create 的参数交出来；
    /// 参数还不完整时传 nil（「插入」按钮会提示）。
    let makeInsertForm: (_ setParams: @escaping ([String: Any]?) -> Void) -> AnyView
    /// 详情视图：拿到 chart_get 的原始 JSON 自己解码；解不开返回 nil（显示「不支持」）。
    /// 只给内容本身，外面的滚动、边距、五行颜色勾选框由 ChartDetailView 统一加。
    let makeDetail: (_ chartJSON: Data) -> AnyView?
}

@MainActor
enum ChartKindRegistry {
    private(set) static var kinds: [ChartKind] = []

    /// App 启动时调用。同一类型注册两次以后一次为准。
    static func register(_ kind: ChartKind) {
        kinds.removeAll { $0.type == kind.type }
        kinds.append(kind)
    }

    static func kind(for type: String) -> ChartKind? {
        kinds.first { $0.type == type }
    }
}
