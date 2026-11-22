"""数据访问层：只管读写数据库，不知道请求和 JSON。"""
from divination.casebook import db


def get_note(note_id: int) -> dict | None:
    row = db.get().execute(
        """
        SELECT n.id, n.title, n.body, n.created_at, n.updated_at
        FROM notes n
        WHERE n.id = ?
        """,
        (note_id,),
    ).fetchone()
    return dict(row) if row else None

def insert_note(title: str, body: str, body_text: str) -> int:
    cur = db.get().execute(
        """
        INSERT INTO notes(title, body, body_text) VALUES(?, ?, ?)
        """,
        (title, body, body_text),
    )
    return cur.lastrowid


def list_notes() -> list[dict]:
    # 预览取纯文字 body_text 的前 40 字，换行替换成空格（char(10) 就是换行符）
    rows = db.get().execute(
        """
        SELECT n.id, n.title, replace(substr(n.body_text, 1, 40), char(10), ' ') AS preview,
        n.created_at, n.updated_at
        FROM notes n
        ORDER BY n.updated_at DESC, n.id DESC
        """
    ).fetchall()
    return [dict(r) for r in rows]

def update_note(note_id: int, title: str, body: str, body_text: str) -> int:
    cur = db.get().execute(
        """
        UPDATE notes
        SET title = ?, body = ?, body_text = ?, updated_at = datetime('now')
        WHERE id = ?
        """,
        (title, body, body_text, note_id),
    )
    return cur.rowcount

def delete_note(note_id: int) -> int:
    cur = db.get().execute("DELETE FROM notes WHERE id = ?", (note_id,))
    return cur.rowcount


# 搜索案主（在写notes的时候，框里会出现下拉菜单既可以选择案主，也可以新建同名字的）
def search_subjects(keyword: str, limit: int = 30) -> list[dict]:
    rows = db.get().execute(
        """
        SELECT id, name, remark FROM subjects
        WHERE instr(name, ?) > 0
        ORDER BY instr(name, ?), updated_at DESC
        LIMIT ?
        """,
        (keyword, keyword, limit),
    ).fetchall()
    return [dict(r) for r in rows]

def insert_subject(name: str, remark: str = "") -> int:
    cur = db.get().execute(
        "INSERT INTO subjects(name, remark) VALUES (?, ?)",
        (name, remark),
    )
    return cur.lastrowid

def get_subject(subject_id: int) -> dict | None:
    row = db.get().execute(
        "SELECT id, name, remark, created_at, updated_at FROM subjects WHERE id = ?",
        (subject_id,),
    ).fetchone()
    return dict(row) if row else None

def link_note_subjects(note_id: int, subject_ids: list[int]) -> None:
    db.get().executemany(
        "INSERT INTO notes_subjects(note_id, subject_id) VALUES(?, ?)",
        [(note_id, sid) for sid in subject_ids],
    )

# 给一份笔记挂上一位案主；已经挂过就跳过（OR IGNORE），返回实际新增的行数
def link_note_subject(note_id: int, subject_id: int) -> int:
    cur = db.get().execute(
        "INSERT OR IGNORE INTO notes_subjects(note_id, subject_id) VALUES (?, ?)",
        (note_id, subject_id),
    )
    return cur.rowcount

# 把一位案主从一份笔记上移除（只删对应关系，案主本身保留）
def unlink_note_subject(note_id: int, subject_id: int) -> int:
    cur = db.get().execute(
        "DELETE FROM notes_subjects WHERE note_id = ? AND subject_id = ?",
        (note_id, subject_id),
    )
    return cur.rowcount

# 找到这个 note 对应的所有的案主
def get_note_subjects(note_id: int) -> list[dict]:
    rows = db.get().execute(
        """
        SELECT s.id, s.name
        FROM notes_subjects ns
        JOIN subjects s ON s.id = ns.subject_id
        WHERE ns.note_id = ?
        ORDER BY s.name
        """,
        (note_id,),
    ).fetchall()
    return [dict(r) for r in rows]

# 取出一个案主下面所有的notes
def get_all_note_subjects() -> list[dict]:
    rows = db.get().execute(
        """
        SELECT ns.note_id, s.id, s.name
        FROM notes_subjects ns
        JOIN subjects s ON s.id = ns.subject_id
        ORDER BY s.name
        """
    ).fetchall()
    return [dict(r) for r in rows]

# ---------- 排盘 ----------

def insert_chart(note_id: int, chart_type: str, title: str,
                 params_json: str, snapshot_json: str, algo_version: str) -> int:
    cur = db.get().execute(
        """
        INSERT INTO charts(note_id, type, title, params_json, snapshot_json, algo_version)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (note_id, chart_type, title, params_json, snapshot_json, algo_version),
    )
    return cur.lastrowid

def get_chart(chart_id: int) -> dict | None:
    row = db.get().execute(
        """
        SELECT id, note_id, type, title, params_json, snapshot_json, algo_version, created_at
        FROM charts WHERE id = ?
        """,
        (chart_id,),
    ).fetchone()
    return dict(row) if row else None

def list_chart_ids(note_id: int) -> list[int]:
    rows = db.get().execute("SELECT id FROM charts WHERE note_id = ?", (note_id,)).fetchall()
    return [r["id"] for r in rows]

def delete_chart(chart_id: int) -> int:
    return db.get().execute("DELETE FROM charts WHERE id = ?", (chart_id,)).rowcount


# ---------- 图片 ----------

def insert_attachment(note_id: int, filename: str, original_name: str,
                      width: int | None, height: int | None, byte_size: int) -> int:
    cur = db.get().execute(
        """
        INSERT INTO attachments(note_id, filename, original_name, width, height, byte_size)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (note_id, filename, original_name, width, height, byte_size),
    )
    return cur.lastrowid

def list_attachment_filenames(note_id: int) -> list[str]:
    rows = db.get().execute(
        "SELECT filename FROM attachments WHERE note_id = ?", (note_id,)
    ).fetchall()
    return [r["filename"] for r in rows]

def delete_attachment(filename: str) -> int:
    return db.get().execute("DELETE FROM attachments WHERE filename = ?", (filename,)).rowcount
