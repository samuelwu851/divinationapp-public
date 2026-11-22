import Foundation

/// 案主（可挂多个笔记；一个笔记也可挂多个案主）。
/// - subject_search 返回 {id,name,remark}；subject_create 返回更全，这里只取要用的。
/// - note 里的 subjects 只有 {id,name}（remark 为空）。
struct Subject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var remark: String?
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
