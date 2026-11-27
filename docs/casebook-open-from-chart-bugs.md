# 笔记：从排盘页「存进案例库」打开笔记窗口的两个 bug

记录 2026-11 修的两个问题、原因和改法，供复习。对应代码在
`NotesWindowView.swift`（笔记窗口）、`NoteEditorView.swift`（编辑器）、
`CasebookWindowManager.swift`（贴合 / 磁吸）、`WindowReader`（拿到 SwiftUI 视图所在的 NSWindow）。

---

## 0. 背景：「存进案例库」是怎么走的

```
排盘页点笔（SaveChartButton）
  → CasebookOpener.shared.pending = 这张盘
  → openWindow(id: "notes")                       打开笔记窗口
笔记窗口 NotesWindowView
  → .onAppear / .onChange(pending) 调 openPending()
  → path = [.editor(.newWithChart(spec))]         直接推进编辑器
编辑器 NoteEditorView
  → 新建笔记 + 排盘，正文里放好卡片
```

平时点右下角笔记本图标打开笔记窗口，**先显示的是笔记列表页**；
从排盘页存进来时，**窗口一打开就立刻推进编辑器**。两个 bug 都出在这个「一上来就推进」上。

---

## 1. 问题一：笔记窗口没贴在主窗口旁边，也吸不上去

**现象**：从排盘页存进案例库，打开的笔记窗口位置随便，拖到主窗口边上也不会被磁吸。
从笔记本图标打开就正常。

**原因**：笔记窗口要先「报到」给 `CasebookWindowManager`（`registerNotes`），
管理器才会把它贴到主窗口右边、监听它的拖动做磁吸。报到是靠一个小视图
`NotesWindowAccessor`（里面是 `WindowReader`）在**放进窗口的那一刻**回调完成的。

原来这个小视图挂在**列表页**上：

```swift
NavigationStack(path: $path) {
    VStack { 列表… }
        .background(NotesWindowAccessor())   // ← 挂在列表页
}
```

一上来就推进编辑器时，列表页可能根本没被放进窗口 → `viewDidMoveToWindow` 不触发 →
没报到 → 不贴合、不磁吸。

**改法**：挂到 `NavigationStack` 外面。不管栈里先显示哪一页，它都在窗口里，一定会报到。

```swift
NavigationStack(path: $path) { … }
    .background(NotesWindowAccessor())       // ← 挂在外面
```

**要记住的点**：用「视图进了窗口」来做初始化的东西（`WindowReader` 这类），要挂在
**一定会显示**的位置，不要挂在导航栈里可能被跳过的某一页上。

---

## 2. 问题二：存进来的那篇笔记里，「插入排盘」一直说光标不在正文

**现象**：从排盘页存进来的笔记，在正文里点了光标再点「插入排盘」，还是提示
「在正文里点一下，把光标放到要插入排盘的地方」。普通新建的笔记没问题。

**原因（推测，按代码推出来的）**：窗口刚打开、列表页**还在第一次出现的过程中**就改了 `path`，
SwiftUI 会把编辑器「出现 → 消失 → 再出现」一遍。编辑器的 `.onDisappear` 是
`finish()`——当成离开编辑器处理：

- `editor.tearDown()`：把 Swift 和网页编辑器之间的连接拆掉（`webView = nil`，`ready = false`）；
- 新建且没保存的笔记还会被 `noteDelete` 删掉。

之后编辑器再出现，但 `loaded` 已经是 true，不会重新 `load()`；网页还显示着，
Swift 这边却连不上它了。`cursorInBody()` 第一句 `guard let webView, ready else { return false }`
永远返回 false → 一直提示「光标不在正文」。（保存也会出问题：取不到正文，笔记也已被删。）

**改法**：推进编辑器这一步推到下一轮主循环，等列表页安稳出现以后再改 `path`：

```swift
private func openPending() {
    guard let spec = CasebookOpener.shared.pending else { return }
    CasebookOpener.shared.pending = nil
    DispatchQueue.main.async { path = [.editor(.newWithChart(spec))] }   // ← 推到下一轮
}
```

**要记住的点**：

- 不要在视图**第一次出现的同一轮**里改导航 `path`，SwiftUI 可能会把推进去的页面多建、多拆一次。
- `.onDisappear` 不一定代表「用户真的离开了」。在里面做删除、断开连接这类**不可逆**的事要小心。

---

## 3. 顺带：为什么「页面切换不丢排盘」不能把几个页面都藏着留着

同一时期还踩过一个相关的坑：为了让底部切换易经 / 八字 / 六壬时不丢排盘，
一开始把三个页面都放在 `ZStack` 里，只用 `opacity` 藏起来。结果六壬进了结果页、
八字也进了结果页以后崩溃（`NSApplication _crashOnException`）：
同一个窗口里**几套 NavigationStack 同时往窗口工具栏 / 标题加东西**，macOS 处理不了。

改成：页面照常用 `switch` 切换（切走就销毁，同一时间只有一套导航），
页面里的内容挪到页面外面的 `PageStates`（`PageStates.swift`）里，由 `MainView` 持有；
切回来时用这些内容重建页面。

**要记住的点**：要「保留状态」，就把**状态**存起来，不要把**整个视图**留着。
