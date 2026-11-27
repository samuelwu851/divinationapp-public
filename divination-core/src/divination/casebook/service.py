"""案例库的业务与命令。"""
import base64
import json
import os
import uuid
from datetime import datetime

from divination.casebook import backup as backup_mod, body as body_mod, chart_facts, charts, db, repository as repo, shushu
from divination.ganzhi.repository import solar_moment
from datetime import datetime

def get_note(note_id: int) -> dict:
    note = repo.get_note(note_id)
    if note is None:
        raise LookupError(f"笔记不存在：{note_id}")
    note["subjects"] = repo.get_note_subjects(note_id)
    note["labels"] = repo.get_note_labels(note_id)
    note["shushu"] = shushu.sort_and_name(repo.get_note_types(note_id))
    return note


# 列出笔记（可按关键字 / 标签 / 案主 / 术数筛选，所有条件同时满足，见 repo.list_notes）
def list_notes(keyword: str = "", label_ids=(), subject_ids=(), shushu_codes=(), trashed: bool = False,
               chart_query: list | None = None) -> list[dict]:
    blocks = chart_facts.clean_query(chart_query)
    notes = repo.list_notes((keyword or "").strip(), label_ids or (), subject_ids or (), shushu_codes or (), trashed,
                            blocks)
    if len(blocks) > 1:
        notes = _match_chart_blocks(notes, blocks)
    by_note = {}
    for row in repo.get_all_note_subjects():
        by_note.setdefault(row["note_id"], []).append({"id": row["id"], "name": row["name"]})
    labels_by_note = {}
    for row in repo.get_all_note_labels():
        labels_by_note.setdefault(row["note_id"], []).append({"id": row["id"], "name": row["name"]})
    types_by_note = {}
    for row in repo.get_all_note_types():
        types_by_note.setdefault(row["note_id"], []).append(row["type"])
    for n in notes:
        n["subjects"] = by_note.get(n["id"], [])
        n["labels"] = labels_by_note.get(n["id"], [])
        n["shushu"] = shushu.sort_and_name(types_by_note.get(n["id"], []))
    return notes


def update_note(note_id: int, title: str, body: str) -> dict:
    if repo.update_note(note_id, title, body, body_mod.extract_text(body)) == 0:
        raise LookupError(f"笔记不存在：{note_id}")
    db.get().commit()
    return get_note(note_id)


def delete_note(note_id: int) -> None:
    # 数据库里的图片记录会随笔记级联删除，但磁盘上的文件要自己删
    filenames = repo.list_attachment_filenames(note_id)
    if repo.delete_note(note_id) == 0:
        raise LookupError(f"笔记不存在：{note_id}")
    db.get().commit()
    _remove_files(filenames)

# ---------- 排盘搜索 ----------

def _match_chart_blocks(notes: list[dict], blocks: list[dict]) -> list[dict]:
    """精筛：每个条件块要由笔记里**不同的**排盘满足（加了两个八字块 → 要有两张八字分别满足）。"""
    by_chart: dict[int, dict] = {}
    for r in repo.chart_facts_of_notes([n["id"] for n in notes], list({b["type"] for b in blocks})):
        c = by_chart.setdefault(r["chart_id"], {"id": r["chart_id"], "note_id": r["note_id"], "type": r["type"], "facts": {}})
        if r["key"] is not None:
            c["facts"].setdefault(r["key"], set()).add(r["value"])     # 同一键可能有多个值
    charts_by_note: dict[int, list[dict]] = {}
    for c in by_chart.values():
        charts_by_note.setdefault(c["note_id"], []).append(c)
    return [n for n in notes if chart_facts.match_distinct(blocks, charts_by_note.get(n["id"], []))]


