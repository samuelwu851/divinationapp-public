"""京房八宫：代码用正推生成对照表（core.bagong）；这里用两种独立的反推方法交叉验证，64 卦必须全部一致。"""
import json

from divination.api import handle
from divination.iching import core, repository
from divination.iching.model import Hexagram, Trigram

ALL = [Hexagram(v) for v in range(64)]
VALUE = {repository.name_of(h): h.value for h in ALL}


def _bits(t: Trigram) -> list[int]:
    """三爻卦从下往上的阴阳。"""
    return [(t.value >> (2 - i)) & 1 for i in range(3)]


def by_koujue(h: Hexagram) -> tuple[Trigram, str]:
    """口诀：天同二世天变五，地同四世地变初，人同游魂人变归。
    地 = 初/四爻，人 = 二/五爻，天 = 三/上爻。
    宫：本宫、一二三世看上卦；四五世、游魂看下卦的错卦；归魂看下卦。"""
    lower, upper = core.split(h)
    di, ren, tian = (a == b for a, b in zip(_bits(lower), _bits(upper)))
    stage = {(True, True, True): "本宫", (False, True, True): "一世", (False, False, True): "二世",
             (False, False, False): "三世", (True, False, False): "四世", (True, True, False): "五世",
             (False, True, False): "游魂", (True, False, True): "归魂"}[(di, ren, tian)]
    if stage in ("本宫", "一世", "二世", "三世"):
        return upper, stage
    if stage == "归魂":
        return lower, stage
    return Trigram(lower.value ^ 0b111), stage


NUM = {Trigram.qian: 1, Trigram.dui: 2, Trigram.li: 3, Trigram.zhen: 4,
       Trigram.xun: 5, Trigram.kan: 6, Trigram.gen: 7, Trigram.kun: 8}   # 先天卦序
TRI = {n: t for t, n in NUM.items()}


def _relation(a: int, b: int) -> str:
    """两个三爻卦（先天序号）的关系：a 变哪几爻得到 b。"""
    changed = tuple(i for i, (x, y) in enumerate(zip(_bits(TRI[a]), _bits(TRI[b]))) if x != y)
    return {(): "同", (0,): "一世", (0, 1): "二世", (1,): "归魂", (0, 1, 2): "错"}[changed]


def by_xiantian(h: Hexagram) -> tuple[Trigram, str]:
    """先天卦序法（用户提供）：
    上下卦同奇偶或相加得 9 → 宫主在卦里：互为归魂 = 归魂卦（宫主下卦）；
        互错 = 三世、互为一世 = 一世、互为二世 = 二世（宫主上卦）。
    一奇一偶又不互错 → 宫主是下卦的错卦；宫主与上卦互为一世 = 四世、二世 = 五世、归魂 = 游魂。"""
    lower, upper = core.split(h)
    up, lo = NUM[upper], NUM[lower]
    if up % 2 == lo % 2 or up + lo == 9:
        r = _relation(up, lo)
        if r == "同":
            return upper, "本宫"
        if r == "归魂":
            return lower, "归魂"
        return upper, {"错": "三世", "一世": "一世", "二世": "二世"}[r]
    palace = 9 - lo
    return TRI[palace], {"一世": "四世", "二世": "五世", "归魂": "游魂"}[_relation(palace, up)]


def test_every_palace_has_eight():
    count = {}
    for h in ALL:
        p, _ = core.bagong(h)
        count[p] = count.get(p, 0) + 1
    assert count == {t: 8 for t in Trigram}


def test_two_reverse_methods_agree_with_table():
    for h in ALL:
        assert by_koujue(h) == core.bagong(h), repository.name_of(h)
        assert by_xiantian(h) == core.bagong(h), repository.name_of(h)


def test_known_examples():
    expect = {
        "乾為天": ("乾", "本宫"), "天風姤": ("乾", "一世"), "火天大有": ("乾", "归魂"),
        "地山謙": ("兌", "五世"), "水澤節": ("坎", "一世"), "雷澤歸妹": ("兌", "归魂"),
        "澤風大過": ("震", "游魂"), "水雷屯": ("坎", "二世"), "風水渙": ("離", "五世"),
    }
    for name, (palace, stage) in expect.items():
        p, s = core.bagong(Hexagram(VALUE[name]))
        assert (repository.trigram_name(p), s) == (palace, stage), name


def test_lookup_and_cangua_carry_palace():
    r = json.loads(handle(json.dumps({"cmd": "lookup", "value": VALUE["天風姤"]})))
    assert r["palace"] == {"name": "乾", "stage": "一世"}
    for k in ("cuogua_palace", "zonggua_palace", "hugua_palace"):
        assert set(r[k]) == {"name", "stage"}
    c = json.loads(handle(json.dumps({"cmd": "cangua", "org_value": VALUE["地山謙"], "chg_value": VALUE["風天小畜"]})))
    assert c["groups"][0]["guas"][0]["palace"] == {"name": "艮", "stage": "二世"}   # 山天大畜


def test_trigram_wuxing():
    # 水火既濟：上坎(水) 下離(火)
    r = json.loads(handle(json.dumps({"cmd": "lookup", "value": VALUE["水火既濟"]})))
    assert r["trigrams"] == {"lower": {"name": "離", "wuxing": "火"}, "upper": {"name": "坎", "wuxing": "水"}}
    assert set(r["cuogua_trigrams"]) == {"lower", "upper"}
    wx = {repository.trigram_name(t): repository.trigram_wuxing(t) for t in Trigram}
    assert wx == {"乾": "金", "兌": "金", "離": "火", "震": "木", "巽": "木", "坎": "水", "艮": "土", "坤": "土"}
