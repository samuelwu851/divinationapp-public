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


def list_notes(keyword: str = "", label_ids=(), subject_ids=(), shushu_codes=()) -> list[dict]:
    """列出笔记，可按四类条件筛选（都可省）。所有条件「同时满足」才出现——
    包括同一类里选了多个：选了「疾病」「感情」两个标签，就要两个标签都有。
    - keyword：标题或正文（纯文字 body_text）里包含这个词
    - label_ids：每个标签都要有（笔记本身有，或者笔记里任意一个排盘有，都算）
    - subject_ids：每个案主都要关联
    - shushu_codes：每个术数都要标了（note_types）
    """
    where, args = [], []
    if keyword:
        # instr 是「包含」，不像 LIKE 要处理 % 和 _ 这些特殊字符。
        # 两边都先 lower() 再比 → 英文不区分大小写（搜 c 也能找到 C）。
        # SQLite 自带的 lower() 只转 A–Z，中文等其他字符原样不动，正好合适。
        where.append("(instr(lower(n.title), lower(?)) > 0 OR instr(lower(n.body_text), lower(?)) > 0)")
        args += [keyword, keyword]
    for label_id in label_ids:          # 每个标签一条 EXISTS，用 AND 连起来 = 都要有
        where.append("""(EXISTS (SELECT 1 FROM note_labels nl WHERE nl.note_id = n.id AND nl.label_id = ?)
               OR EXISTS (SELECT 1 FROM charts c JOIN chart_labels cl ON cl.chart_id = c.id
                          WHERE c.note_id = n.id AND cl.label_id = ?))""")
        args += [label_id, label_id]
    for subject_id in subject_ids:
        where.append("EXISTS (SELECT 1 FROM notes_subjects ns WHERE ns.note_id = n.id AND ns.subject_id = ?)")
        args.append(subject_id)
    for code in shushu_codes:
        where.append("EXISTS (SELECT 1 FROM note_types nt WHERE nt.note_id = n.id AND nt.type = ?)")
        args.append(code)
    # 预览取纯文字 body_text 的前 40 字，换行替换成空格（char(10) 就是换行符）
    rows = db.get().execute(
        f"""
        SELECT n.id, n.title, replace(substr(n.body_text, 1, 40), char(10), ' ') AS preview,
        n.created_at, n.updated_at
        FROM notes n
        {"WHERE " + " AND ".join(where) if where else ""}
        ORDER BY n.updated_at DESC, n.id DESC
        """,
        args,
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



""" ---------------------- 以下是关于案主（subjects）的实现------------------------------"""

# 搜索案主（在写notes的时候，框里会出现下拉菜单既可以选择案主，也可以新建同名字的）
def search_subjects(keyword: str, limit: int = 30) -> list[dict]:
    rows = db.get().execute(
        """
        SELECT id, name, remark, birthday, birthtime, gender FROM subjects
        WHERE instr(lower(name), lower(?)) > 0          -- 英文不区分大小写（同笔记搜索）
        ORDER BY instr(lower(name), lower(?)), updated_at DESC
        LIMIT ?
        """,
        (keyword, keyword, limit),
    ).fetchall()
    return [dict(r) for r in rows]

def insert_subject(name: str, remark: str = "", birthday: str | None = None,
                   birthtime: str | None = None, gender: int | None = None) -> int:
    cur = db.get().execute(
        "INSERT INTO subjects(name, remark, birthday, birthtime, gender) VALUES (?, ?, ?, ?, ?)",
        (name, remark, birthday, birthtime, gender),
    )
    return cur.lastrowid

def list_subjects() -> list[dict]:
    """全部案主（最近改过的在前），带关联的笔记数。"""
    rows = db.get().execute(
        """
        SELECT s.id, s.name, s.remark, s.birthday, s.birthtime, s.gender, s.created_at, s.updated_at,
               (SELECT COUNT(*) FROM notes_subjects ns WHERE ns.subject_id = s.id) AS note_count
        FROM subjects s
        ORDER BY s.updated_at DESC, s.id DESC
        """
    ).fetchall()
    return [dict(r) for r in rows]

def update_subject(subject_id: int, name: str, remark: str, birthday: str | None,
                    birthtime: str | None, gender: int | None) -> int:
    return db.get().execute(
        "UPDATE subjects SET name = ?, remark = ?, birthday = ?, birthtime = ?, gender = ?, updated_at = datetime('now') WHERE id = ?",
        (name, remark, birthday, birthtime, gender, subject_id),
    ).rowcount

def delete_subject(subject_id: int) -> int:
    # notes_subjects 里的对应关系会级联删除；笔记本身不动
    return db.get().execute("DELETE FROM subjects WHERE id = ?", (subject_id,)).rowcount

def get_subject(subject_id: int) -> dict | None:
    row = db.get().execute(
        "SELECT id, name, remark, birthday, birthtime, gender, created_at, updated_at FROM subjects WHERE id = ?",
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

"""----------------------- 排盘 -----------------------"""

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


""" --------------------- 图片 ---------------------"""

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


# ---------- 标签（笔记和排盘共用一份清单，名字唯一） ----------

def search_labels(keyword: str, limit: int = 30) -> list[dict]:
    # 空关键字 = 列出全部；按「用过的次数」多的在前，常用标签排前面
    rows = db.get().execute(
        """
        SELECT l.id, l.name,
               (SELECT COUNT(*) FROM note_labels nl WHERE nl.label_id = l.id)
             + (SELECT COUNT(*) FROM chart_labels cl WHERE cl.label_id = l.id) AS uses
        FROM labels l
        WHERE instr(lower(l.name), lower(?)) > 0        -- 英文不区分大小写（同笔记搜索）
        ORDER BY instr(lower(l.name), lower(?)), uses DESC, l.name
        LIMIT ?
        """,
        (keyword, keyword, limit),
    ).fetchall()
    # uses：有多少笔记 + 排盘在用这个标签（删除标签前提示用）
    return [dict(r) for r in rows]

def delete_label(label_id: int) -> int:
    # note_labels / chart_labels 设了 ON DELETE CASCADE，所有笔记和排盘上的这个标签会一起去掉
    return db.get().execute("DELETE FROM labels WHERE id = ?", (label_id,)).rowcount

def get_or_create_label(name: str) -> int:
    """名字已存在就返回已有的 id，不存在就新建。"""
    db.get().execute("INSERT OR IGNORE INTO labels(name) VALUES (?)", (name,))
    return db.get().execute("SELECT id FROM labels WHERE name = ?", (name,)).fetchone()["id"]

def get_label(label_id: int) -> dict | None:
    row = db.get().execute("SELECT id, name FROM labels WHERE id = ?", (label_id,)).fetchone()
    return dict(row) if row else None

def get_note_labels(note_id: int) -> list[dict]:
    rows = db.get().execute(
        """
        SELECT l.id, l.name FROM note_labels nl JOIN labels l ON l.id = nl.label_id
        WHERE nl.note_id = ? ORDER BY nl.seq, l.name
        """,
        (note_id,),
    ).fetchall()
    return [dict(r) for r in rows]

def get_all_note_labels() -> list[dict]:
    rows = db.get().execute(
        """
        SELECT nl.note_id, l.id, l.name FROM note_labels nl JOIN labels l ON l.id = nl.label_id
        ORDER BY nl.seq, l.name
        """
    ).fetchall()
    return [dict(r) for r in rows]

def link_note_label(note_id: int, label_id: int) -> int:
    # seq = 这份笔记里目前最大的序号 + 1 → 新标签排在最后
    return db.get().execute(
        """
        INSERT OR IGNORE INTO note_labels(note_id, label_id, seq)
        VALUES (?, ?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM note_labels WHERE note_id = ?))
        """,
        (note_id, label_id, note_id),
    ).rowcount

def unlink_note_label(note_id: int, label_id: int) -> int:
    return db.get().execute(
        "DELETE FROM note_labels WHERE note_id = ? AND label_id = ?", (note_id, label_id)
    ).rowcount

def get_chart_labels(chart_id: int) -> list[dict]:
    rows = db.get().execute(
        """
        SELECT l.id, l.name FROM chart_labels cl JOIN labels l ON l.id = cl.label_id
        WHERE cl.chart_id = ? ORDER BY cl.seq, l.name
        """,
        (chart_id,),
    ).fetchall()
    return [dict(r) for r in rows]

def link_chart_label(chart_id: int, label_id: int) -> int:
    return db.get().execute(
        """
        INSERT OR IGNORE INTO chart_labels(chart_id, label_id, seq)
        VALUES (?, ?, (SELECT COALESCE(MAX(seq), 0) + 1 FROM chart_labels WHERE chart_id = ?))
        """,
        (chart_id, label_id, chart_id),
    ).rowcount

def unlink_chart_label(chart_id: int, label_id: int) -> int:
    return db.get().execute(
        "DELETE FROM chart_labels WHERE chart_id = ? AND label_id = ?", (chart_id, label_id)
    ).rowcount


# ---------- 笔记用了哪些术数（note_types） ----------

def get_note_types(note_id: int) -> list[str]:
    rows = db.get().execute("SELECT type FROM note_types WHERE note_id = ?", (note_id,)).fetchall()
    return [r["type"] for r in rows]

def get_all_note_types() -> list[dict]:
    return [dict(r) for r in db.get().execute("SELECT note_id, type FROM note_types").fetchall()]

def link_note_type(note_id: int, code: str) -> int:
    return db.get().execute(
        "INSERT OR IGNORE INTO note_types(note_id, type) VALUES (?, ?)", (note_id, code)
    ).rowcount

def unlink_note_type(note_id: int, code: str) -> int:
    return db.get().execute(
        "DELETE FROM note_types WHERE note_id = ? AND type = ?", (note_id, code)
    ).rowcount
