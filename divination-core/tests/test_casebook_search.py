"""案例库：笔记搜索（关键字 / 标签 / 案主 / 术数）、案主编辑、笔记术数、V3 迁移。"""
import json
import sqlite3

import pytest

from divination.api import handle
from divination.casebook import schema


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


def body(text, chart_id=None):
    content = [{"type": "paragraph", "content": [{"type": "text", "text": text}]}]
    if chart_id:
        content.append({"type": "chart", "attrs": {"id": chart_id}})
    return json.dumps({"type": "doc", "content": content}, ensure_ascii=False)


def ids(**filters):
    return sorted(n["id"] for n in call("note_list", **filters)["notes"])


@pytest.fixture(autouse=True)
def fresh(tmp_path):
    call("casebook_open", path=str(tmp_path / "t.db"))


@pytest.fixture
def data():
    zhang = call("subject_create", name="张三")
    li = call("subject_create", name="李四")
    a = call("note_create", title="张三问病", body=body("最近咳嗽"), subject_ids=[zhang["id"]])
    b = call("note_create", title="随手记", body=body("张三的事业"), subject_ids=[li["id"]])
    c = call("note_create", title="李四婚姻", body=body("无"), subject_ids=[zhang["id"], li["id"]])
    sick = call("label_create", name="疾病")
    call("note_label_add", note_id=a["id"], label_id=sick["id"])
    chart = call("chart_create", note_id=c["id"], type="iching", params={"org_value": 63, "chg_value": 31})
    call("note_update", note_id=c["id"], title="李四婚姻", body=body("无", chart["id"]))
    call("chart_label_add", chart_id=chart["id"], name="疾病")        # 只有 c 的排盘有「疾病」
    call("note_shushu_add", note_id=b["id"], code="daliuren")
    call("note_shushu_add", note_id=c["id"], code="daliuren")
    return dict(zhang=zhang["id"], li=li["id"], a=a["id"], b=b["id"], c=c["id"], sick=sick["id"])


def test_keyword_title_and_body(data):
    assert ids(keyword="张三") == sorted([data["a"], data["b"]])   # a 标题、b 正文
    assert ids(keyword="  咳嗽 ") == [data["a"]]
    assert ids(keyword="") == sorted([data["a"], data["b"], data["c"]])
    assert ids(keyword="%") == []                                   # 特殊字符照字面找


def test_label_matches_note_or_its_charts(data):
    assert ids(label_ids=[data["sick"]]) == sorted([data["a"], data["c"]])


def test_subject_and_shushu_and_combined(data):
    assert ids(subject_ids=[data["zhang"]]) == sorted([data["a"], data["c"]])
    assert ids(shushu=["daliuren"]) == sorted([data["b"], data["c"]])
    assert ids(shushu=["daliuren"], subject_ids=[data["zhang"]]) == [data["c"]]
    assert ids(shushu=["daliuren"], subject_ids=[data["zhang"]], label_ids=[data["sick"]], keyword="婚") == [data["c"]]
    assert ids(shushu=["daliuren"], subject_ids=[data["zhang"]], keyword="咳嗽") == []


def test_multi_select_in_one_category_means_all(data):
    """同一类选多个：都要满足。"""
    assert ids(subject_ids=[data["zhang"], data["li"]]) == [data["c"]]          # 两个案主都关联的只有 c
    work = call("label_create", name="事业")
    call("note_label_add", note_id=data["a"], label_id=work["id"])
    assert ids(label_ids=[data["sick"], work["id"]]) == [data["a"]]
    call("note_shushu_add", note_id=data["c"], code="iching")
    assert ids(shushu=["daliuren", "iching"]) == [data["c"]]
    assert ids(shushu=["daliuren", "bazi"]) == []


def test_note_shushu_in_get_and_list(data):
    call("note_shushu_add", note_id=data["c"], code="iching")
    got = call("note_get", note_id=data["c"])["shushu"]
    assert [s["name"] for s in got] == ["易经", "大六壬"]                # 按清单顺序
    listed = {n["id"]: n["shushu"] for n in call("note_list")["notes"]}
    assert listed[data["c"]] == got and listed[data["a"]] == []
    r = call("note_shushu_remove", note_id=data["c"], code="iching")
    assert [s["code"] for s in r["shushu"]] == ["daliuren"]
    assert "error" in call("note_shushu_add", note_id=data["c"], code="nope")


def test_shushu_list():
    names = [s["name"] for s in call("shushu_list")["shushu"]]
    assert names[:5] == ["易经", "梅花易数", "六爻", "皇极经世", "八字"] and names[-1] == "随笔"
    assert {"八字", "紫微斗数", "大六壬", "奇门遁甲", "太乙神数", "小六壬", "风水", "金口诀"} <= set(names)


