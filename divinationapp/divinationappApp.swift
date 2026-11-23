//
//  divinationappApp.swift
//  divinationapp
//
//  Created by samuelwu on 2026/10/03.
//

import SwiftUI

@main
struct divinationappApp: App {

    init() {
        Self.bootstrapPython()
        Self.testDispatch()        // 里程碑 1 自检（走通用分发器）
        Self.openCasebook()        // 打开案例库数据库
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .defaultSize(width: 625, height: 780)   // 打开时的大小；切换页面不随内容变化

        #if os(macOS)
        // 笔记（案例库）独立窗口：独立的关闭/最大化，点右下角笔记本图标打开。
        Window("笔记", id: "notes") {
            NotesWindowView()
        }
        .defaultSize(width: 518, height: 780)
        .windowResizability(.contentMinSize)        // 窗口最小尺寸跟内容走（笔记窗最窄 518，见 NotesWindowView.minWidth）

        // 笔记里点开的排盘：普通窗口（不挡住笔记，可拖动、缩放）。
        // 按排盘 id 区分：同一个排盘再点一次只会把已开的窗口提到前面。
        WindowGroup("排盘", id: "chart", for: Int.self) { $chartId in
            if let chartId {
                ChartDetailView(client: DivinationClient(), chartId: chartId, inWindow: true)
            }
        }
        .defaultSize(width: 760, height: 780)
        .restorationBehavior(.disabled)           // 重启 App 不自动恢复这些窗口
        #endif
    }

    /// 打开案例库 SQLite：调试用 casebook-debug.db，发行用 casebook.db，
    /// 都放在 Application Support/divination/ 下。
    private static func openCasebook() {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil, create: true) else {
            print("找不到 Application Support 目录"); return
        }
        let dir = appSupport.appendingPathComponent("divination", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        #if DEBUG
        let dbName = "casebook-debug.db"
        #else
        let dbName = "casebook.db"
        #endif
        let path = dir.appendingPathComponent(dbName).path

        if let dir = DivinationClient().casebookOpen(path: path) {
            CasebookPaths.attachmentsDir = URL(fileURLWithPath: dir, isDirectory: true)
            print("✅ casebook 打开：\(path)")
        } else {
            print("❌ casebook 打开失败：\(path)")
        }
    }

    /// 在 app 启动时初始化嵌入的 Python 解释器，并把我们的包目录加入搜索路径。
    private static func bootstrapPython() {
        // 嵌入的框架位于 app bundle 的 Frameworks 目录下。
        // 注意：Versions/3.13 这段是 macOS 框架布局；之后推 iOS 时再按 iOS 布局调整。
        guard let frameworks = Bundle.main.privateFrameworksURL else {
            print("找不到 Frameworks 目录"); return
        }
        let home = frameworks
            .appendingPathComponent("Python.framework/Versions/3.13").path

        // divination 包被打进了 app 资源区，它的父目录就是 resourceURL。
        guard let appPath = Bundle.main.resourceURL?.path else {
            print("找不到资源目录"); return
        }

        let rc = py_bootstrap(home, appPath)
        print(rc == 0 ? "✅ py_bootstrap 成功" : "❌ py_bootstrap 失败 rc=\(rc)")
    }

    /// 里程碑 1 自检：通过通用分发器发一条 lookup 命令，把卦象 JSON 打印出来。
    private static func testDispatch() {
        let request = #"{"cmd":"lookup","value":63}"#   // 一条请求命令
        guard let c = py_dispatch(request) else {
            print("dispatch 返回 NULL（看上面有没有 Python 报错）"); return
        }
        let json = String(cString: c)   // C 字符串 → Swift String（会复制）
        py_free_string(c)               // 复制完，释放 C 那份，避免泄漏
        print("✅ dispatch(lookup,63) =\n\(json)")
    }
}
