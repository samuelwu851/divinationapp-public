"""神煞：规则展开后和书里的表、通行的三合起法互相核对。"""
import json

import pytest

from divination.api import handle
from divination.shensha import core
from divination.shensha.data import RULES, ZHI, GAN, CATEGORIES

GZ60 = [GAN[i % 10] + ZHI[i % 12] for i in range(60)]


def _find(res, category, name):
    for c in res["by_category"]:
        if c["category"] == category:
            for it in c["items"]:
                if it["name"] == name:
                    return it["branches"]
    raise KeyError((category, name))


def _rule(category, name):
    return next(r for r in RULES if r.category == category and r.name == name)


def test_names_unique_within_category():
    seen = set()
    for r in RULES:
        assert (r.category, r.name) not in seen, r
        seen.add((r.category, r.name))
        assert r.category in CATEGORIES
        if r.start is None:
            n = {"year_zhi": 12, "day_zhi": 12, "month": 12, "year_gan": 10, "day_gan": 10, "season": 4}[r.key]
            assert len(r.values) == n, r
            assert all(z in ZHI for v in r.values for z in v), r


@pytest.mark.parametrize("sui_name, rizhi_name", [
    ("驿马", "驿马"), ("华盖", "华盖"), ("劫煞", "劫煞"), ("灾煞", "灾煞"),
    ("年桃花", "日桃花"), ("亡神", "支亡"),
])
def test_year_sanhe_ring_matches_day_tables(sui_name, rizhi_name):
    """岁驿一圈是按年支三合起的，应该和书里日支表（同样按三合起）一模一样。"""
    s, t = _rule("岁煞", sui_name), _rule("日支煞", rizhi_name)
    for i in range(12):
        assert core.place(s, {"year_zhi": i}) == list(t.values[i]), (sui_name, ZHI[i])


@pytest.mark.parametrize("yue_name, rizhi_name", [
    ("驿马", "驿马"), ("劫煞", "劫煞"), ("灾煞", "灾煞"), ("月桃花", "日桃花"),
    ("亡神", "支亡"), ("黄幡", "华盖"),
])
def test_month_sanhe_matches_day_tables(yue_name, rizhi_name):
    """「正五九 / 二六十…」四个月一轮的，是按月建三合起的：寅月看寅的三合。"""
    s, t = _rule("月煞", yue_name), _rule("日支煞", rizhi_name)
    for m in range(12):
        z = (m + 2) % 12
        assert core.place(s, {"month": m}) == list(t.values[z]), (yue_name, ZHI[z])


def test_some_known_positions():
    r = core.compute("甲子", "丙寅", "甲子")
    assert _find(r, "岁煞", "太岁") == ["子"]
    assert _find(r, "岁煞", "丧门") == ["寅"]
    assert _find(r, "岁煞", "吊客") == ["戌"]
    assert _find(r, "岁煞", "将星") == ["子"]
    assert _find(r, "季煞", "天喜") == ["戌"]          # 春戌
    assert _find(r, "季煞", "孤辰") == ["巳"]
    assert _find(r, "季煞", "寡宿") == ["丑"]
    assert _find(r, "月煞", "月建") == ["寅"]
    assert _find(r, "月煞", "月破") == ["申"]
    assert _find(r, "月煞", "月厌") == ["戌"]
    assert _find(r, "月煞", "天马") == ["午"]
    assert _find(r, "日干煞", "日禄") == ["寅"]
    assert _find(r, "日支煞", "支冲") == ["午"]

    r = core.compute("甲子", "酉", "壬申")              # 秋、酉月（正起第 8 个月）、壬日
    assert _find(r, "季煞", "天喜") == ["辰"]
    assert _find(r, "月煞", "月建") == ["酉"]
    assert _find(r, "月煞", "天马") == ["申"]           # 酉月是八月，二八同 → 申
    assert _find(r, "月煞", "雷公") == ["巳"]           # 寅亥申巳：酉月是八月，属「四八腊」那一列 → 巳
    assert _find(r, "日干煞", "日鬼") == ["辰", "戌"]


def test_ganma_is_yima_of_jigong():
    """干马 = 日干寄宫的驿马：用日支驿马表反查，十个日干都对得上。"""
    jigong = "寅辰巳未巳未申戌亥丑"
    yima = _rule("日支煞", "驿马")
    ganma = _rule("日干煞", "干马")
    for g in range(10):
        assert list(ganma.values[g]) == list(yima.values[ZHI.index(jigong[g])]), GAN[g]
    assert _find(core.compute("甲子", "寅", "丁卯"), "日干煞", "干马") == ["巳"]    # 丁寄未，亥卯未马在巳
    assert _find(core.compute("甲子", "寅", "甲子"), "日干煞", "干马") == ["申"]    # 甲寄寅，寅午戌马在申


def test_xun():
    r = core.compute("甲子", "寅", "庚午")              # 甲子旬
    assert _find(r, "旬煞", "旬仪") == ["子"]
    assert _find(r, "旬煞", "旬奇") == ["丑"]
    assert _find(r, "旬煞", "空亡") == ["戌", "亥"]
    assert _find(r, "旬煞", "旬癸") == ["酉"]
    r = core.compute("甲子", "寅", "乙未")              # 甲午旬
    assert _find(r, "旬煞", "旬仪") == ["午"]
    assert _find(r, "旬煞", "旬奇") == ["子"]
    assert _find(r, "旬煞", "空亡") == ["辰", "巳"]
    r = core.compute("甲子", "寅", "丙辰")              # 甲寅旬
    assert _find(r, "旬煞", "旬奇") == ["亥"]
    assert _find(r, "旬煞", "空亡") == ["子", "丑"]


def test_washa_and_today():
    assert _find(core.compute("甲子", "寅", "甲子"), "月煞", "瓦煞") == ["巳"]    # 阳日
    assert _find(core.compute("甲子", "寅", "乙丑"), "月煞", "瓦煞") == ["亥"]    # 阴日取冲
    assert [t["name"] for t in core.compute("甲子", "卯", "乙卯")["today"]] == ["天转"]
    assert [t["name"] for t in core.compute("甲子", "卯", "辛卯")["today"]] == ["地转"]
    assert core.compute("甲子", "午", "乙卯")["today"] == []


def test_by_branch_is_consistent():
    for i, gz in enumerate(GZ60[:12]):
        r = core.compute(gz, ZHI[(i * 5) % 12], GZ60[(i * 7) % 60])
        n1 = sum(len(it["branches"]) for c in r["by_category"] for it in c["items"])
        n2 = sum(len(b["items"]) for b in r["by_branch"])
        assert n1 == n2
        assert [b["branch"] for b in r["by_branch"]] == list(ZHI)


def test_bad_input():
    with pytest.raises(ValueError):
        core.compute("甲丑", "寅", "甲子")              # 不是六十甲子
    with pytest.raises(ValueError):
        core.compute("甲子", "X", "甲子")


def test_api_ganzhi_and_date():
    r = json.loads(handle(json.dumps({"cmd": "shensha", "year": "甲辰", "month": "丙寅", "day": "庚午"})))
    assert r["input"] == {"year": "甲辰", "month": "寅", "day": "庚午", "season": "春"}
    # 2024-02-10：立春后，甲辰年丙寅月甲辰日
    r = json.loads(handle(json.dumps({"cmd": "shensha", "date": {"year": 2024, "month": 2, "day": 10, "hour": 12}})))
    assert r["input"]["year"] == "甲辰" and r["input"]["month"] == "寅" and r["input"]["day"] == "甲辰"
