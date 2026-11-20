"""案例库的业务与命令。"""
import json

from divination.casebook import db, repository as repo


def get_note(note_id: int) -> dict:
    note = repo.get_note(note_id)
    if note is None:
        raise LookupError(f"笔记不存在：{note_id}")
    return note


def create_note(title: str, body: str) -> dict:
    note_id = repo.insert_note(title, body)
    db.get().commit()
    return get_note(note_id)

# 列出所有笔记 
def list_notes() -> list[dict]:
    return repo.list_notes()


def update_note(note_id: int, title: str, body: str) -> dict:
    if repo.update_note(note_id, title, body) == 0:
        raise LookupError(f"笔记不存在：{note_id}")
    db.get().commit()
    return get_note(note_id)


def delete_note(note_id: int) -> None:
    if repo.delete_note(note_id) == 0:
        raise LookupError(f"笔记不存在：{note_id}")
    db.get().commit()




# ---------- 命令：取参数 → 调业务 → 转 JSON (类似java里的controller层) ----------

def _to_json(data) -> str:
    return json.dumps(data, ensure_ascii=False)

def _open_cmd(req: dict) -> str:
    db.init(req["path"])
    return _to_json({"ok": True})

def _note_create_cmd(req: dict) -> str:
    return _to_json(create_note(req.get("title", ""), req.get("body", "")))

def _note_get_cmd(req: dict) -> str:
    return _to_json(get_note(req["note_id"]))

def _note_list_cmd(req: dict) -> str:
    return _to_json({"notes": list_notes()})

def _note_update_cmd(req: dict) -> str:
    return _to_json(update_note(req["note_id"], req.get("title", ""), req.get("body", "")))

def _note_delete_cmd(req: dict) -> str:
    delete_note(req["note_id"])
    return _to_json({"ok": True})

COMMANDS = {
    "casebook_open": _open_cmd,
    "note_create": _note_create_cmd,
    "note_get": _note_get_cmd,
    "note_list": _note_list_cmd,
    "note_update": _note_update_cmd,
    "note_delete": _note_delete_cmd,
}
