"""案例库的业务与命令。"""
import base64
import json
import os
import uuid

from divination.casebook import body as body_mod, charts, db, repository as repo


def get_note(note_id: int) -> dict:
    note = repo.get_note(note_id)
    if note is None:
        raise LookupError(f"笔记不存在：{note_id}")
    note["subjects"] = repo.get_note_subjects(note_id)
    return note


# 列出所有笔记 
def list_notes() -> list[dict]:
    notes = repo.list_notes()
    by_note = {}
    for row in repo.get_all_note_subjects():
        by_note.setdefault(row["note_id"], []).append({"id": row["id"], "name": row["name"]})
    for n in notes:
        n["subjects"] = by_note.get(n["id"], [])
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

def create_chart(note_id: int, chart_type: str, params: dict) -> dict:
    """按参数排盘并存进这份笔记，返回存好的排盘（含快照）。"""
    if repo.get_note(note_id) is None:
        raise LookupError(f"笔记不存在：{note_id}")
    title, snapshot = charts.build(chart_type, params)
    with db.get():
        chart_id = repo.insert_chart(
            note_id, chart_type, title,
            _to_json(params), _to_json(snapshot), charts.ALGO_VERSION,
        )
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
    }


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


def create_subject(name: str, remark: str = "") -> dict:
    name = name.strip()
    if not name:
        raise ValueError("案主名字不能为空")
    with db.get():
        subject_id = repo.insert_subject(name, remark)
    return repo.get_subject(subject_id)


# ---------- 命令：取参数 → 调业务 → 转 JSON (类似java里的controller层) ----------

def _to_json(data) -> str:
    return json.dumps(data, ensure_ascii=False)

def _open_cmd(req: dict) -> str:
    db.init(req["path"])
    return _to_json({"ok": True, "attachments_dir": db.attachments_dir()})

def _note_get_cmd(req: dict) -> str:
    return _to_json(get_note(req["note_id"]))

def _note_list_cmd(req: dict) -> str:
    return _to_json({"notes": list_notes()})

def _note_update_cmd(req: dict) -> str:
    return _to_json(update_note(req["note_id"], req.get("title", ""), req.get("body", "")))

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
    return _to_json(create_chart(req["note_id"], req["type"], req.get("params", {})))

def _chart_get_cmd(req: dict) -> str:
    return _to_json(get_chart(req["chart_id"]))

def _attachment_add_cmd(req: dict) -> str:
    return _to_json(add_attachment(
        req["note_id"], req["data"], req.get("original_name", ""),
        req.get("width"), req.get("height"),
    ))

def _subject_search_cmd(req: dict) -> str:
    return _to_json({"subjects": search_subjects(req.get("keyword", ""))})

def _subject_create_cmd(req: dict) -> str:
    return _to_json(create_subject(req["name"], req.get("remark", "")))


COMMANDS = {
    "casebook_open": _open_cmd,
    "note_create": _note_create_cmd,
    "note_get": _note_get_cmd,
    "note_list": _note_list_cmd,
    "note_update": _note_update_cmd,
    "note_delete": _note_delete_cmd,
    "note_subject_add": _note_subject_add_cmd,
    "note_subject_remove": _note_subject_remove_cmd,
    "note_cleanup": _note_cleanup_cmd,
    "chart_create": _chart_create_cmd,
    "chart_get": _chart_get_cmd,
    "attachment_add": _attachment_add_cmd,
    "subject_search": _subject_search_cmd,
    "subject_create": _subject_create_cmd,
}