def backfill_chart_facts() -> int:
    """给还没拆过、或者是旧版本拆的排盘重拆特征（老数据 / 新加了可搜索的术数或字段）。
    打开案例库时调用；返回重拆了几个。"""
    rows = []
    for t in chart_facts.REGISTRY:                       # 每种术数对照它自己的版本号
        rows += repo.charts_needing_facts([t], chart_facts.VERSION_KEY, chart_facts.version_for(t))
    with db.get():
        for r in rows:
            repo.delete_chart_facts(r["id"])
            repo.insert_chart_facts(r["id"], r["type"], chart_facts.extract(r["type"], json.loads(r["snapshot_json"])))
    return len(rows)


# ---------- 回收站：删除笔记先放进来，可以恢复；在回收站里再删才是彻底删除 ----------

def trash_note(note_id: int) -> None:
    with db.get():
        if repo.set_note_trashed(note_id, True) == 0:
            raise LookupError(f"笔记不存在：{note_id}")


def restore_note(note_id: int) -> None:
    with db.get():
        if repo.set_note_trashed(note_id, False) == 0:
            raise LookupError(f"笔记不存在：{note_id}")


def empty_trash() -> int:
    """清空回收站：里面的笔记全部彻底删除（连同排盘、图片文件）。返回删了几篇。"""
    ids = repo.list_trashed_note_ids()
    for nid in ids:
        delete_note(nid)
    return len(ids)


# 新建笔记
def create_note(title: str, body: str, subject_ids: list[int] = ()) -> dict:
    with db.get():
        note_id = repo.insert_note(title, body, body_mod.extract_text(body))
        repo.link_note_subjects(note_id, subject_ids)
    return get_note(note_id)


def cleanup_note(note_id: int) -> dict:
    """删掉这份笔记里「已保存的正文」没有引用的排盘和图片。编辑器关闭时调用。

    编辑过程中插入的排盘、图片会立刻存进数据库；如果用户随后删掉卡片，
    或者放弃修改，它们就成了没人引用的数据。等关闭时再清理，
    编辑过程中的撤销（⌘Z）就不会把卡片恢复成一张「坏卡」。
    """
    note = repo.get_note(note_id)
    if note is None:
        raise LookupError(f"笔记不存在：{note_id}")
    used_charts = body_mod.referenced_chart_ids(note["body"])
    used_files = body_mod.referenced_attachments(note["body"])

    removed_charts = [c for c in repo.list_chart_ids(note_id) if c not in used_charts]
    removed_files = [f for f in repo.list_attachment_filenames(note_id) if f not in used_files]
    with db.get():
        for cid in removed_charts:
            repo.delete_chart(cid)
        for f in removed_files:
            repo.delete_attachment(f)
    _remove_files(removed_files)
    return {"removed_charts": removed_charts, "removed_attachments": removed_files}


# ---------- 排盘 ----------

def _clean_question(text) -> str:
    """所问之事：去掉首尾空白、换行换成空格，最多 100 字。"""
    q = " ".join(str(text or "").split())
    if len(q) > 100:
        raise ValueError("所问之事太长（最多 100 字）")
    return q


def create_chart(note_id: int, chart_type: str, params: dict, question: str = "") -> dict:
    """按参数排盘并存进这份笔记，返回存好的排盘（含快照）。question = 所问之事（可不填），存在 title 里。"""
    if repo.get_note(note_id) is None:
        raise LookupError(f"笔记不存在：{note_id}")
    builder_title, snapshot = charts.build(chart_type, params)
    title = _clean_question(question) or builder_title
    with db.get():
        chart_id = repo.insert_chart(
            note_id, chart_type, title,
            _to_json(params), _to_json(snapshot), charts.ALGO_VERSION,
        )
        repo.insert_chart_facts(chart_id, chart_type, chart_facts.extract(chart_type, snapshot))   # 供按排盘搜索
    return get_chart(chart_id)


def get_chart(chart_id: int) -> dict:
    row = repo.get_chart(chart_id)
    if row is None:
        raise LookupError(f"排盘不存在：{chart_id}")
    return {
        "id": row["id"],
        "note_id": row["note_id"],
        "type": row["type"],
        "title": row["title"],
        "params": json.loads(row["params_json"]),
        "snapshot": json.loads(row["snapshot_json"]),
        "algo_version": row["algo_version"],
        "created_at": row["created_at"],
        "labels": repo.get_chart_labels(chart_id),
        "tags": repo.get_chart_tags(chart_id),        # 特点
    }


