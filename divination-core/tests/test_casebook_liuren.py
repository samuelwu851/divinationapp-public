"""案例库里的大六壬：存排盘、按排盘搜（固定字段、课体多值、加临 / 乘神这种用户自己加的条件）。"""
import json

import pytest

from divination.api import handle
from divination.casebook import chart_facts
from divination.liuren import core


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


def ids(**filters):
    return sorted(n["id"] for n in call("note_list", **filters)["notes"])


@pytest.fixture(autouse=True)
def fresh(tmp_path):
    call("casebook_open", path=str(tmp_path / "t.db"))


# 参考盘：2026-11-26 08:44 甲辰日 辰时 寅将，涉害。固定用深浅法：三传 寅子戌（螣蛇 天后 玄武）
# （默认孟仲季法是 戌申午；这里只测案例库的存取和搜索，取法定死免得跟着默认变）
REF = {"date": {"year": 2026, "month": 11, "day": 26, "hour": 8, "minute": 44}, "method": "depth",
       "nianming": [{"birth": "庚申", "gender": "男"}]}


def _note_with_chart(params, question=""):
    n = call("note_create", title="六壬")
    c = call("chart_create", note_id=n["id"], type="daliuren", params=params, question=question)
    return n, c


def q(**fields):
    return [{"type": "daliuren", "fields": fields}]


def test_create_chart_snapshot():
    n, c = _note_with_chart(REF, question="问事业")
    assert c["type"] == "daliuren" and c["title"] == "问事业"
    s = c["snapshot"]
    assert s["day"] == "甲辰" and s["sanchuan"]["ke_ti"] == "涉害"
    assert [x["zhi"] for x in s["sanchuan"]["chuan"]] == ["寅", "子", "戌"]
    assert s["nianming"][0]["xingnian"]["ganzhi"] == "壬子"


def test_saved_chart_keeps_its_method():
    """存进案例库的课不跟着默认取法变：存的时候用深浅法，之后读出来、重拆特征都还是深浅法那一课。"""
    n, c = _note_with_chart(REF)                                   # REF 定了 method=depth
    got = call("chart_get", chart_id=c["id"])
    assert got["params"]["method"] == "depth"
    assert [x["zhi"] for x in got["snapshot"]["sanchuan"]["chuan"]] == ["寅", "子", "戌"]   # 默认孟仲季会是 戌申午
    assert ids(chart_query=q(chu="寅")) == [n["id"]] and ids(chart_query=q(chu="戌")) == []


def test_saved_chart_keeps_its_guiren():
    """贵人起法同理：存的时候用 甲(戊)庚牛羊，读出来还是那一课。
    2024-02-13 14:00 丁未日未时（昼）：默认昼贵亥，甲(戊)庚牛羊 丁日昼贵酉。"""
    n, c = _note_with_chart({"date": {"year": 2024, "month": 2, "day": 13, "hour": 14}, "guiren": "alt"})
    got = call("chart_get", chart_id=c["id"])
    assert got["params"]["guiren"] == "alt" and got["snapshot"]["guiren"] == "alt"
    assert next(p["zhi"] for p in got["snapshot"]["pan"] if p["jiang"] == "贵人") == "酉"


def test_ke_ge():
    assert core.ke_ge(["寅", "子", "戌"]) == ["退间传"]
    assert core.ke_ge(["亥", "子", "丑"]) == ["进连茹"]
    assert core.ke_ge(["申", "子", "辰"]) == ["润下"]
    assert core.ke_ge(["辰", "丑", "戌"]) == ["稼穑"]
    assert core.ke_ge(["酉", "酉", "酉"]) == []


