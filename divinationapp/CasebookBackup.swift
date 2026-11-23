#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 数据备份 / 恢复（菜单栏「文件」里的两项）。
///
/// - 备份：选个位置，把整个案例库（数据库 + 笔记里的图片）存成一个 .zip 文件（后端 casebook/backup.py）。
/// - 恢复：选一个备份文件 → 先给用户看里面有几篇笔记、什么时候备份的 → 确认后替换全部数据。
///   替换前后端会把当前数据自动备份一份（在数据库旁边，「…恢复前自动备份.zip」），万一选错了还能找回来。
/// - 有笔记正在编辑时不让恢复：编辑器离开时会清理「它那篇笔记」，恢复后同一个编号可能已经是别的笔记了。
@MainActor
enum CasebookBackup {
    /// 正在打开的笔记编辑器有几个（NoteEditorView 出现 / 离开时加减）。
    static var openEditors = 0

    /// 恢复完成：笔记列表等收到后重新取数据。
    static let restoredNotification = Notification.Name("casebookRestored")

    private static let client = DivinationClient()

    // MARK: - 备份

    static func backup() {
        let panel = NSSavePanel()
        panel.title = "备份数据"
        panel.nameFieldStringValue = "案例库备份 \(Self.today()).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let (res, err): (BackupResult?, String?) = client.callWithError("casebook_backup", ["path": url.path])
        guard let r = res else { alert("备份失败", err ?? "未知错误", style: .warning); return }
        alert("备份完成",
              "已备份 \(r.notes) 篇笔记、\(r.attachments) 张图片（\(ByteCountFormatter.string(fromByteCount: Int64(r.size), countStyle: .file))）。\n\n\(url.path)")
    }

    // MARK: - 恢复

    static func restore() {
        guard openEditors == 0 else {
            alert("请先保存并关闭正在编辑的笔记", "恢复会替换全部数据，有笔记正在编辑时不能恢复。", style: .warning); return
        }
        let panel = NSOpenPanel()
        panel.title = "选择要恢复的备份文件"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let (infoRes, infoErr): (BackupInfo?, String?) = client.callWithError("casebook_backup_inspect", ["path": url.path])
        guard let info = infoRes else { alert("无法恢复", infoErr ?? "未知错误", style: .warning); return }
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "用这个备份替换现在的全部数据？"
        confirm.informativeText = """
            备份时间：\(info.createdAt.map { $0.replacingOccurrences(of: "T", with: " ") } ?? "未知")
            备份里有 \(info.notes ?? 0) 篇笔记、\(info.attachments ?? 0) 张图片。

            现在的数据会先自动备份一份（放在数据库旁边，名字是「…恢复前自动备份.zip」），然后被替换。
            """
        confirm.addButton(withTitle: "恢复")
        confirm.addButton(withTitle: "取消")
        confirm.buttons.first?.hasDestructiveAction = true
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let (res, err): (RestoreResult?, String?) = client.callWithError("casebook_restore", ["path": url.path])
        guard let r = res else { alert("恢复失败", (err ?? "未知错误") + "\n\n现在的数据没有被改动。", style: .warning); return }
        NotificationCenter.default.post(name: restoredNotification, object: nil)
        alert("恢复完成", "已恢复 \(r.notes ?? 0) 篇笔记。\n\n恢复前的数据已自动备份到：\n\(r.safetyBackup ?? "")")
    }

    // MARK: - 小工具

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.alertStyle = style
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private struct BackupResult: Decodable { let notes: Int; let attachments: Int; let size: Int }
    private struct BackupInfo: Decodable { let createdAt: String?; let notes: Int?; let attachments: Int? }
    private struct RestoreResult: Decodable { let notes: Int?; let safetyBackup: String? }
}

/// 菜单栏「文件」里加「备份数据…」「恢复数据…」。
struct CasebookBackupCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("备份数据…") { CasebookBackup.backup() }
            Button("恢复数据…") { CasebookBackup.restore() }
        }
    }
}
#endif
