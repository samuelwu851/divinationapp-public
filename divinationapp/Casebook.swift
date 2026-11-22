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
/// - `subjects` 为该笔记关联的案主（多对多）。
struct Note: Codable, Identifiable {
    let id: Int
    let title: String
    var body: String?
    var preview: String?
    let createdAt: String
    let updatedAt: String
    var subjects: [Subject]?
    var labels: [String]?        // 右上角「算什么事」标签。后端暂未返回 → nil，位置先预留。
}

/// note_list 的外层：{ "notes": [...] }。
struct NoteListResult: Codable {
    let notes: [Note]
}

/// subject_search 的外层：{ "subjects": [...] }。
struct SubjectSearchResult: Codable {
    let subjects: [Subject]
}

/// 通用 {"ok": true} 响应（casebook_open / note_delete）。
struct OkResult: Codable {
    let ok: Bool
}