def test_subject_list_get_update_delete(data):
    subs = {s["name"]: s for s in call("subject_list")["subjects"]}
    assert subs["张三"]["note_count"] == 2 and subs["李四"]["note_count"] == 2
    got = call("subject_get", subject_id=data["zhang"])
    assert sorted(n["id"] for n in got["notes"]) == sorted([data["a"], data["c"]])
    up = call("subject_update", subject_id=data["zhang"], name=" 张三丰 ", remark="武当")
    assert up["name"] == "张三丰" and up["remark"] == "武当"
    assert "error" in call("subject_update", subject_id=data["zhang"], name="  ")
    assert call("subject_delete", subject_id=data["zhang"]) == {"ok": True}
    assert ids(subject_ids=[data["zhang"]]) == []
    assert len(call("note_list")["notes"]) == 3                       # 笔记都还在
    assert "error" in call("subject_get", subject_id=data["zhang"])


def test_label_list_returns_all():
    for i in range(40):
        call("label_create", name=f"标签{i}")
    assert len(call("label_list")["labels"]) == 40


def test_v3_backfills_note_types_from_charts(tmp_path):
    """V2 的老库：已有排盘的笔记，升级后自动标上对应术数。"""
    path = tmp_path / "old.db"
    con = sqlite3.connect(path)
    con.executescript(schema.SCHEMA_V1 + schema.SCHEMA_V2)
    con.execute("PRAGMA user_version = 2")
    con.execute("INSERT INTO notes(id, title) VALUES (1, 'x')")
    con.execute("INSERT INTO charts(note_id, type, params_json, snapshot_json, algo_version) "
                "VALUES (1, 'bazi', '{}', '{}', '1')")
    con.commit(); con.close()
    call("casebook_open", path=str(path))
    assert [s["code"] for s in call("note_get", note_id=1)["shushu"]] == ["bazi"]


def test_keyword_ignores_english_case():
    a = call("note_create", title="Case C", body=body("用了 Python 排盘"))
    assert ids(keyword="c") == [a["id"]]                 # 标题里是大写 C
    assert ids(keyword="PYTHON") == [a["id"]]            # 正文里是 Python
    assert ids(keyword="pYtHoN 排盘") == [a["id"]]       # 中英混合
    assert ids(keyword="排盘") == [a["id"]]


def test_subject_and_label_search_ignore_english_case():
    tom = call("subject_create", name="Tom 张")
    assert [x["id"] for x in call("subject_search", keyword="tom")["subjects"]] == [tom["id"]]
    call("label_create", name="Work")
    assert [l["name"] for l in call("label_search", keyword="wORK")["labels"]] == ["Work"]


def test_trash_restore_purge(data):
    a, c = data["a"], data["c"]
    assert call("note_trash", note_id=a) == {"ok": True}
    assert a not in ids()                                            # 正常列表里没有了
    assert a not in ids(subject_ids=[data["zhang"]])                 # 筛选也不出现
    assert [n["id"] for n in call("trash_list")["notes"]] == [a]
    assert call("trash_list")["notes"][0]["deleted_at"]
    subs = {s["name"]: s for s in call("subject_list")["subjects"]}
    assert subs["张三"]["note_count"] == 1                           # 回收站里的不算
    assert call("note_restore", note_id=a) == {"ok": True}
    assert a in ids() and call("trash_list")["notes"] == []
    call("note_trash", note_id=a); call("note_trash", note_id=c)
    assert call("trash_empty") == {"ok": True, "deleted": 2}
    assert "error" in call("note_get", note_id=a) and "error" in call("note_get", note_id=c)
    assert ids() == [data["b"]]
    assert "error" in call("note_trash", note_id=9999)


def _chart(note_id, chart_type, params):
    c = call("chart_create", note_id=note_id, type=chart_type, params=params)
    return c


def _q(*blocks):
    return [{"type": t, "fields": f} for t, f in blocks]


