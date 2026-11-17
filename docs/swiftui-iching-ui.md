# SwiftUI 界面笔记：易经速查 + 变卦模式

记录这次前端大改用到的 SwiftUI 写法与思路，供复习。对应代码主要在
`ContentView.swift`（界面）和 `IChingStore.swift`（状态）。

---

## 1. 组件树（谁套谁）

界面是用一堆 View（struct）像积木一样嵌套出来的：

```
ContentView（根）
├── Toggle「变卦模式」（右上角）
├── 关：HexagramPanelView(本卦, 完整版)
└── 开：HStack{ HexagramPanelView(本卦) ; HexagramPanelView(变卦) }  紧凑版
      + 崔氏易林文本
      + HStack{ DerivedRow(本卦) ; DerivedRow(变卦) }   错综互

HexagramPanelView（一个卦的面板，可复用）
├── 卦名（紧凑版点它弹 HexagramDetailView 浮窗）
├── 六爻：ForEach → LineView（点=变爻）(+ 动爻→箭头 / 完整版的爻辞)
└── 完整版才有：用九用六、卦辞、DerivedRow

DerivedRow → ForEach → DerivedHexagramCell → MiniHexagram → MiniLine
                                   └── 点自己弹 DerivedDetailView
```

**核心思想：复用。** `HexagramPanelView` 一块积木，喂不同数据（本卦/变卦）+ 不同
回调，就长成两个独立面板。更小的 `LineView / MiniLine / MiniHexagram` 再被反复组合。

---

## 2. 状态怎么驱动界面（最关键）

```swift
@Observable                        // 标在 store 类上：它的属性一变，用到的界面自动重画
final class IChingStore { … }

struct ContentView: View {
    @State private var store = IChingStore()   // @State 持有这个可观察对象
}
```

- **`@Observable`（放在 store 类）**：让这个类的属性可被 SwiftUI 观察。
- **`@State`（放在视图里持有 store）**：视图拥有它；store 内属性变化 → body 重算。
- 界面**只读** store 的数据来显示，用户操作就调 store 的方法。界面不算业务、不碰
  Python——这叫 **view-model 模式**（界面薄、逻辑集中）。

---

## 3. 可复用、可配置的视图（参数 + 回调）

```swift
struct HexagramPanelView: View {
    let hex: Hexagram                 // 显示哪个卦
    var compact: Bool = false         // 带默认值的参数 = 可选配置
    var changingLines: Set<Int> = []  // 动爻下标
    var showArrow: Bool = false
    let onFlip: (Int) -> Void         // 回调：点了第几爻，交给外面处理
}
```

- **带默认值的属性**（`var x = 默认`）= 调用时可省略的"可选参数"。
- **`onFlip: (Int) -> Void`** 是个**闭包参数**：面板不自己决定"变爻怎么做"，而是
  把"第几爻被点了"**回调**出去。本卦传 `store.flipOriginal`、变卦传 `store.flipChanged`，
  **同一块面板，两种行为**。这是复用的关键。

调用：
```swift
HexagramPanelView(hex: org, compact: true, showArrow: true,
                  onFlip: { store.flipOriginal(line: $0) })   // $0 = 回调传回的爻位
```

---

## 4. 条件渲染：一套界面，多种形态

SwiftUI 里可直接用 `if / else` 选择显示什么：

```swift
if let org = store.original {            // 有本卦才画
    if store.showChanged, let chg = store.changed {
        … 双卦并排 + 易林 + 错综互 …
    } else {
        … 只画本卦完整面板 …
    }
} else if let msg = store.errorMessage {
    Text("出错了：\(msg)")
} else {
    ProgressView()                       // 加载中转圈
}
```

`if let` 同时做了"判空 + 取值"：有值才进分支并拿到非空的 `org`。

---

## 5. 常用零件速记

| 写法 | 作用 |
|---|---|
| `HStack { Spacer(); Toggle(...) }` | 用 `Spacer()` 把 Toggle 顶到**右上角** |
| `Toggle("变卦模式", isOn: $store.showChanged)` | 开关，`$` 是**双向绑定**（可读可写） |
| `ScrollView { VStack { … } }` | 内容多时可滚动，防止窗口小被截断 |
| `.frame(height: 44)` 固定行高 | 让每行高度恒定，**排版不随内容长短跳动** |
| `ForEach((0..<n).reversed())` | 倒序遍历：让 `lines[0]`(初爻) 排在**最下** |
| `.contentShape(Rectangle())` | 让整块（含空白）都能点 |

---

## 6. 浮窗（popover）的两种挂法

**A. 每项自管（`isPresented` + 子视图各自的 `@State`）** —— 用于错综互小卡片：
```swift
struct DerivedHexagramCell: View {
    @State private var showing = false          // 每个 cell 自己的开关
    var body: some View {
        … .onTapGesture { showing = true }
          .popover(isPresented: $showing) { DerivedDetailView(derived: derived) }
    }
}
```
> 把"一项"抽成独立子视图、让它持有自己的 `@State`，三个卡片就各弹各的、互不干扰。
> （若用一个共享绑定挂在三个上，会同时触发——这是个坑。）

**B. 直接挂在卦名上** —— 变卦模式点卦名看详情：
```swift
Text(hex.name)
    .onTapGesture { if compact { showDetail = true } }
    .popover(isPresented: $showDetail) { HexagramDetailView(hex: hex) }
```

---

## 7. 动爻箭头 & 爻题（小而有用的细节）

- **动爻** = 本卦与变卦**不同**的那几爻，在 store 里用集合算出：
  ```swift
  var changingLines: Set<Int> {
      // 比较两卦 lines，收集不同的下标
  }
  ```
  面板里 `if changingLines.contains(index) { 显示 "→" }`，只画在本卦侧、只用 `→`。