def test_search_fixed_fields():
    n, _ = _note_with_chart(REF)
    other, _ = _note_with_chart({"date": {"year": 2024, "month": 2, "day": 11, "hour": 12}})      # 乙巳日
    assert ids(chart_query=q()) == sorted([n["id"], other["id"]])          # 空块 = 有六壬就行
    assert ids(chart_query=q(day_gan="甲", day_zhi="辰")) == [n["id"]]
    assert ids(chart_query=q(chu="寅", chu_j="螣蛇", mo="戌")) == [n["id"]]
    assert ids(chart_query=q(chu="寅", chu_j="青龙")) == []
    # 四课：干上子天后、干阴戌玄武、支上寅螣蛇、支阴子天后
    assert ids(chart_query=q(gs="子", gs_j="天后", gy="戌", zs="寅", zy_j="天后")) == [n["id"]]
    # 课体：九宗门和课格都能搜
    assert ids(chart_query=q(ke_ti="涉害")) == [n["id"]]
    assert ids(chart_query=q(ke_ti="退间传")) == [n["id"]]
    assert ids(chart_query=q(ke_ti="贼克")) == []                # 涉害不算贼克
    assert ids(chart_query=q(ke_ti="遥克")) == []


def test_ke_ti_groups():
    snap = lambda kt: {"day": "甲子", "sike": [], "pan": [{"zhi": z, "di": z, "jiang": "贵人"} for z in core.ZHI],
                       "sanchuan": {"ke_ti": kt, "chuan": []}}
    kinds = lambda kt: {v for k, v in chart_facts._liuren_facts(snap(kt)) if k == "ke_ti"}
    assert kinds("元首") == {"元首", "贼克"} and kinds("重审") == {"重审", "贼克"}
    assert kinds("蒿矢") == {"蒿矢", "遥克"} and kinds("弹射") == {"弹射", "遥克"}
    assert kinds("比用") == {"比用"}
    ge = lambda chuan: {v for k, v in chart_facts._liuren_facts(
        {**snap("比用"), "sanchuan": {"ke_ti": "比用", "chuan": [], "ke_ge": core.ke_ge(chuan)}}) if k == "ke_ti"}
    assert ge(["申", "子", "辰"]) == {"比用", "润下", "三合"}
    assert ge(["辰", "丑", "戌"]) == {"比用", "稼穑"}                 # 稼穑不算三合


def test_search_day_riding():
    n, _ = _note_with_chart(REF)
    # 甲寄寅：天盘寅乘螣蛇；日支辰：天盘辰乘六合
    assert ids(chart_query=q(day_gan_j="螣蛇", day_zhi_j="六合")) == [n["id"]]
    assert ids(chart_query=q(day_gan_j="天后")) == []           # 干上（子）乘天后，不是日干乘将


def test_search_pairs():
    n, _ = _note_with_chart(REF)
    # 天地盘：子加寅、戌加子；乘神：子乘天后、寅乘螣蛇
    assert ids(chart_query=q(**{"jia#1": "子寅"})) == [n["id"]]
    assert ids(chart_query=q(**{"jia#1": "子寅", "jia#2": "戌子"})) == [n["id"]]
    assert ids(chart_query=q(**{"jia#1": "子寅", "jia#2": "子卯"})) == []          # 每组都要满足
    assert ids(chart_query=q(**{"cheng#1": "子天后", "cheng#2": "寅螣蛇"})) == [n["id"]]
    assert ids(chart_query=q(**{"cheng#1": "子青龙"})) == []
    assert ids(chart_query=q(**{"jia#1": "子寅", "cheng#1": "寅螣蛇", "chu": "寅"})) == [n["id"]]


def test_pairs_cleaning():
    blocks = chart_facts.clean_query(q(**{"jia#1": "子寅", "jia#13": "子寅", "jia#x": "子寅",
                                          "jia#2": "子青龙", "cheng#1": "子天后", "cheng": "子天后"}))
    assert blocks[0]["fields"] == {"jia#1": "子寅", "cheng#1": "子天后"}     # 超出 12、序号不对、值不对、裸键都去掉


def test_form():
    form = next(f for f in call("chart_search_forms")["forms"] if f["type"] == "daliuren")
    keys = [f["key"] for f in form["fields"]]
    assert {"ke_ti", "day_gan", "day_gan_j", "day_zhi_j", "gs", "gs_j", "chu", "mo_j", "jia", "cheng"} <= set(keys)
    jia = next(f for f in form["fields"] if f["key"] == "jia")
    assert jia["style"] == "pairs" and jia["max"] == 12 and jia["joiner"] == "加"
    assert call("shushu_list")["shushu"][[s["code"] for s in call("shushu_list")["shushu"]].index("daliuren")]["name"] == "大六壬"
