import Foundation

/// 梅花排盘结果（对应后端 meihua 命令的 JSON）。
struct MeihuaResult: Codable {
    struct Gua: Codable { let value: Int; let name: String }
    let benGua: Gua       // ben_gua
    let movingLine: Int   // moving_line，动爻 1-6
    let bianGua: Gua      // bian_gua
}

/// 八字排盘结果（对应后端 bazi 命令的 JSON，只取要显示的字段）。
struct BaziResult: Codable {
    let inputTime: String   // input_time，公历
    let lunar: String       // 农历
    let year: String        // 四柱：年柱
    let month: String       // 月柱
    let day: String         // 日柱
    let hour: String        // 时柱
}

/// 公历→农历 结果（对应后端 solar_to_lunar）。
struct SolarToLunarResult: Codable {
    let lunarYear: Int      // lunar_year
    let lunarMonth: Int     // lunar_month(1-12)
    let isLeap: Bool        // is_leap
    let lunarDay: Int       // lunar_day
}

/// 一个农历月（对应后端 lunar_months 的每一项）。
struct LunarMonth: Codable, Identifiable {
    let month: Int          // 1-12
    let isLeap: Bool        // is_leap
    let days: Int           // 该月天数(29/30)
    let label: String       // "正月"/"闰冬月"…
    var id: String { label }  // 同一年内 label 唯一
}

/// 某农历年的月份结构（对应后端 lunar_months）。
struct LunarMonthsResult: Codable {
    let year: Int
    let months: [LunarMonth]
}

/// 无状态小帮手：包一下 engine + JSON 解码。不持有状态、不是 store。
/// 梅花易数用它一次性取数据，结果存进视图自己的 @State。
struct DivinationClient {
    private let engine: DivinationEngine = PythonEngine()

    func lookup(_ value: Int) -> Hexagram? {
        decode(send(["cmd": "lookup", "value": value]))
    }

