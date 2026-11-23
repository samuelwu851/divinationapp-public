"""笔记里插入的排盘：由后端按参数排盘，生成快照（snapshot）。

前端只传「什么术数 + 参数」，排盘全在后端做，保证：
- 每个平台的前端都不用重写排盘逻辑；
- 存下来的快照就是当时的结果，以后算法改了，老笔记里的盘也不会变。

每种术数一个 builder：参数 dict → (标题, 快照 dict)。

插件也可以加自己的排盘类型：在插件模块里导出 CHART_BUILDERS = {"类型": builder}，
api 扫描插件时会调 register_builders 合并进来（同 COMMANDS 的做法），这里不用改。

通用卡片：前端只内置了 bazi / iching / meihua 三种卡片的画法。其他类型（如插件）
在快照里带一段 "card"，前端照着画，不用为每种新类型改编辑器：
    "card": {
        "title": "卡片抬头（术数名）",
        "subtitle": "副标题（如日期，可省）",
        "guas": [{"label": "卦下的小字", "name": "卦名", "lines": [初…上], "trigrams": {...}（可省）}, ...]
    }
"""
from datetime import datetime

from divination.bazi import service as bazi_service
from divination.ganzhi import service as ganzhi_service
from divination.iching import service as iching_service
from divination.meihua import service as meihua_service

# 排盘算法版本：算法有不兼容修改时加一，便于以后知道某个快照是哪一版算的
ALGO_VERSION = "1"


def _moment(p: dict) -> datetime:
    return datetime(p["year"], p["month"], p["day"], p.get("hour", 0), p.get("minute", 0))


def _yilin_text(org: int, chg: int) -> str | None:
    if org == chg:
        return None
    return iching_service.yilin(org, chg)["text"]


def _bazi(p: dict) -> tuple[str, dict]:
    name = (p.get("name") or "").strip()
    birth = bazi_service.moment(p["year"], p["month"], p["day"], p.get("hour", 0), p.get("minute", 0))
    chart = bazi_service.bazi_chart(birth, bool(p["is_male"]))   # 公元 1–2200 年，1582 年以前按儒略历
    return name, {"name": name, "chart": chart}


def _iching(p: dict) -> tuple[str, dict]:
    org = p["org_value"]
    chg = p.get("chg_value", org)
    return "", {
        "original": iching_service.checkandpack(org),
        "changed": iching_service.checkandpack(chg),
        "yilin": _yilin_text(org, chg),
        "cangua": iching_service.cangua(org, chg)["groups"],
    }


def _meihua(p: dict) -> tuple[str, dict]:
    moment = _moment(p)
    q = meihua_service.qigua(moment)
    org, chg = q["ben_gua"]["value"], q["bian_gua"]["value"]
    return "", {
        "qigua": q,
        "bazi": ganzhi_service.bazi(moment),
        "original": iching_service.checkandpack(org),
        "changed": iching_service.checkandpack(chg),
        "yilin": _yilin_text(org, chg),
        "cangua": iching_service.cangua(org, chg)["groups"],
    }


BUILDERS = {
    "bazi": _bazi,
    "iching": _iching,
    "meihua": _meihua,
}


def register_builders(builders: dict) -> None:
    """插件注册自己的排盘类型。不许覆盖已有的类型（避免插件悄悄改掉内置排盘）。"""
    for chart_type, builder in builders.items():
        if chart_type in BUILDERS:
            raise ValueError(f"排盘类型重复注册：{chart_type}")
        BUILDERS[chart_type] = builder


def build(chart_type: str, params: dict) -> tuple[str, dict]:
    """按术数类型排盘，返回 (默认标题, 快照)。"""
    builder = BUILDERS.get(chart_type)
    if builder is None:
        raise ValueError(f"不支持的排盘类型：{chart_type}")
    return builder(params)