# ---------- 标签：笔记和排盘共用一份清单，名字唯一 ----------

def _clean_label_name(name: str) -> str:
    name = (name or "").strip()
    if not name:
        raise ValueError("标签名字不能为空")
    if len(name) > 20:
        raise ValueError("标签名字太长（最多 20 个字）")
    return name


def search_labels(keyword: str) -> list[dict]:
    return repo.search_labels(keyword.strip())


def list_labels() -> list[dict]:
    """全部标签（搜索筛选的下拉菜单用），常用的在前。"""
    return repo.search_labels("", limit=100000)


def create_label(name: str) -> dict:
    """新建标签；同名的已经存在就直接返回已有的（标签不允许重名）。"""
    name = _clean_label_name(name)
    with db.get():
        label_id = repo.get_or_create_label(name)
    return repo.get_label(label_id)


def delete_label(label_id: int) -> None:
    """彻底删除一个标签：所有笔记和排盘上的这个标签都会一起去掉。"""
    with db.get():
        if repo.delete_label(label_id) == 0:
            raise LookupError(f"标签不存在：{label_id}")


def add_note_label(note_id: int, label_id: int) -> dict:
    get_note(note_id)
    if repo.get_label(label_id) is None:
        raise LookupError(f"标签不存在：{label_id}")
    with db.get():
        repo.link_note_label(note_id, label_id)
    return get_note(note_id)


def remove_note_label(note_id: int, label_id: int) -> dict:
    with db.get():
        if repo.unlink_note_label(note_id, label_id) == 0:
            raise LookupError(f"笔记 {note_id} 没有标签 {label_id}")
    return get_note(note_id)


def add_chart_label(chart_id: int, name: str) -> list[dict]:
    """按名字给排盘贴标签（没有这个标签就顺便新建），返回排盘现在的全部标签。"""
    name = _clean_label_name(name)
    if repo.get_chart(chart_id) is None:
        raise LookupError(f"排盘不存在：{chart_id}")
    with db.get():
        repo.link_chart_label(chart_id, repo.get_or_create_label(name))
    return repo.get_chart_labels(chart_id)


def remove_chart_label(chart_id: int, label_id: int) -> list[dict]:
    with db.get():
        repo.unlink_chart_label(chart_id, label_id)
    return repo.get_chart_labels(chart_id)


# ---------- 图片 ----------

_IMAGE_EXTS = {"png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"}
MAX_IMAGE_BYTES = 30 * 1024 * 1024


def add_attachment(note_id: int, data_base64: str, original_name: str = "",
                   width: int | None = None, height: int | None = None) -> dict:
    """把图片复制进 App 自己的文件夹，返回程序生成的文件名。

    文件名用随机 uuid，不用用户的原文件名：避免重名、避免奇怪字符，
    原文件名另存一列，只用来显示。
    """
    if repo.get_note(note_id) is None:
        raise LookupError(f"笔记不存在：{note_id}")
    data = base64.b64decode(data_base64, validate=True)
    if not data:
        raise ValueError("图片是空的")
    if len(data) > MAX_IMAGE_BYTES:
        raise ValueError("图片太大（超过 30MB）")

    ext = os.path.splitext(original_name)[1].lower().lstrip(".")
    if ext not in _IMAGE_EXTS:
        ext = "png"
    filename = f"{uuid.uuid4().hex}.{ext}"

    folder = db.attachments_dir()
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, filename)
    with open(path, "wb") as f:
        f.write(data)
    try:
        with db.get():
            repo.insert_attachment(note_id, filename, original_name, width, height, len(data))
    except Exception:
        os.remove(path)          # 数据库没写进去，文件也别留着
        raise
    return {"filename": filename, "src": body_mod.ATTACHMENT_PREFIX + filename}


