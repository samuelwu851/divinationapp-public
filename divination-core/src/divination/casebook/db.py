"""案例库的数据库连接：打开文件、建表、按版本升级。"""
import os
import sqlite3

from divination.casebook.schema import MIGRATIONS

_conn = None
_attachments_dir = None
_path = None


def init(path: str) -> None:
    global _conn, _attachments_dir, _path
    close()                     # 重新打开（比如恢复备份后）：先关掉旧连接
    # 图片放在数据库旁边的文件夹：casebook-debug.db → casebook-debug-attachments/
    # 调试库和正式库各用各的，互不干扰
    stem = os.path.splitext(os.path.basename(path))[0]
    _attachments_dir = os.path.join(os.path.dirname(os.path.abspath(path)), f"{stem}-attachments")
    # 1. 打开连接
    conn = sqlite3.connect(path)
    # 2. 设置 row_factory
    conn.row_factory = sqlite3.Row
    # 3. 开启外键
    conn.execute("PRAGMA foreign_keys = ON")
    # 4. 读出当前版本号
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    # 5. 依次执行还没执行过的 MIGRATIONS，每段执行完更新版本号
    for i in range (version, len(MIGRATIONS)):
        conn.executescript(MIGRATIONS[i])
        conn.execute(f"PRAGMA user_version = {i + 1}")
    _conn = conn
    _path = os.path.abspath(path)



def close() -> None:
    """关掉连接（恢复备份要替换数据库文件前调用）。"""
    global _conn
    if _conn is not None:
        _conn.close()
        _conn = None


def path() -> str:
    """当前数据库文件的路径。"""
    if _path is None:
        raise RuntimeError("database has not init yet")
    return _path


def get() -> sqlite3.Connection:
    # 还没 init 就抛错，否则返回 _conn
    if _conn is None:
        raise RuntimeError("database has not init yet")
    return _conn


def attachments_dir() -> str:
    """图片文件夹的路径（不保证已存在，写文件前自己建）。"""
    if _attachments_dir is None:
        raise RuntimeError("database has not init yet")
    return _attachments_dir
