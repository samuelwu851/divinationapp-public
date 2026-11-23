"""排盘的「所问之事」、排盘「特点」、删除案主时连笔记一起删。"""
import json
import sqlite3

import pytest

from divination.api import handle
from divination.casebook import schema


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


@pytest.fixture(autouse=True)
def fresh(tmp_path):
    call("casebook_open", path=str(tmp_path / "t.db"))


BAZI = {"year": 1990, "month": 5, "day": 1, "hour": 8, "minute": 0, "is_male": True, "name": "张三"}


def test_question_on_create_and_update():
    n = call("note_create", title="x")
    c = call("chart_create", note_id=n["id"], type="iching", params={"org_value": 63, "chg_value": 31},
             question="  这次  出行\n顺利吗？ ")
    assert c["title"] == "这次 出行 顺利吗？"
    b = call("chart_create", note_id=n["id"], type="bazi", params=BAZI)
    assert b["title"] == "" and b["snapshot"]["name"] == "张三"          # 姓名不再当成所问之事
    assert call("chart_question", chart_id=c["id"], question="问财运")["question"] == "问财运"
    assert call("chart_get", chart_id=c["id"])["title"] == "问财运"
    assert "error" in call("chart_question", chart_id=c["id"], question="字" * 101)
    assert "error" in call("chart_question", chart_id=9999, question="x")


def test_tags_add_order_remove_delete():
    n = call("note_create", title="x")
    c = call("chart_create", note_id=n["id"], type="bazi", params=BAZI)
    call("chart_tag_add", chart_id=c["id"], name="伤官见官")
    r = call("chart_tag_add", chart_id=c["id"], name=" 从格 ")
    assert [t["name"] for t in r["tags"]] == ["伤官见官", "从格"]                 # 按添加先后
    call("chart_tag_add", chart_id=c["id"], name="从格")                          # 重复加不报错
    assert len(call("chart_get", chart_id=c["id"])["tags"]) == 2
    found = call("tag_search", keyword="从")["tags"]
    assert found[0]["name"] == "从格" and found[0]["uses"] == 1
    tid = found[0]["id"]
    assert [t["name"] for t in call("chart_tag_remove", chart_id=c["id"], tag_id=tid)["tags"]] == ["伤官见官"]
    other = call("tag_search", keyword="伤官")["tags"][0]["id"]
    call("tag_delete", tag_id=other)
    assert call("chart_get", chart_id=c["id"])["tags"] == []
    assert "error" in call("chart_tag_add", chart_id=c["id"], name="   ")


def test_delete_subject_keep_or_trash_notes():
    a = call("subject_create", name="张三")
    b = call("subject_create", name="李四")
    n1 = call("note_create", title="张三的", subject_ids=[a["id"]])
    n2 = call("note_create", title="李四的", subject_ids=[b["id"]])
    r = call("subject_delete", subject_id=a["id"])
    assert r == {"ok": True, "trashed_notes": 0}
    assert {n["id"] for n in call("note_list")["notes"]} == {n1["id"], n2["id"]}   # 笔记留着
    r = call("subject_delete", subject_id=b["id"], with_notes=True)
    assert r["trashed_notes"] == 1
    assert [n["id"] for n in call("note_list")["notes"]] == [n1["id"]]
    assert [n["id"] for n in call("trash_list")["notes"]] == [n2["id"]]            # 进了回收站，能恢复


def test_v5_clears_bazi_name_from_title(tmp_path):
    path = tmp_path / "old.db"
    con = sqlite3.connect(path)
    con.executescript(schema.SCHEMA_V1 + schema.SCHEMA_V2 + schema.SCHEMA_V3 + schema.SCHEMA_V4)
    con.execute("PRAGMA user_version = 4")
    con.execute("INSERT INTO notes(id, title) VALUES (1, 'x')")
    con.execute("""INSERT INTO charts(note_id, type, title, params_json, snapshot_json, algo_version)
                   VALUES (1, 'bazi', '张三', '{}', '{"name": "张三", "chart": {}}', '1'),
                          (1, 'iching', '问出行', '{}', '{}', '1')""")
    con.commit(); con.close()
    call("casebook_open", path=str(path))
    titles = sorted(r[0] for r in sqlite3.connect(path).execute("SELECT title FROM charts"))
    assert titles == ["", "问出行"]


