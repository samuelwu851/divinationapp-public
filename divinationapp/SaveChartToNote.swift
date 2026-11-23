import SwiftUI

/// 「存进案例库」：排盘页面上点笔的图标 → 打开笔记窗口，新建一篇笔记，正文里已经放好这个排盘。
///
/// - 各排盘页把「现在这个盘」放进 CurrentChart（没排出来就是 nil，笔变灰）；
/// - 点笔：CasebookOpener 记下要新建的排盘，打开笔记窗口；笔记窗口看到后推进编辑器（NoteEditTarget.newWithChart）；
/// - 编辑器建笔记、排盘、插卡片；和普通新建一样：没保存就离开，这篇笔记会被删掉。

/// 要存的排盘：类型 + 参数（参数存成 JSON 字符串，好比较、好放进导航路径）。
struct ChartSaveSpec: Hashable {
    let id = UUID()
    let type: String
    let paramsJSON: String

    init?(type: String, params: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: params),
              let json = String(data: data, encoding: .utf8) else { return nil }
        self.type = type
        self.paramsJSON = json
    }

    var params: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(paramsJSON.utf8))) as? [String: Any] ?? [:]
    }
}

/// 排盘页现在显示的这个盘（排盘页写，顶上的笔读）。
@Observable
final class CurrentChart {
    var spec: ChartSaveSpec?
}

/// 排盘窗口 → 笔记窗口：要新建一篇带这个排盘的笔记。
@Observable
final class CasebookOpener {
    @MainActor static let shared = CasebookOpener()
    var pending: ChartSaveSpec?
}

/// 顶上工具栏里的「存进案例库」按钮（笔的图标）。
struct SaveChartButton: View {
    let current: CurrentChart
    @Environment(\.openWindow) private var openWindow
    @State private var confirm = false

    var body: some View {
        Button {
            if current.spec != nil { confirm = true }          // 先问一下
        } label: {
            PenIcon(color: current.spec == nil ? .secondary.opacity(0.4) : .primary, lineWidth: 1.6)
                .frame(width: 18, height: 18)
        }
        .disabled(current.spec == nil)
        .help(current.spec == nil ? "先排出一个盘，才能存进案例库" : "存进案例库（新建一篇笔记，放进这个排盘）")
        .alert("要把当前排盘存进案例库吗？", isPresented: $confirm) {
            Button("存进案例库") { save() }
            Button("取消", role: .cancel) {}
        }
    }

    private func save() {
        guard let spec = current.spec else { return }
        CasebookOpener.shared.pending = spec
        #if os(macOS)
        openWindow(id: "notes")
        #endif
    }
}