def _remove_files(filenames: list[str]) -> None:
    folder = db.attachments_dir()
    for f in filenames:
        try:
            os.remove(os.path.join(folder, os.path.basename(f)))
        except FileNotFoundError:
            pass


# 给已有笔记添加案主；重复添加不报错，直接返回当前笔记
def add_note_subject(note_id: int, subject_id: int) -> dict:
    get_note(note_id)  # 笔记不存在就抛 LookupError
    if repo.get_subject(subject_id) is None:
        raise LookupError(f"案主不存在：{subject_id}")
    with db.get():
        repo.link_note_subject(note_id, subject_id)
    return get_note(note_id)


# 从笔记上移除案主；案主没有笔记了也不删
def remove_note_subject(note_id: int, subject_id: int) -> dict:
    with db.get():
        if repo.unlink_note_subject(note_id, subject_id) == 0:
            raise LookupError(f"笔记 {note_id} 没有关联案主 {subject_id}")
    return get_note(note_id)


def search_subjects(keyword: str) -> list[dict]:
    return repo.search_subjects(keyword)


def create_subject(name: str, remark: str = "", birthday: str | None = None, birthtime: str | None = None, gender: int | None = None) -> dict:
    name = name.strip()
    if not name:
        raise ValueError("案主名字不能为空")
    birthday, birthtime, gender = _clean_subject_fields(birthday, birthtime, gender)
    with db.get():
        subject_id = repo.insert_subject(name, (remark or "").strip(), birthday, birthtime, gender)
    return repo.get_subject(subject_id)


def list_subjects() -> list[dict]:
    return repo.list_subjects()


def get_subject(subject_id: int) -> dict:
    """案主详情 + 和他关联的所有笔记（同笔记列表的格式）。"""
    s = repo.get_subject(subject_id)
    if s is None:
        raise LookupError(f"案主不存在：{subject_id}")
    s["notes"] = list_notes(subject_ids=[subject_id])
    return s

def update_subject(subject_id: int, name: str, remark: str = "",
                   birthday: str | None = None, birthtime: str | None = None,
                   gender: int | None = None) -> dict:
    name = (name or "").strip()
    if not name:
        raise ValueError("案主名字不能为空")
    birthday, birthtime, gender = _clean_subject_fields(birthday, birthtime, gender)
    with db.get():
        if repo.update_subject(subject_id, name, (remark or "").strip(),
                               birthday, birthtime, gender) == 0:
            raise LookupError(f"案主不存在：{subject_id}")
    return get_subject(subject_id)


def delete_subject(subject_id: int, with_notes: bool = False) -> int:
    """删除案主。with_notes=False：只解除和笔记的关联，笔记保留；
    True：他的笔记一起放进回收站（可以恢复）。返回放进回收站的笔记数。"""
    with db.get():
        note_ids = repo.note_ids_of_subject(subject_id) if with_notes else []
        for nid in note_ids:
            repo.set_note_trashed(nid, True)
        if repo.delete_subject(subject_id) == 0:
            raise LookupError(f"案主不存在：{subject_id}")
    return len(note_ids)

def _clean_birthday(text: str) -> str:
    """生日 'YYYY-MM-DD' → 检查这天在历史公历里存在，返回补足位数的写法（如 '618-1-5' → '0618-01-05'）。

    不用 datetime.strptime：它只认格里历，1582 年以前按儒略历才有的日子（如 1000-02-29）会被误判成不存在，
    而 1582-10-05 到 10-14 这 10 天（历史上不存在）反而能通过。改用和八字同一套历史公历（见 ganzhi/repository）。
    """
    parts = text.split("-")
    try:
        y, m, d = (int(x) for x in parts)
        if len(parts) != 3:
            raise ValueError
    except ValueError:
        raise ValueError(f"生日格式不对：{text}（应为 YYYY-MM-DD）") from None
    if not 1 <= y <= 9999:
        raise ValueError(f"生日年份不对：{y}")
    solar_moment(y, m, d)          # 日期不存在会抛 ValueError（中文说明）
    return f"{y:04d}-{m:02d}-{d:02d}"