- **爻题**（初九/六二/上九…）用一个纯函数拼：初/上位置在前，中间四爻阴阳在前，
  阳=九、阴=六。见 `yaoTitle(index:isYang:)`。

---

## 8. 一次点击的完整数据流（把各层串起来）

```
点变卦面板第3爻
 → HexagramPanelView 的 onTapGesture 调 onFlip(3)
 → 外面传进来的 store.flipChanged(line: 3)
 → store 发 {"cmd":"flip",…} 给 engine → C桥 → Python → 返回 JSON
 → store 用 Hexagram 解码，更新 self.changed，并 recomputeYilin()
 → @Observable 触发 → ContentView 自动重画新卦 + 新易林
```

**一句话**：界面点击 → 回调到 store 方法 → store 调后端拿数据、更新自己的属性 →
`@Observable` 让界面自动刷新。你只需维护"状态"和"怎么显示状态"，不用手动刷界面。

---

## 9. 坑：`LazyVGrid` 里别用「数量会变的 `ForEach(0..<n)`」——翻月会错位

> 实战记录。出在一个「月历视图」上：按公历月铺一张日历网格，可以翻到上/下个月。

**现象**：月历首次打开那个月是对的，**翻到别的月份后月初就错位**（1 号落错列、前几天挤在一起），而且每个月错的样子还不一样；但从第二周往后又是对的。

**踩坑的写法**：月初要按"1 号是星期几"留几个空格，当时这么写——
```swift
LazyVGrid(columns: cols, spacing: 4) {
    ForEach(0..<leadingBlanks(month), id: \.self) { _ in   // ← 空格数会随月份变
        Color.clear.frame(height: 62)
    }
    ForEach(month.days) { day in DayCellView(day: day) … }
}
```
**原因**：`ForEach(0..<n)` 这种"整数区间"形式是给**固定数量**用的。`n`（前导空格数）
随翻月变化时，`LazyVGrid` 不会可靠地重算这段空格 → 空格数停留在旧值 → 后面所有日期
整体移位，月初就对不上星期列。加不加 `id: \.self` 都不保险。

**修法**：别单独用一个"动态数量的 ForEach"画空格。把**空格 + 各天合并成一个数组**，
每个格子带**稳定的"位置 id"**，用**一个** `ForEach` 画完：
```swift
private struct GridSlot: Identifiable {
    let id: Int               // 格子在网格中的位置（稳定）
    let day: DayData?         // nil = 月初前导空格
}
private func gridSlots(_ m: MonthData) -> [GridSlot] {
    let lead = m.days.first?.weekday ?? 0          // 1 号星期 = 前面留几个空格
    var slots = (0..<lead).map { GridSlot(id: $0, day: nil) }
    for (offset, day) in m.days.enumerated() {
        slots.append(GridSlot(id: lead + offset, day: day))
    }
    return slots
}
// body:
ForEach(gridSlots(month)) { slot in
    if let day = slot.day { DayCellView(day: day) … } else { Color.clear.frame(height: 62) }
}
```
翻到任何月份，数组整体换新、每个格子按位置 id 稳定更新，不再错位。

**通用教训**：`ForEach(0..<n)` 只配**常量** `n`。数量会变时，一律改成「**遍历一个带稳定
`id` 的数组**」。这和第 6 节"每项自管 `@State`"是同一类问题——**身份（identity）要稳定**，
SwiftUI 才能正确 diff。

**怎么定位的（排查方法也值得记）**：按"数据 → 静态渲染 → 更新"三段切开，逐段证伪：
1. 在 App 真实运行环境用 `RunCodeSnippet` 跑嵌入式 Python，确认**后端数据是对的**（星期没算错）；
2. 用 `#Preview` 喂正确数据给那个网格视图，确认**静态渲染是对的**；
3. 剩下只有"翻月更新"这一段 → 锁定到动态 `ForEach`。
数据对、静态对、只在交互后错 → 几乎都是 **SwiftUI 的 identity/更新** 问题。

---

## 10. 八字数据流（谁调谁）

八字对应 `BaziView.swift`（输入页）、`BaziChartView.swift`（结果页）、`BaziChart.swift`（解码模型）。
整条链和易经一样，界面从不直接碰 Python，都经过 `DivinationClient`。

**谁调后端** —— 八字有两处会请求后端，都走同一条「下水道」：

```
① 点「开始排盘」
BaziView.paipan() → client.baziChart(...)          // cmd: bazi_chart
② 点某个流年
BaziChartView.loadLiuyue(年) → client.baziLiuyue(...) // cmd: liuyue

两者之后都是：
DivinationClient.send(拼JSON) → engine.dispatch → py_dispatch(C桥)
    → Python divination.api.handle 按 cmd 分发 → bazi 服务
```

**谁调结果页** —— `BaziView` 用 `navigationDestination` 把 `BaziChartView` **推成新页面**：

```
paipan() 拿到 chart → showChart = true
  → .navigationDestination(isPresented: $showChart) { BaziChartView(...) }
```

**整体导航**（底部大类切换，与易经类并列）：

```
MainView（底部胶囊栏：易经 / 八字）
├─ 易经 → IChingHomeView（内部再用右上角 ⋯ 切 易经速查/时间起卦）
└─ 八字 → BaziView（输入） ──排盘──▶ BaziChartView（结果：流月|流年|大运 ┊ 四柱）
```

**一个复用点**：四柱/大运/流年/流月的干支上色，统一用 `WuXing.swift` 里的
`GanZhiChar`（按单字五行取色）——八字、时间起卦共用同一套配色，不各写各的。
