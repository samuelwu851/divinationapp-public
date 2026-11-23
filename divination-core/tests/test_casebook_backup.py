"""数据备份 / 恢复。"""
import base64
import json
import os
import sqlite3
import zipfile

import pytest

from divination.api import handle
from divination.casebook import schema

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\nfake").decode()


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


@pytest.fixture
def lib(tmp_path):
    path = tmp_path / "lib" / "casebook.db"
    path.parent.mkdir()
    call("casebook_open", path=str(path))
    return path


def test_backup_and_restore_roundtrip(lib, tmp_path):
    n = call("note_create", title="原来的")
    att = call("attachment_add", note_id=n["id"], data=PNG, original_name="a.png")
    call("chart_create", note_id=n["id"], type="bazi",
         params={"year": 1990, "month": 5, "day": 1, "hour": 8, "minute": 0, "is_male": True})
    dest = tmp_path / "备份.zip"
    r = call("casebook_backup", path=str(dest))
    assert r["notes"] == 1 and r["attachments"] == 1 and dest.exists()
    info = call("casebook_backup_inspect", path=str(dest))
    assert info["notes"] == 1 and info["schema_version"] == len(schema.MIGRATIONS)

    # 备份后又改了：删掉原来的、加一篇新的
    call("note_delete", note_id=n["id"])
    call("note_create", title="后来的")
    assert [x["title"] for x in call("note_list")["notes"]] == ["后来的"]

    r = call("casebook_restore", path=str(dest))
    assert r["ok"] and r["notes"] == 1 and os.path.exists(r["safety_backup"])
    assert [x["title"] for x in call("note_list")["notes"]] == ["原来的"]
    img = lib.parent / "casebook-attachments" / att["filename"]
    assert img.read_bytes() == base64.b64decode(PNG)
    assert len(call("note_list", chart_query=[{"type": "bazi", "fields": {"gender": "male"}}])["notes"]) == 1
    # 恢复前自动备份里是「后来的」
    assert call("casebook_backup_inspect", path=r["safety_backup"])["notes"] == 1
    call("casebook_restore", path=r["safety_backup"])
    assert [x["title"] for x in call("note_list")["notes"]] == ["后来的"]


def test_restore_old_version_backup_upgrades(lib, tmp_path):
    """旧版本 App 做的备份：恢复后自动升级到当前版本。"""
    old = tmp_path / "old.db"
    con = sqlite3.connect(old)
    con.executescript(schema.SCHEMA_V1 + schema.SCHEMA_V2)
    con.execute("PRAGMA user_version = 2")
    con.execute("INSERT INTO notes(id, title) VALUES (1, '老笔记')")
    con.execute("INSERT INTO subjects(id, name) VALUES (1, '老案主')")
    con.commit(); con.close()
    z = tmp_path / "old.zip"
    with zipfile.ZipFile(z, "w") as f:
        f.writestr("manifest.json", json.dumps({"format": "divination-casebook-backup", "schema_version": 2, "notes": 1}))
        f.write(old, "casebook.db")
    call("casebook_restore", path=str(z))
    assert [x["title"] for x in call("note_list")["notes"]] == ["老笔记"]
    s = call("subject_get", subject_id=1)
    assert s["name"] == "老案主" and s["birthday"] is None            # V4 的新字段已经有了


@pytest.mark.parametrize("make,msg", [
    (lambda p: p.write_text("not a zip"), "不是有效的备份"),
    (lambda p: zipfile.ZipFile(p, "w").close(), "不是本 App"),
    (lambda p: _zip(p, {"format": "divination-casebook-backup", "schema_version": 999}), "更新版本"),
    (lambda p: _zip(p, {"format": "divination-casebook-backup", "schema_version": 1}, db=b"garbage"), "损坏"),
])
def test_bad_backups_rejected_and_data_untouched(lib, tmp_path, make, msg):
    call("note_create", title="不能丢")
    bad = tmp_path / "bad.zip"
    make(bad)
    r = call("casebook_restore", path=str(bad))
    assert msg in r["error"]
    assert [x["title"] for x in call("note_list")["notes"]] == ["不能丢"]


def _zip(path, manifest, db=None):
    with zipfile.ZipFile(path, "w") as f:
        f.writestr("manifest.json", json.dumps(manifest))
        f.writestr("casebook.db", db if db is not None else b"")