def test_keyword_search_covers_question_and_tags():
    n1 = call("note_create", title="甲")
    n2 = call("note_create", title="乙")
    c1 = call("chart_create", note_id=n1["id"], type="iching", params={"org_value": 63, "chg_value": 31},
              question="问 Career 发展")
    c2 = call("chart_create", note_id=n2["id"], type="bazi", params=BAZI)
    call("chart_tag_add", chart_id=c2["id"], name="伤官见官")
    ids = lambda kw: sorted(n["id"] for n in call("note_list", keyword=kw)["notes"])
    assert ids("career") == [n1["id"]]                 # 所问之事（英文不分大小写）
    assert ids("伤官") == [n2["id"]]                    # 特点
    assert ids("问") == [n1["id"]]
    assert ids("没有的词") == []
    call("chart_question", chart_id=c1["id"], question="")
    assert ids("career") == []


def test_meihua_chart_methods():
    n = call("note_create", title="x")
    t = call("chart_create", note_id=n["id"], type="meihua",
             params={"year": 2026, "month": 3, "day": 5, "hour": 10, "minute": 0})
    assert t["snapshot"]["qigua"]["method"] == "time"
    assert set(t["snapshot"]["bazi"]["pillars"]["year"]) >= {"ganzhi", "canggan", "nayin"}   # bazi 包的四柱
    num = call("chart_create", note_id=n["id"], type="meihua", params={"method": "number", "numbers": [3, 5, 10]})
    assert num["snapshot"]["bazi"] is None and num["snapshot"]["original"]["name"] == "火風鼎"
    sp = call("chart_create", note_id=n["id"], type="meihua", params={"method": "specified", "upper": 6, "lower": 1, "moving": 3})
    assert sp["snapshot"]["original"]["name"] == "水天需"
    assert "error" in call("chart_create", note_id=n["id"], type="meihua", params={"method": "number", "numbers": [0, 1, 1]})
    assert "error" in call("bazi", year=2026, month=1, day=1, hour=0, minute=0)       # 旧的八字命令已经删了


def test_bazi_chart_name():
    n = call("note_create", title="x")
    b = call("chart_create", note_id=n["id"], type="bazi", params={**BAZI, "name": ""})
    assert call("chart_name", chart_id=b["id"], name=" 李 四 ")["name"] == "李 四"
    got = call("chart_get", chart_id=b["id"])
    assert got["snapshot"]["name"] == "李 四" and got["params"]["name"] == "李 四"
    assert got["snapshot"]["chart"]["pillars"] == b["snapshot"]["chart"]["pillars"]     # 排盘结果不变
    i = call("chart_create", note_id=n["id"], type="iching", params={"org_value": 1})
    assert "error" in call("chart_name", chart_id=i["id"], name="x")                    # 只有八字有姓名


def test_bazi_name_searchable_as_subject_and_keyword():
    zhang = call("subject_create", name="张三")
    n1 = call("note_create", title="没关联案主")
    n2 = call("note_create", title="关联了", subject_ids=[zhang["id"]])
    b = call("chart_create", note_id=n1["id"], type="bazi", params={**BAZI, "name": "张三"})
    ids = lambda **f: sorted(n["id"] for n in call("note_list", **f)["notes"])
    assert ids(subject_ids=[zhang["id"]]) == sorted([n1["id"], n2["id"]])     # 八字姓名 = 案主名，也算
    assert ids(keyword="张") == [n1["id"]]                                     # 关键字也搜八字姓名
    call("chart_name", chart_id=b["id"], name="李四")
    assert ids(subject_ids=[zhang["id"]]) == [n2["id"]]
