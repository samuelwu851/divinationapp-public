"""神煞计算：给年、月、日的干支，算出每个神煞落在哪个地支，以及每个地支上有哪些神煞。

输入：
    year  年干支，如 "甲辰"（岁煞用年干、年支）
    month 月建，如 "丙寅" 或只给 "寅"（只用地支；立春起寅月）
    day   日干支，如 "庚午"（旬煞、日干煞、日支煞、当日神煞）
"""
from divination.shensha.data import (
    ZHI, GAN, RULES, CATEGORIES, Rule,
    YEAR_ZHI, YEAR_GAN, MONTH, SEASON, DAY_GAN, DAY_ZHI,
    YUE, XUN, DANGRI,
)

_SEASONS = "春夏秋冬"


def _zhi(z: str) -> int:
    i = ZHI.find(z)
    if i < 0:
        raise ValueError(f"不认识的地支：{z!r}")
    return i


def _gan(g: str) -> int:
    i = GAN.find(g)
    if i < 0:
        raise ValueError(f"不认识的天干：{g!r}")
    return i


def _ganzhi(gz: str, what: str) -> tuple[int, int]:
    if not isinstance(gz, str) or len(gz) != 2:
        raise ValueError(f"{what}要两个字的干支，收到 {gz!r}")
    g, z = _gan(gz[0]), _zhi(gz[1])
    if g % 2 != z % 2:
        raise ValueError(f"{what}「{gz}」不是六十甲子里的干支")
    return g, z


def indexes(year: str, month: str, day: str) -> dict:
    """各种「按什么起」的序号。"""
    yg, yz = _ganzhi(year, "年")
    m = (_zhi(month[-1]) - 2) % 12                   # 寅月 0、卯月 1 … 丑月 11
    dg, dz = _ganzhi(day, "日")
    return {YEAR_ZHI: yz, YEAR_GAN: yg, MONTH: m, SEASON: m // 3, DAY_GAN: dg, DAY_ZHI: dz}


def place(rule: Rule, idx: dict) -> list[str]:
    """一条规则在这个盘里落在哪些地支。"""
    i = idx[rule.key]
    if rule.start is not None:
        return [ZHI[(_zhi(rule.start) + rule.step * i) % 12]]
    return list(rule.values[i])


# ---------- 要另外算的 ----------

def _xun(dg: int, dz: int) -> list[dict]:
    """旬煞：旬首（甲）所在地支往后数。甲子旬：甲子 乙丑 丙寅 丁卯 … 癸酉，空亡戌亥。"""
    head = (dz - dg) % 12                            # 旬首甲所临的地支
    at = lambda k: ZHI[(head + k) % 12]
    qi = {0: "丑", 10: "丑", 8: "子", 6: "子", 4: "亥", 2: "亥"}[head]   # 子戌旬丑、申午旬子、辰寅旬亥
    return [
        {"name": "旬仪", "category": XUN, "branches": [at(0)], "alias": "六仪、旬甲"},
        {"name": "旬奇", "category": XUN, "branches": [qi], "alias": ""},
        {"name": "旬乙", "category": XUN, "branches": [at(1)], "alias": "盗神"},
        {"name": "旬丁", "category": XUN, "branches": [at(3)], "alias": "丁神"},
        {"name": "旬庚", "category": XUN, "branches": [at(6)], "alias": "响动"},
        {"name": "旬辛", "category": XUN, "branches": [at(7)], "alias": "五亡"},
        {"name": "旬癸", "category": XUN, "branches": [at(9)], "alias": "闭口"},
        {"name": "空亡", "category": XUN, "branches": [at(10), at(11)], "alias": ""},
    ]


# 瓦煞：阳日按月取，阴日取其冲位
_WA = "巳子丑寅卯辰亥午未申酉戌"


def _washa(m: int, dg: int) -> dict:
    z = _zhi(_WA[m])
    if dg % 2 == 1:
        z = (z + 6) % 12
    return {"name": "瓦煞", "category": YUE, "branches": [ZHI[z]], "alias": ""}


# 当日神煞：这一天是不是（不落在地支上）
_TIANZHUAN = ["乙卯", "丙午", "辛酉", "壬子"]       # 春夏秋冬
_DIZHUAN = ["辛卯", "戊午", "癸酉", "丙子"]


def _dangri(season: int, day: str) -> list[dict]:
    out = []
    if day == _TIANZHUAN[season]:
        out.append({"name": "天转", "category": DANGRI, "branches": [], "alias": ""})
    if day == _DIZHUAN[season]:
        out.append({"name": "地转", "category": DANGRI, "branches": [], "alias": ""})
    return out


# ---------- 汇总 ----------

def compute(year: str, month: str, day: str) -> dict:
    """返回：
    {
      "input": {year, month, day, season},
      "by_category": [{"category": "岁煞", "items": [{"name", "branches": [地支...], "alias"}]}, ...],
      "by_branch":   [{"branch": "子", "items": [{"name", "category"}]}, ...],   # 子到亥 12 格
      "today":       [{"name": "天转", ...}]                                    # 当日神煞（不落在地支上）
    }
    """
    idx = indexes(year, month, day)
    items = [{"name": r.name, "category": r.category, "branches": place(r, idx), "alias": r.alias}
             for r in RULES]
    items.append(_washa(idx[MONTH], idx[DAY_GAN]))
    items += _xun(idx[DAY_GAN], idx[DAY_ZHI])
    today = _dangri(idx[SEASON], day)

    by_category = []
    for cat in CATEGORIES:
        if cat == DANGRI:
            continue
        rows = [{k: it[k] for k in ("name", "branches", "alias")} for it in items if it["category"] == cat]
        by_category.append({"category": cat, "items": rows})

    by_branch = [{"branch": z, "items": []} for z in ZHI]
    for it in items:
        for z in it["branches"]:
            by_branch[_zhi(z)]["items"].append({"name": it["name"], "category": it["category"]})

    return {
        "input": {"year": year, "month": ZHI[(idx[MONTH] + 2) % 12], "day": day,
                  "season": _SEASONS[idx[SEASON]]},
        "by_category": by_category,
        "by_branch": by_branch,
        "today": [{"name": t["name"], "alias": t["alias"]} for t in today],
    }