def _clean_subject_fields(birthday, birthtime, gender):
    birthday = (birthday or "").strip() or None
    birthtime = (birthtime or "").strip() or None
    if birthday is not None:
        birthday = _clean_birthday(birthday)
    if birthtime is not None:
        if birthday is None:
            raise ValueError("只填时间不填日期没有意义")
        try:
            datetime.strptime(birthtime, "%H:%M")
        except ValueError:
            raise ValueError(f"时间格式不对：{birthtime}（应为 HH:MM）") from None
    if gender not in (None, 0, 1):
        raise ValueError("性别只能是 1（男）、0（女）或不填")
    return birthday, birthtime, gender

# ---------- 术数：笔记用了哪些术数 ----------

def add_note_shushu(note_id: int, code: str) -> dict:
    if not shushu.is_known(code):
        raise ValueError(f"不认识的术数：{code}")
    if repo.get_note(note_id) is None:
        raise LookupError(f"笔记不存在：{note_id}")
    with db.get():
        repo.link_note_type(note_id, code)
    return {"shushu": shushu.sort_and_name(repo.get_note_types(note_id))}


def remove_note_shushu(note_id: int, code: str) -> dict:
    with db.get():
        repo.unlink_note_type(note_id, code)
    return {"shushu": shushu.sort_and_name(repo.get_note_types(note_id))}


# ---------- 命令：取参数 → 调业务 → 转 JSON (类似java里的controller层) ----------

def _to_json(data) -> str:
    return json.dumps(data, ensure_ascii=False)

def _open_cmd(req: dict) -> str:
    db.init(req["path"])
    backfill_chart_facts()
    return _to_json({"ok": True, "attachments_dir": db.attachments_dir()})

def _note_get_cmd(req: dict) -> str:
    return _to_json(get_note(req["note_id"]))

def _note_list_cmd(req: dict) -> str:
    # 筛选条件都可省；标签 / 案主 / 术数都是列表，可以多选（都要满足）
    return _to_json({"notes": list_notes(
        req.get("keyword", ""), req.get("label_ids", []), req.get("subject_ids", []), req.get("shushu", []),
        chart_query=req.get("chart_query"),       # 条件块列表，见 chart_facts.py
    )})

def _backup_cmd(req: dict) -> str:
    return _to_json(backup_mod.backup(req["path"]))

def _backup_inspect_cmd(req: dict) -> str:
    return _to_json(backup_mod.inspect(req["path"]))

def _restore_cmd(req: dict) -> str:
    result = backup_mod.restore(req["path"])
    backfill_chart_facts()              # 旧备份里的排盘也补上搜索特征
    return _to_json({"ok": True, **result})

def _chart_search_forms_cmd(req: dict) -> str:
    return _to_json({"forms": chart_facts.forms()})

def _note_update_cmd(req: dict) -> str:
    return _to_json(update_note(req["note_id"], req.get("title", ""), req.get("body", "")))

def _note_trash_cmd(req: dict) -> str:
    trash_note(req["note_id"])
    return _to_json({"ok": True})

def _note_restore_cmd(req: dict) -> str:
    restore_note(req["note_id"])
    return _to_json({"ok": True})

def _trash_list_cmd(req: dict) -> str:
    return _to_json({"notes": list_notes(trashed=True)})

def _trash_empty_cmd(req: dict) -> str:
    return _to_json({"ok": True, "deleted": empty_trash()})

def _note_delete_cmd(req: dict) -> str:
    delete_note(req["note_id"])
    return _to_json({"ok": True})

def _note_create_cmd(req: dict) -> str:
    return _to_json(create_note(
        req.get("title", ""), req.get("body", ""), req.get("subject_ids", [])
    ))

def _note_subject_add_cmd(req: dict) -> str:
    return _to_json(add_note_subject(req["note_id"], req["subject_id"]))

