"""案例库的数据库连接：打开文件、建表、按版本升级。"""
import sqlite3

from divination.casebook.schema import MIGRATIONS

_conn = None


def init(path: str) -> None:
    global _conn
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



def get() -> sqlite3.Connection:
    # 还没 init 就抛错，否则返回 _conn
    if _conn is None:
        raise RuntimeError("database has not init yet")
    return _conn