    func meihua(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> MeihuaResult? {
        decode(send(["cmd": "meihua", "year": year, "month": month,
                     "day": day, "hour": hour, "minute": minute]))
    }

    func bazi(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> BaziResult? {
        decode(send(["cmd": "bazi", "year": year, "month": month,
                     "day": day, "hour": hour, "minute": minute]))
    }

    /// 八字全盘：四柱(十神/藏干/纳音) + 大运（每步内嵌 10 流年）。
    func baziChart(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                   isMale: Bool) -> BaziChart? {
        decode(send(["cmd": "bazi_chart", "year": year, "month": month, "day": day,
                     "hour": hour, "minute": minute, "is_male": isMale]))
    }

    /// 某流年的 12 流月（相对命主日主的十神）。
    func baziLiuyue(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                    targetYear: Int) -> BaziLiuYueResult? {
        decode(send(["cmd": "liuyue", "year": year, "month": month, "day": day,
                     "hour": hour, "minute": minute, "target_year": targetYear]))
    }

    /// 参卦：本卦 → 变卦时，变了的三爻卦起的参卦（没有动爻 → 空）。
    func cangua(org: Int, chg: Int) -> [CanGuaGroup] {
        let r: CanGuaResult? = decode(send(["cmd": "cangua", "org_value": org, "chg_value": chg]))
        return r?.groups ?? []
    }

    func yilin(org: Int, chg: Int) -> String? {
        let r: YilinResult? = decode(send(["cmd": "yilin", "org_value": org, "chg_value": chg]))
        return r?.text
    }

    /// 公历 → 农历（定农历默认值）。
    func solarToLunar(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> SolarToLunarResult? {
        decode(send(["cmd": "solar_to_lunar", "year": year, "month": month, "day": day,
                     "hour": hour, "minute": minute]))
    }

    /// 某农历年的月份结构（含闰月、每月天数）。
    func lunarMonths(year: Int) -> [LunarMonth]? {
        let r: LunarMonthsResult? = decode(send(["cmd": "lunar_months", "year": year]))
        return r?.months
    }

    // MARK: - 案例库（笔记）

    /// 打开/初始化案例库数据库（建表、迁移）。App 启动时调用一次。
    /// 返回图片文件夹路径（编辑器显示图片用）；失败返回 nil。
    @discardableResult
    func casebookOpen(path: String) -> String? {
        let r: CasebookOpenResult? = decode(send(["cmd": "casebook_open", "path": path]))
        return r?.ok == true ? r?.attachmentsDir : nil
    }

    /// 所有笔记（按更新时间倒序，含正文预览）。
    func noteList() -> [Note] {
        let r: NoteListResult? = decode(send(["cmd": "note_list"]))
        return r?.notes ?? []
    }

    func noteGet(id: Int) -> Note? {
        decode(send(["cmd": "note_get", "note_id": id]))
    }

    @discardableResult
    func noteCreate(title: String, body: String, subjectIds: [Int] = []) -> Note? {
        decode(send(["cmd": "note_create", "title": title, "body": body, "subject_ids": subjectIds]))
    }

    /// 案主模糊搜索（写笔记时输入框下拉用）。
    func subjectSearch(keyword: String) -> [Subject] {
        let r: SubjectSearchResult? = decode(send(["cmd": "subject_search", "keyword": keyword]))
        return r?.subjects ?? []
    }

    /// 新建案主。
    @discardableResult
    func subjectCreate(name: String, remark: String = "") -> Subject? {
        decode(send(["cmd": "subject_create", "name": name, "remark": remark]))
    }

    /// 标签模糊搜索（空关键字 = 全部，常用的在前）。
    func labelSearch(keyword: String) -> [NoteLabel] {
        let r: LabelSearchResult? = decode(send(["cmd": "label_search", "keyword": keyword]))
        return r?.labels ?? []
    }

    /// 新建标签；同名已存在就返回已有的。
    func labelCreate(name: String) -> NoteLabel? {
        decode(send(["cmd": "label_create", "name": name]))
    }

    /// 彻底删除一个标签（所有笔记和排盘上的这个标签都会去掉）。
    @discardableResult
    func labelDelete(id: Int) -> Bool {
        let r: OkResult? = decode(send(["cmd": "label_delete", "label_id": id]))
        return r?.ok ?? false
    }

    @discardableResult
    func noteLabelAdd(noteId: Int, labelId: Int) -> Note? {
        decode(send(["cmd": "note_label_add", "note_id": noteId, "label_id": labelId]))
    }

    @discardableResult
    func noteLabelRemove(noteId: Int, labelId: Int) -> Note? {
        decode(send(["cmd": "note_label_remove", "note_id": noteId, "label_id": labelId]))
    }

    /// 给已有笔记添加一个案主（重复添加不报错），返回更新后的笔记。
    @discardableResult
    func noteSubjectAdd(noteId: Int, subjectId: Int) -> Note? {
        decode(send(["cmd": "note_subject_add", "note_id": noteId, "subject_id": subjectId]))
    }

    /// 从某笔记移除一个案主关联，返回更新后的笔记。
    @discardableResult
    func noteSubjectRemove(noteId: Int, subjectId: Int) -> Note? {
        decode(send(["cmd": "note_subject_remove", "note_id": noteId, "subject_id": subjectId]))
    }

    @discardableResult
    func noteUpdate(id: Int, title: String, body: String) -> Note? {
        decode(send(["cmd": "note_update", "note_id": id, "title": title, "body": body]))
    }

    @discardableResult
    func noteDelete(id: Int) -> Bool {
        let r: OkResult? = decode(send(["cmd": "note_delete", "note_id": id]))
        return r?.ok ?? false
    }

    /// 清理笔记里「已保存正文」没引用的排盘和图片（编辑器关闭时调用）。
    func noteCleanup(id: Int) {
        _ = send(["cmd": "note_cleanup", "note_id": id])
    }

    /// 按参数排盘并存进笔记（type: bazi / iching / meihua），返回排盘 id。
    func chartCreate(noteId: Int, type: String, params: [String: Any]) -> Int? {
        let r: ChartRef? = decode(send(["cmd": "chart_create", "note_id": noteId, "type": type, "params": params]))
        return r?.id
    }

    /// 取出一个已存的排盘（含快照），交给 ChartDetailView 解码。
    func chartGet(id: Int) -> Data? {
        guard let json = send(["cmd": "chart_get", "chart_id": id]) else { return nil }
        return Data(json.utf8)
    }

    /// 翻某一爻，返回新卦。
    func flip(value: Int, line: Int) -> Hexagram? {
        decode(send(["cmd": "flip", "value": value, "line": line]))
    }

    /// 原样转发一条命令，返回后端的 JSON 字符串（编辑器网页通过它调后端）。
    func dispatchRaw(cmd: String, params: [String: Any]) -> String? {
        var req = params
        req["cmd"] = cmd
        return send(req)
    }

    // MARK: - 私有：发请求 + 泛型解码

    private func send(_ request: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let req = String(data: data, encoding: .utf8) else { return nil }
        return engine.dispatch(req)
    }

    private func decode<T: Decodable>(_ json: String?) -> T? {
        guard let json else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(T.self, from: Data(json.utf8))
    }
}