def _note_subject_remove_cmd(req: dict) -> str:
    return _to_json(remove_note_subject(req["note_id"], req["subject_id"]))

def _note_cleanup_cmd(req: dict) -> str:
    return _to_json(cleanup_note(req["note_id"]))

def _chart_create_cmd(req: dict) -> str:
    return _to_json(create_chart(req["note_id"], req["type"], req.get("params", {}), req.get("question", "")))

def _chart_question_cmd(req: dict) -> str:
    """改「所问之事」。"""
    q = _clean_question(req.get("question", ""))
    with db.get():
        if repo.update_chart_title(req["chart_id"], q) == 0:
            raise LookupError(f"排盘不存在：{req['chart_id']}")
    return _to_json({"question": q})

def _chart_name_cmd(req: dict) -> str:
    """改八字排盘的姓名（可以清空）。"""
    name = " ".join(str(req.get("name", "")).split())
    if len(name) > 30:
        raise ValueError("姓名太长（最多 30 字）")
    with db.get():
        if repo.update_bazi_name(req["chart_id"], name) == 0:
            raise LookupError(f"八字排盘不存在：{req['chart_id']}")
    return _to_json({"name": name})

def _clean_tag_name(name) -> str:
    name = " ".join(str(name or "").split())
    if not name:
        raise ValueError("特点不能为空")
    if len(name) > 30:
        raise ValueError("特点太长（最多 30 字）")
    return name

def _tag_search_cmd(req: dict) -> str:
    return _to_json({"tags": repo.search_tags(str(req.get("keyword", "")).strip())})

def _tag_delete_cmd(req: dict) -> str:
    with db.get():
        repo.delete_tag(req["tag_id"])
    return _to_json({"ok": True})

def _chart_tag_add_cmd(req: dict) -> str:
    """按名字给排盘加特点（没有就顺便新建），返回排盘现在的全部特点。"""
    name = _clean_tag_name(req["name"])
    with db.get():
        if repo.get_chart(req["chart_id"]) is None:
            raise LookupError(f"排盘不存在：{req['chart_id']}")
        repo.link_chart_tag(req["chart_id"], repo.get_or_create_tag(name))
    return _to_json({"tags": repo.get_chart_tags(req["chart_id"])})

def _chart_tag_remove_cmd(req: dict) -> str:
    with db.get():
        repo.unlink_chart_tag(req["chart_id"], req["tag_id"])
    return _to_json({"tags": repo.get_chart_tags(req["chart_id"])})

def _chart_get_cmd(req: dict) -> str:
    return _to_json(get_chart(req["chart_id"]))

def _attachment_add_cmd(req: dict) -> str:
    return _to_json(add_attachment(
        req["note_id"], req["data"], req.get("original_name", ""),
        req.get("width"), req.get("height"),
    ))

def _label_search_cmd(req: dict) -> str:
    return _to_json({"labels": search_labels(req.get("keyword", ""))})

def _label_create_cmd(req: dict) -> str:
    return _to_json(create_label(req["name"]))

def _label_delete_cmd(req: dict) -> str:
    delete_label(req["label_id"])
    return _to_json({"ok": True})

def _note_label_add_cmd(req: dict) -> str:
    return _to_json(add_note_label(req["note_id"], req["label_id"]))

def _note_label_remove_cmd(req: dict) -> str:
    return _to_json(remove_note_label(req["note_id"], req["label_id"]))

def _chart_label_add_cmd(req: dict) -> str:
    return _to_json({"labels": add_chart_label(req["chart_id"], req["name"])})

def _chart_label_remove_cmd(req: dict) -> str:
    return _to_json({"labels": remove_chart_label(req["chart_id"], req["label_id"])})

def _subject_search_cmd(req: dict) -> str:
    return _to_json({"subjects": search_subjects(req.get("keyword", ""))})

def _subject_create_cmd(req: dict) -> str:
    return _to_json(create_subject(req["name"], req.get("remark", ""),
        req.get("birthday"), req.get("birthtime"), req.get("gender"),))