def test_search_by_chart_blocks():
    n1 = call("note_create", title="甲")
    n2 = call("note_create", title="乙")
    b1 = _chart(n1["id"], "bazi", {"year": 1990, "month": 5, "day": 1, "hour": 8, "minute": 0, "is_male": True})
    _chart(n2["id"], "bazi", {"year": 1986, "month": 3, "day": 15, "hour": 20, "minute": 0, "is_male": False})
    p = {k: v["ganzhi"] for k, v in b1["snapshot"]["chart"]["pillars"].items()}      # 庚午 庚辰 丙寅 壬辰
    assert ids(chart_query=_q(("bazi", {"year_gan": p["year"][0]}))) == [n1["id"]]
    assert ids(chart_query=_q(("bazi", {"year_gan": p["year"][0], "hour_zhi": p["hour"][1]}))) == [n1["id"]]
    assert ids(chart_query=_q(("bazi", {"year_gan": p["year"][0], "hour_zhi": "子"}))) == []   # 同一张盘要同时满足
    assert ids(chart_query=_q(("bazi", {}))) == sorted([n1["id"], n2["id"]])                   # 空块 = 有八字就行
    assert ids(chart_query=_q(("bazi", {"gender": "male"}))) == [n1["id"]]
    assert ids(chart_query=_q(("bazi", {"gender": "female"}))) == [n2["id"]]
    # 两个八字块：要有两张不同的八字分别满足
    assert ids(chart_query=_q(("bazi", {"gender": "male"}), ("bazi", {}))) == []                # n1 只有一张八字
    _chart(n1["id"], "bazi", {"year": 2000, "month": 1, "day": 1, "hour": 0, "minute": 0, "is_male": False})
    assert ids(chart_query=_q(("bazi", {"gender": "male"}), ("bazi", {"gender": "female"}))) == [n1["id"]]
    assert ids(chart_query=_q(("bazi", {"gender": "male"}), ("bazi", {"gender": "male"}))) == []
    # 八字 + 梅花：两种都要有
    m = _chart(n1["id"], "meihua", {"year": 2026, "month": 3, "day": 5, "hour": 10, "minute": 0})
    from divination.casebook import chart_facts as cf
    facts = dict(cf.extract("meihua", m["snapshot"]))
    assert {"ben_upper", "ben_lower", "bian_upper", "bian_lower"} <= set(facts)
    both = _q(("bazi", {"day_gan": p["day"][0]}), ("meihua", {"ben_upper": facts["ben_upper"], "bian_lower": facts["bian_lower"]}))
    assert ids(chart_query=both) == [n1["id"]]
    other = "坤" if facts["ben_upper"] != "坤" else "乾"
    assert ids(chart_query=_q(("bazi", {}), ("meihua", {"ben_upper": other}))) == []


def test_search_iching_has_change():
    n1 = call("note_create", title="有变")
    n2 = call("note_create", title="没变")
    _chart(n1["id"], "iching", {"org_value": 63, "chg_value": 31})       # 乾 → 姤
    _chart(n2["id"], "iching", {"org_value": 63, "chg_value": 63})
    assert ids(chart_query=_q(("iching", {"has_change": "yes"}))) == [n1["id"]]
    assert ids(chart_query=_q(("iching", {"has_change": "no"}))) == [n2["id"]]
    assert ids(chart_query=_q(("iching", {"bian_lower": "巽"}))) == [n1["id"]]                  # 姤：乾上巽下
    assert ids(chart_query=_q(("iching", {"ben_upper": "乾", "bian_upper": "乾"}))) == sorted([n1["id"], n2["id"]])


def test_chart_search_forms():
    forms = {f["type"]: f for f in call("chart_search_forms")["forms"]}
    labels = [x["label"] for x in forms["bazi"]["fields"]]
    assert labels[0] == "性别" and labels[1:5] == ["年干", "月干", "日干", "时干"]
    assert forms["bazi"]["fields"][0]["style"] == "checks"
    assert len(forms["bazi"]["fields"]) == 9 and len(forms["meihua"]["fields"]) == 4
    assert [x["key"] for x in forms["iching"]["fields"]][0] == "has_change"
    assert [o["label"] for o in forms["meihua"]["fields"][0]["options"]][:3] == ["乾", "兑", "离"]


def test_backfill_old_charts(tmp_path):
    """升级前就存在的排盘（没有特征）：打开案例库时自动补上。"""
    import sqlite3
    path = tmp_path / "x.db"
    call("casebook_open", path=str(path))
    n = call("note_create", title="老")
    c = _chart(n["id"], "bazi", {"year": 1990, "month": 5, "day": 1, "hour": 8, "minute": 0, "is_male": True})
    con = sqlite3.connect(path); con.execute("DELETE FROM chart_facts"); con.commit(); con.close()
    call("casebook_open", path=str(path))
    gan = c["snapshot"]["chart"]["pillars"]["year"]["ganzhi"][0]
    assert ids(chart_query=_q(("bazi", {"year_gan": gan}))) == [n["id"]]
    # 旧版本拆的特征（没有性别）：版本号对不上 → 打开时重拆
    con = sqlite3.connect(path)
    con.execute("DELETE FROM chart_facts WHERE key IN ('gender')"); con.execute("UPDATE chart_facts SET value = '1' WHERE key = '_v'")
    con.commit(); con.close()
    call("casebook_open", path=str(path))
    assert ids(chart_query=_q(("bazi", {"gender": "male"}))) == [n["id"]]
