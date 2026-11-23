"""数据备份 / 恢复：整个案例库（数据库 + 笔记里的图片）打包成一个 zip 文件。

备份文件里有：
    manifest.json   说明：哪个 App、什么时候备份的、数据库是第几版（schema_version）、几篇笔记
    casebook.db     数据库（用 SQLite 自带的 backup 拷一份，拷的时候数据库照常可用，不会拷到写了一半的数据）
    attachments/    笔记里的图片

恢复：
- 先检查备份文件：是不是我们的备份、数据库能不能打开、版本是不是比当前 App 还新（新版 App 做的备份，旧版不认）；
- 再把**当前**的数据自动备份一份到数据库旁边（<名字>-恢复前自动备份.zip，只留最近一份），万一恢复错了还能找回；
- 然后用备份替换数据库和图片，重新打开——旧版本的备份会自动升级到当前版本（同 App 更新时的升级）。
"""
import datetime
import json
import os
import shutil
import sqlite3
import tempfile
import zipfile

from divination.casebook import db
from divination.casebook.schema import MIGRATIONS

FORMAT = "divination-casebook-backup"
FORMAT_VERSION = 1
_DB_NAME = "casebook.db"
_ATT_DIR = "attachments/"


def _snapshot_db(dest: str) -> None:
    """把当前数据库完整拷到 dest（SQLite 的在线备份：拷的过程中数据一致）。"""
    out = sqlite3.connect(dest)
    try:
        db.get().backup(out)
    finally:
        out.close()


def _note_count(conn: sqlite3.Connection) -> int:
    return conn.execute("SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL").fetchone()[0]


def backup(dest_path: str) -> dict:
    """备份到 dest_path（一个 .zip 文件，已存在就覆盖）。返回 {path, notes, attachments, size}。"""
    conn = db.get()
    att_dir = db.attachments_dir()
    with tempfile.TemporaryDirectory() as tmp:
        snap = os.path.join(tmp, _DB_NAME)
        _snapshot_db(snap)
        files = sorted(os.listdir(att_dir)) if os.path.isdir(att_dir) else []
        manifest = {
            "format": FORMAT,
            "format_version": FORMAT_VERSION,
            "created_at": datetime.datetime.now().isoformat(timespec="seconds"),
            "schema_version": conn.execute("PRAGMA user_version").fetchone()[0],
            "notes": _note_count(conn),
            "attachments": len(files),
        }
        partial = dest_path + ".part"          # 先写临时文件，写完再改名：写到一半出错不会留下坏的备份
        with zipfile.ZipFile(partial, "w", compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
            z.write(snap, _DB_NAME)
            for name in files:
                full = os.path.join(att_dir, name)
                if os.path.isfile(full):
                    # 图片本来就是压缩过的，再压没用，直接存
                    z.write(full, _ATT_DIR + name, compress_type=zipfile.ZIP_STORED)
        os.replace(partial, dest_path)
    return {"path": dest_path, "notes": manifest["notes"], "attachments": len(files),
            "size": os.path.getsize(dest_path)}


def inspect(src_path: str) -> dict:
    """看一个备份文件里是什么（恢复前给用户确认用）；不是有效的备份就抛 ValueError（中文说明）。"""
    try:
        z = zipfile.ZipFile(src_path)
    except (zipfile.BadZipFile, OSError):
        raise ValueError("这不是有效的备份文件") from None
    with z:
        names = set(z.namelist())
        if "manifest.json" not in names or _DB_NAME not in names:
            raise ValueError("这不是本 App 的备份文件")
        try:
            manifest = json.loads(z.read("manifest.json"))
        except ValueError:
            raise ValueError("备份文件已损坏（说明文件读不出来）") from None
    if manifest.get("format") != FORMAT:
        raise ValueError("这不是本 App 的备份文件")
    if manifest.get("schema_version", 0) > len(MIGRATIONS):
        raise ValueError("这个备份是更新版本的 App 做的，请先把 App 更新到最新版再恢复")
    return manifest


def restore(src_path: str) -> dict:
    """用备份替换当前的全部数据。返回 {notes, attachments, safety_backup}（safety_backup = 恢复前自动备份的路径）。"""
    manifest = inspect(src_path)
    db_path = db.path()
    att_dir = db.attachments_dir()
    folder = os.path.dirname(db_path)
    stem = os.path.splitext(os.path.basename(db_path))[0]

    with tempfile.TemporaryDirectory(dir=folder) as tmp:      # 放在同一个文件夹里：之后改名是原子操作
        # 1. 解压并检查数据库
        with zipfile.ZipFile(src_path) as z:
            z.extract(_DB_NAME, tmp)
            new_att = os.path.join(tmp, "attachments")
            os.makedirs(new_att)
            for info in z.infolist():
                if info.filename.startswith(_ATT_DIR) and not info.is_dir():
                    name = os.path.basename(info.filename)
                    if not name or name.startswith("."):
                        continue                              # 不接受奇怪的路径（如 ../）
                    with z.open(info) as fin, open(os.path.join(new_att, name), "wb") as fout:
                        shutil.copyfileobj(fin, fout)
        new_db = os.path.join(tmp, _DB_NAME)
        try:
            check = sqlite3.connect(new_db)
            ok = check.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            check.close()
        except sqlite3.DatabaseError:
            ok = False
        if not ok:
            raise ValueError("备份里的数据库已损坏，无法恢复")

        # 2. 先把当前数据自动备份一份（万一恢复错了还能找回）
        safety = os.path.join(folder, f"{stem}-恢复前自动备份.zip")
        backup(safety)

        # 3. 关掉数据库，替换数据库和图片
        db.close()
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(db_path + suffix)
            except FileNotFoundError:
                pass
        os.replace(new_db, db_path)
        if os.path.isdir(att_dir):
            shutil.rmtree(att_dir)
        os.replace(new_att, att_dir)

    # 4. 重新打开（旧版本的备份会在这里自动升级）
    db.init(db_path)
    return {"notes": manifest.get("notes"), "attachments": manifest.get("attachments"), "safety_backup": safety}