def _subject_list_cmd(req: dict) -> str:
    return _to_json({"subjects": list_subjects()})

def _subject_get_cmd(req: dict) -> str:
    return _to_json(get_subject(req["subject_id"]))

def _subject_update_cmd(req: dict) -> str:
    return _to_json(update_subject(req["subject_id"], req["name"], req.get("remark", ""),
        req.get("birthday"), req.get("birthtime"), req.get("gender"),))

def _subject_delete_cmd(req: dict) -> str:
    trashed = delete_subject(req["subject_id"], bool(req.get("with_notes", False)))
    return _to_json({"ok": True, "trashed_notes": trashed})

def _label_list_cmd(req: dict) -> str:
    return _to_json({"labels": list_labels()})

def _shushu_list_cmd(req: dict) -> str:
    return _to_json({"shushu": shushu.all_items()})

def _note_shushu_add_cmd(req: dict) -> str:
    return _to_json(add_note_shushu(req["note_id"], req["code"]))

def _note_shushu_remove_cmd(req: dict) -> str:
    return _to_json(remove_note_shushu(req["note_id"], req["code"]))


COMMANDS = {
    "casebook_open": _open_cmd,
    "note_create": _note_create_cmd,
    "note_get": _note_get_cmd,
    "note_list": _note_list_cmd,
    "note_update": _note_update_cmd,
    "note_delete": _note_delete_cmd,          # 彻底删除（回收站里的「彻底删除」、新建没保存就离开）
    "note_trash": _note_trash_cmd,            # 放进回收站
    "note_restore": _note_restore_cmd,        # 从回收站恢复
    "trash_list": _trash_list_cmd,            # 回收站里的笔记
    "trash_empty": _trash_empty_cmd,          # 清空回收站
    "chart_search_forms": _chart_search_forms_cmd,
    "casebook_backup": _backup_cmd,                  # 备份到用户选的 zip 文件
    "casebook_backup_inspect": _backup_inspect_cmd,  # 看备份文件里是什么（恢复前确认）
    "casebook_restore": _restore_cmd,                # 用备份替换全部数据（先自动备份当前的）   # 按排盘搜索的面板（各术数能按什么搜）
    "note_subject_add": _note_subject_add_cmd,
    "note_subject_remove": _note_subject_remove_cmd,
    "note_cleanup": _note_cleanup_cmd,
    "chart_create": _chart_create_cmd,
    "chart_get": _chart_get_cmd,
    "attachment_add": _attachment_add_cmd,
    "label_search": _label_search_cmd,
    "label_create": _label_create_cmd,
    "label_delete": _label_delete_cmd,
    "note_label_add": _note_label_add_cmd,
    "note_label_remove": _note_label_remove_cmd,
    "chart_label_add": _chart_label_add_cmd,
    "chart_label_remove": _chart_label_remove_cmd,
    "subject_search": _subject_search_cmd,
    "subject_create": _subject_create_cmd,
    "subject_list": _subject_list_cmd,
    "subject_get": _subject_get_cmd,
    "subject_update": _subject_update_cmd,
    "subject_delete": _subject_delete_cmd,
    "chart_question": _chart_question_cmd,      # 改排盘的「所问之事」
    "chart_name": _chart_name_cmd,              # 改八字排盘的姓名
    "tag_search": _tag_search_cmd,              # 排盘特点：搜索（空 = 全部）
    "tag_delete": _tag_delete_cmd,              # 彻底删除一个特点（所有排盘上一起去掉）
    "chart_tag_add": _chart_tag_add_cmd,        # 给排盘加特点（按名字，没有就新建）
    "chart_tag_remove": _chart_tag_remove_cmd,
    "label_list": _label_list_cmd,
    "shushu_list": _shushu_list_cmd,
    "note_shushu_add": _note_shushu_add_cmd,
    "note_shushu_remove": _note_shushu_remove_cmd,
}
