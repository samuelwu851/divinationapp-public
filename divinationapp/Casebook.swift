import Foundation

/// 案主（可挂多个笔记；一个笔记也可挂多个案主）。
/// - subject_search 返回 {id,name,remark}；subject_create 返回更全，这里只取要用的。
/// - note 里的 subjects 只有 {id,name}（remark 为空）。
struct Subject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var remark: String?
    var noteCount: Int? = nil   // 只有 subject_list 返回：关联了多少笔记
}

/// 案主详情（subject_get）：案主本身 + 和他关联的所有笔记。
/// 生日 "YYYY-MM-DD"、时间 "HH:MM"、性别 1 男 / 0 女，没填都是 nil。
struct SubjectDetail: Codable {
    let id: Int
    let name: String
    let remark: String
    var birthday: String?
    var birthtime: String?
    var gender: Int?
    let notes: [Note]
}

/// 术数（笔记用了哪些术数）：code 存数据库，name 显示。能插排盘的术数 code 同排盘类型。
struct Shushu: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    var tone: String? = nil     // 色系（后端给）：yi / ren / qimen / red / ziwei / earth / plain，见 ShushuChip
    var id: String { code }
}

/// shushu_list 的外层：{ "shushu": [...] }（note_shushu_add/remove 也返回这个格式）。
struct ShushuListResult: Codable {
    let shushu: [Shushu]
}

/// 笔记列表的筛选条件（都可省）。所有条件同时满足才出现——同一类选了多个（如两个标签），也要都有。
struct NoteFilter: Equatable {
    var keyword = ""
    var labels: [NoteLabel] = []
    var subjects: [Subject] = []
    var shushu: [Shushu] = []
    /// 按排盘搜的条件块（新加的在最前面）；每一块要由笔记里**不同的**排盘满足（见 ChartSearchPanel）
    var chartBlocks: [ChartQueryBlock] = []

    var isEmpty: Bool {
        keyword.trimmingCharacters(in: .whitespaces).isEmpty && labels.isEmpty && subjects.isEmpty && shushu.isEmpty
            && chartBlocks.isEmpty
    }
}

/// 一个排盘条件块：某种术数 + 选了哪些值（没选的字段 = 不限；一个字段都没选 = 有这种排盘就行）。
struct ChartQueryBlock: Identifiable, Equatable {
    let id = UUID()
    let type: String
    var fields: [String: String] = [:]
}

/// 按排盘搜索的面板（后端 chart_search_forms 给）：每种术数一组下拉框。
struct ChartSearchForm: Codable, Identifiable {
    struct Option: Codable, Hashable { let value: String; let label: String }
    struct Field: Codable, Identifiable {
        let key: String
        let label: String
        var style: String? = nil          // "menu" 下拉框 / "checks" 互斥勾选框（男 / 女、有变卦 / 没变卦）/ "number" 填整数（如年份）
        let options: [Option]
        var min: Int? = nil               // number 字段的范围（可没有）
        var max: Int? = nil
        var group: String? = nil          // 分组小标题（如「公历」「农历」）：相邻的同组字段排在一起，组上面显示小标题
        var id: String { key }
        var isChecks: Bool { style == "checks" }
        var isNumber: Bool { style == "number" }
    }
    let type: String
    let title: String
    let columns: Int
    let fields: [Field]
    var id: String { type }
}

struct ChartSearchFormsResult: Codable {
    let forms: [ChartSearchForm]
}

/// 一条笔记。
/// - note_get 返回含 `body`（完整正文，markdown）；note_list 返回含 `preview`（正文前 40 字）。
/// - `subjects` 为该笔记关联的案主（多对多）；`labels` 为「算什么事」标签（多对多）。
struct Note: Codable, Identifiable {
    let id: Int
    let title: String
    var body: String?
    var preview: String?
    let createdAt: String
    let updatedAt: String
    var subjects: [Subject]?
    var labels: [NoteLabel]?     // 列表右上角显示
    var shushu: [Shushu]?        // 用了哪些术数
    var deletedAt: String?       // 放进回收站的时间（只有回收站列表有）
}

/// 标签（「算什么事」，如疾病、感情）：笔记和排盘共用一份清单，名字唯一。
/// 不叫 Label，避免和 SwiftUI 的 Label 视图重名。
struct NoteLabel: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var uses: Int? = nil        // 只有 label_search 返回：有多少笔记 + 排盘在用（删除前提示用）
}

/// label_search 的外层：{ "labels": [...] }。
struct LabelSearchResult: Codable {
    let labels: [NoteLabel]
}

/// note_list 的外层：{ "notes": [...] }。
struct NoteListResult: Codable {
    let notes: [Note]
}

/// subject_search 的外层：{ "subjects": [...] }。
struct SubjectSearchResult: Codable {
    let subjects: [Subject]
}

/// 通用 {"ok": true} 响应（note_delete）。
struct OkResult: Codable {
    let ok: Bool
}

/// casebook_open 的响应：{"ok": true, "attachments_dir": "..."}。
struct CasebookOpenResult: Codable {
    let ok: Bool
    let attachmentsDir: String?
}

/// chart_create 的响应里只取 id。
struct ChartRef: Codable {
    let id: Int
}

/// 案例库的路径：App 启动打开数据库后填入，编辑器读图片时用。
enum CasebookPaths {
    static var attachmentsDir: URL?
}
