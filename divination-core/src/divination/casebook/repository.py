"""数据访问层：只管读写数据库，不知道请求和 JSON。"""
from divination.casebook import db


def get_note(note_id: int) -> dict | None:
    row = db.get().execute(
        """
        SELECT n.id, n.title, n.body, n.created_at, n.updated_at,
               n.subject_id, s.name AS subject_name
        FROM notes n
        LEFT JOIN subjects s ON s.id = n.subject_id
        WHERE n.id = ?
        """,
        (note_id,),
    ).fetchone()
    return dict(row) if row else None

def insert_note(title: str, body: str, subject_id: int |None = None) -> int:
    cur = db.get().execute(
        """
        INSERT INTO notes(title, body, subject_id) VALUES(?, ?, ?)
        """,
        (title, body, subject_id),
    )
    return cur.lastrowid


def list_notes() -> list[dict]:
    rows = db.get().execute(
        """
        SELECT n.id, n.title, substr(n.body, 1, 40) AS preview, n.created_at,
        n.updated_at, s.name AS subject_name, n.subject_id
        FROM notes n
        LEFT JOIN subjects s ON s.id = n.subject_id
        ORDER BY n.updated_at DESC, n.id DESC
        """
    ).fetchall()
    return [dict(r) for r in rows]

def update_note(note_id: int, title: str, body:str) -> int:
    cur = db.get().execute(
        """
        UPDATE notes
        SET title = ?, body = ?, updated_at = datetime('now')
        WHERE id = ?
        """,
        (title, body, note_id),
    )
    return cur.rowcount

def delete_note(note_id: int) -> int:
    cur = db.get().execute("DELETE FROM notes WHERE id = ?", (note_id,))
    return cur.rowcount