"""大六壬排盘命令。

{"cmd": "liuren_paipan", "date": {"year": 2024, "month": 2, "day": 10, "hour": 12, "minute": 0}}
    给公历时刻：日干支、占时按八字（子时 23:00 换日），月将按中气换（雨水亥将 … 大寒子将），
    年、月也有了，顺带返回神煞：shensha 按十二支排，shensha_list 按神煞排
    [{"category": "岁煞", "name": "驿马", "branches": ["寅"]}, ...]（左栏让用户挑着显示）。

{"cmd": "liuren_paipan", "day": "甲子", "yuejiang": "亥", "shi": "午"}
    直接给日干支、月将、占时。再给 "year": "甲辰", "month": "寅" 才有神煞。

可选参数：
    "yuejiang" / "shi": 给了 date 也可以手动指定月将、占时（活时），不给就自动
    "method":   "mzj"（涉害孟仲季法，默认：断案、指南的涉害课全合）或 "depth"（深浅法）
    "guiren":   "std"（甲戊庚牛羊，每句先昼后夜，默认）或 "alt"（甲(戊)庚牛羊：庚己丁癸昼夜对调）
    "day_night": "昼" / "夜"，不给就按占时（卯至申为昼）
    "nianming": [{"name": "本人", "birth": "庚午", "gender": "男"}, ...]
        年命：birth 是出生年干支（只写地支就只有本命）。有性别、又知道占年（给 date 或 year），
        就排行年（男一岁丙寅顺行，女一岁壬申逆行），不用算岁数。占年按立春换年。
"""
import json

from divination.liuren import core
from divination.shensha import core as shensha_core

QI_JIANG = core.QI_JIANG


def yuejiang_of(solar) -> tuple[str, str]:
    """某时刻的月将：(月将, 它所依的中气名)。"""
    qi = solar.getLunar().getPrevQi().getName()
    return QI_JIANG[qi], qi


def _from_date(d: dict) -> dict:
    from divination.bazi.service import moment
    from divination.ganzhi.repository import sizhu_of
    m = moment(d["year"], d["month"], d["day"], d.get("hour", 0), d.get("minute", 0))
    s = sizhu_of(m)
    jiang, qi = yuejiang_of(m)
    return {"year": s.year.name, "month": s.month.name, "day": s.day.name, "hour": s.hour.name,
            "shi": s.hour.name[1], "yuejiang": jiang, "qi": qi}


def paipan(req: dict) -> dict:
    if req.get("date"):
        base = _from_date(req["date"])
        for k in ("yuejiang", "shi"):              # 手动指定（活时 / 换将）
            if req.get(k):
                base[k] = req[k]
                if k == "shi":
                    base["hour"] = None
    else:
        base = {"year": req.get("year"), "month": req.get("month"), "day": req["day"], "hour": None,
                "shi": req["shi"], "yuejiang": req["yuejiang"], "qi": None}
    dn = req.get("day_night")
    if dn not in (None, "昼", "夜"):
        raise ValueError(f"day_night 只能是 昼 或 夜：{dn}")
    day = None if dn is None else dn == "昼"
    res = core.paipan(base["day"][0], base["day"][1], base["yuejiang"], base["shi"],
                      req.get("method", "mzj"), day, req.get("nianming"), base["year"],
                      req.get("guiren", "std"))
    res["input"] = {k: base[k] for k in ("year", "month", "day", "hour", "shi", "yuejiang", "qi")}
    if base["year"] and base["month"]:
        sha = shensha_core.compute(base["year"], base["month"], base["day"])
        res["shensha"] = sha["by_branch"]
        res["shensha_list"] = [{"category": c["category"], "name": it["name"], "branches": it["branches"]}
                               for c in sha["by_category"] for it in c["items"]]
    return res


def _cmd(req: dict) -> str:
    return json.dumps(paipan(req), ensure_ascii=False)


COMMANDS = {"liuren_paipan": _cmd}
