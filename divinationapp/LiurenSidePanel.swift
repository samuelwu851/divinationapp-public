import SwiftUI

/// 六壬课式页左栏：显示哪些项、按什么顺序，由用户自己定（存在本机 UserDefaults）。
///
/// 每一项用一个键表示：
/// - 基本项 `base:月将` / `base:旬空` / `base:旬首` / `base:旬丁` / `base:旬尾`（默认就是这五项）；
/// - 神煞 `sha:岁煞:驿马`（类别 + 名字；同名神煞在不同类别里是不同的项，比如岁煞驿马、日支煞驿马）。
/// 顺序就是添加的先后，设置里可以删、可以拖动调整。
enum LiurenSideItems {
    static let storageKey = "liurenSidePanelItems"
    static let base = ["月将", "旬空", "旬首", "旬丁", "旬尾"]
    static let defaultKeys = base.map { "base:" + $0 }

    static func decode(_ s: String) -> [String] {
        s.isEmpty ? defaultKeys : s.split(separator: "|").map(String.init)
    }
    static func encode(_ keys: [String]) -> String {
        keys.isEmpty ? "none" : keys.joined(separator: "|")      // 全删光也要和「没设置过」区分开
    }

    static func shaKey(_ s: LiurenResult.Sha) -> String { "sha:\(s.category):\(s.name)" }

    /// 显示名：基本项直接用名字；神煞用名字，同名的在后面括注类别（如「驿马（岁）」）。
    static func label(_ key: String, all: [LiurenResult.Sha]) -> String {
        let parts = key.split(separator: ":").map(String.init)
        guard parts.first == "sha", parts.count == 3 else { return parts.last ?? key }
        let (cat, name) = (parts[1], parts[2])
        let dup = all.filter { $0.name == name }.count > 1
        return dup ? "\(name)（\(cat.prefix(cat.count - 1))）" : name
    }
}

/// 课式页的设置（齿轮点进来）：一级列表，以后别的设置也往这里加。
struct LiurenChartSettings: View {
    let all: [LiurenResult.Sha]
    /// 案例库里打开的课不显示「涉害取法」「贵人起法」：存进去的课按当时的取法定死，不会跟着设置重排。
    var showsMethod = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiurenScript.key) private var traditional = true
    @AppStorage(LiurenInput.methodKey) private var method = LiurenInput.defaultMethod   // 和起课页是同一个值
    @AppStorage(LiurenInput.guirenKey) private var guiren = LiurenInput.defaultGuiren

    var body: some View {
        NavigationStack {
            List {
                Picker("字体", selection: $traditional) {
                    Text("繁体").tag(true)
                    Text("简体").tag(false)
                }
                .pickerStyle(.segmented)
                if showsMethod {
                    Picker("涉害取法", selection: $method) {
                        Text("孟仲季法").tag("mzj")
                        Text("深浅法").tag("depth")
                    }
                    .pickerStyle(.segmented)
                    .help("改了以后，正在看的课马上按新取法重排；以后起课也默认用它（已存进案例库的课不变）")
                    Picker("贵人起法", selection: $guiren) {
                        Text("甲戊庚牛羊").tag("std")
                        Text("甲(戊)庚牛羊").tag("alt")
                    }
                    .pickerStyle(.segmented)
                    .help("甲(戊)庚牛羊：庚己丁癸昼夜贵人对调。改了以后正在看的课马上重排（已存进案例库的课不变）")
                }
                NavigationLink("左栏显示的神煞") {
                    LiurenSideItemsSettings(all: all)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 540)
    }
}

/// 设置面板：上面是已选的项（可删、可拖动排序），下面按类别列出还没选的神煞，点一下就加到最后。
struct LiurenSideItemsSettings: View {
    @AppStorage(LiurenSideItems.storageKey) private var stored = ""
    @AppStorage(LiurenScript.key) private var traditional = true
    private func tc(_ s: String) -> String { traditional ? LiurenScript.trad(s) : s }
    let all: [LiurenResult.Sha]
    private var keys: [String] {
        get { stored == "none" ? [] : LiurenSideItems.decode(stored) }
    }
    private func save(_ k: [String]) { stored = LiurenSideItems.encode(k) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("已选（拖动调整顺序）") {
                    if keys.isEmpty {
                        Text("还没有选任何项").foregroundStyle(.secondary)
                    }
                    ForEach(keys, id: \.self) { k in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Text(tc(LiurenSideItems.label(k, all: all)))
                            Spacer()
                            Button { save(keys.filter { $0 != k }) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("删掉")
                        }
                    }
                    .onMove { from, to in
                        var k = keys
                        k.move(fromOffsets: from, toOffset: to)
                        save(k)
                    }
                }

                let baseLeft = LiurenSideItems.base.filter { !keys.contains("base:" + $0) }
                if !baseLeft.isEmpty {
                    Section("基本") {
                        ForEach(baseLeft, id: \.self) { b in addRow(tc(b), key: "base:" + b) }
                    }
                }
                ForEach(categories, id: \.self) { cat in
                    let left = all.filter { $0.category == cat && !keys.contains(LiurenSideItems.shaKey($0)) }
                    if !left.isEmpty {
                        Section(tc(cat)) {
                            ForEach(left, id: \.name) { s in addRow(tc(s.name), key: LiurenSideItems.shaKey(s)) }
                        }
                    }
                }
            }
        }
        .navigationTitle("左栏显示的神煞")
        .toolbar {
            ToolbarItem { Button("恢复默认") { stored = "" } }
        }
    }

    /// 类别按后端给的顺序。
    private var categories: [String] {
        var seen: [String] = []
        for s in all where !seen.contains(s.category) { seen.append(s.category) }
        return seen
    }

    private func addRow(_ title: String, key: String) -> some View {
        Button { save(keys + [key]) } label: {
            HStack {
                Image(systemName: "plus.circle").foregroundStyle(.green)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
