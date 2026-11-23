import SwiftUI
#if os(macOS)
import AppKit
#endif

/// App 根视图：底部可横滑的「术数大类」切换栏（易经 / 八字…），默认进易经。
/// 易经类内部的子术数（易经速查 / 梅花易数）仍用右上角 ⋯ 菜单切换。
struct MainView: View {
    enum Section: String, CaseIterable {
        case iching = "易经"
        case bazi   = "八字"
    }

    @State private var section: Section = .iching
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch section {
                case .iching: IChingHomeView()
                case .bazi:   BaziView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            ZStack {
                bottomBar                           // 居中胶囊切换栏
                HStack {                            // 右下角：笔记本图标（在胶囊之外）
                    Spacer()
                    Button { openNotes() } label: {
                        NotebookIcon(color: .secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)   // 仅设很小的下限，允许自由缩放
        .background(PatternBackground())          // 全 app 背景纹理
        #if os(macOS)
        .background(WindowConfigurator(width: 625, height: 780))
        #endif
    }

    /// 打开笔记（案例库）独立窗口。
    private func openNotes() {
        #if os(macOS)
        openWindow(id: "notes")
        #endif
    }

    /// 底部大类切换栏：居中的圆角胶囊，宽度随术数个数自适应，当前项高亮。
    private var bottomBar: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases, id: \.self) { s in
                Button { section = s } label: {
                    Text(s.rawValue)
                        .font(.title3).bold()
                        .foregroundStyle(section == s ? Color.white : .secondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .background {
                            if section == s { Capsule().fill(Color.accentColor) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)   // 整条胶囊水平居中
    }
}

/// 易经类主页：默认进「易经速查」，右上角 ⋯ 菜单切换易经类各子术数。
/// 用 switch 选择页面——切走再切回「梅花易数」时会重建视图、@State 自动归零。
struct IChingHomeView: View {
    enum Page: String, CaseIterable {
        case iching  = "易经速查"
        case time    = "梅花易数"
    }

    @State private var page: Page = .iching

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .iching:  ContentView()
                case .time:    TimeDivinationView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(Page.allCases, id: \.self) { p in
                            Button(p.rawValue) { page = p }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

#if os(macOS)
/// 禁用窗口状态恢复，并在启动时把窗口设回默认大小（之后用户仍可自由缩放）。
private struct WindowConfigurator: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        // 进了窗口的那一刻才设置（见 WindowReader：原来的 async 写法在 Release 版常常拿不到窗口）
        WindowReader { window in
            window.isRestorable = false                                  // 不保存/恢复窗口状态
            window.setContentSize(NSSize(width: width, height: height))  // 每次启动设回默认大小
            window.center()
            CasebookWindowManager.shared.registerMain(window)            // 供笔记窗跟随
        }
    }
}
#endif
