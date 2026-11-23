"""排盘的「可搜索特征」：从快照里拆出来，存进 chart_facts 表，按排盘搜笔记时用。

每种术数两样东西：
- 拆特征的函数：快照 → [(key, value), ...]，如八字 ("year_gan", "丙")、("hour_zhi", "戌")、("gender", "male")；
- 搜索表单：前端照着画。字段有两种样子（style）：
    "menu"  下拉框：选一个值或「不限」
    "checks" 几个互斥的勾选框（如 男 / 女、有变卦 / 没变卦）：勾一个 = 只要这种，都不勾 = 不限

搜索条件是一串「条件块」：[{"type": "bazi", "fields": {"year_gan": "丙"}}, {"type": "bazi", "fields": {...}}, ...]
笔记要有**不同的**排盘分别满足每一块（加了两个八字块，就要有两张八字各自满足），见 service.list_notes。

特征可以随时从快照重建：每个排盘的特征里带一个版本号（_v），版本变了（比如加了新特征）打开案例库时
service.backfill_chart_facts 会自动重拆，老数据也能按新特征搜。

插件也能加自己的术数：在插件模块里导出
    CHART_FACTS = {"类型": {"extract": 函数, "form": 表单}}
api 扫描插件时调 register_many 合并进来（同 CHART_BUILDERS 的做法）。
"""
from divination.iching import core as iching_core
from divination.iching import repository as iching_repo
from divination.iching.model import Hexagram

# 特征的版本：拆法或字段有变化就加一，打开案例库时会给所有排盘重拆
FACTS_VERSION = "2"
VERSION_KEY = "_v"

GAN = "甲乙丙丁戊己庚辛壬癸"
ZHI = "子丑寅卯辰巳午未申酉戌亥"

# 八卦：存的值用库里的名字（繁体：兌、離），显示用简体
_TRIGRAM_VALUES = ["乾", "兌", "離", "震", "巽", "坎", "艮", "坤"]
_TRIGRAM_LABELS = ["乾", "兑", "离", "震", "巽", "坎", "艮", "坤"]

_PILLARS = [("year", "年"), ("month", "月"), ("day", "日"), ("hour", "时")]


def _options(values, labels=None) -> list[dict]:
    labels = labels or values
    return [{"value": v, "label": l} for v, l in zip(values, labels)]


def _menu(key: str, label: str, options: list[dict]) -> dict:
    return {"key": key, "label": label, "style": "menu", "options": options}


def _checks(key: str, label: str, options: list[dict]) -> dict:
    return {"key": key, "label": label, "style": "checks", "options": options}


# ---------- 八字：性别 + 八个字 ----------

def _bazi_facts(snapshot: dict) -> list[tuple[str, str]]:
    chart = snapshot["chart"]
    pillars = chart["pillars"]
    facts = [("gender", "male" if chart.get("gender") == "乾造" else "female")]
    for key, _ in _PILLARS:
        gz = pillars[key]["ganzhi"]
        facts += [(f"{key}_gan", gz[0]), (f"{key}_zhi", gz[1])]
    return facts


_BAZI_FORM = {
    "title": "八字",
    "columns": 4,          # 一行四柱：上面一行天干、下面一行地支
    "fields": [_checks("gender", "性别", _options(["male", "female"], ["男", "女"]))]
            + [_menu(f"{k}_gan", f"{n}干", _options(GAN)) for k, n in _PILLARS]
            + [_menu(f"{k}_zhi", f"{n}支", _options(ZHI)) for k, n in _PILLARS],
}


# ---------- 用卦的（梅花易数、易经速查）：本卦、变卦的上卦和下卦 ----------

def _trigrams(value: int) -> tuple[str, str]:
    """卦码 → (上卦名, 下卦名)。不靠快照里的 trigrams（老快照没有），直接从卦码算。"""
    lower, upper = iching_core.split(Hexagram(value))
    return iching_repo.trigram_name(upper), iching_repo.trigram_name(lower)


def _gua_facts(snapshot: dict) -> list[tuple[str, str]]:
    facts = []
    for which, key in (("original", "ben"), ("changed", "bian")):
        upper, lower = _trigrams(snapshot[which]["value"])
        facts += [(f"{key}_upper", upper), (f"{key}_lower", lower)]
    return facts


def _iching_facts(snapshot: dict) -> list[tuple[str, str]]:
    changed = snapshot["original"]["value"] != snapshot["changed"]["value"]
    return [("has_change", "yes" if changed else "no")] + _gua_facts(snapshot)


_TRIGRAM_OPTIONS = _options(_TRIGRAM_VALUES, _TRIGRAM_LABELS)

# 左边本卦、右边变卦；上面一行上卦、下面一行下卦
_GUA_FIELDS = [
    _menu("ben_upper", "本卦上卦", _TRIGRAM_OPTIONS),
    _menu("bian_upper", "变卦上卦", _TRIGRAM_OPTIONS),
    _menu("ben_lower", "本卦下卦", _TRIGRAM_OPTIONS),
    _menu("bian_lower", "变卦下卦", _TRIGRAM_OPTIONS),
]

_MEIHUA_FORM = {"title": "梅花易数", "columns": 2, "fields": _GUA_FIELDS}

_ICHING_FORM = {
    "title": "易经速查",
    "columns": 2,
    "fields": [_checks("has_change", "变卦", _options(["yes", "no"], ["有变卦", "没变卦"]))] + _GUA_FIELDS,
}


# 排盘类型 → {"extract": 拆特征函数, "form": 搜索表单}；顺序就是「＋ 选择术数」菜单里的顺序
REGISTRY: dict[str, dict] = {
    "bazi": {"extract": _bazi_facts, "form": _BAZI_FORM},
    "iching": {"extract": _iching_facts, "form": _ICHING_FORM},
    "meihua": {"extract": _gua_facts, "form": _MEIHUA_FORM},
}


def register_many(items: dict) -> None:
    """插件加自己的可搜索术数。不许覆盖已有的。"""
    for chart_type, spec in items.items():
        if chart_type in REGISTRY:
            raise ValueError(f"排盘搜索重复注册：{chart_type}")
        REGISTRY[chart_type] = spec


def extract(chart_type: str, snapshot: dict) -> list[tuple[str, str]]:
    """拆特征（最后带上版本号）；这种排盘不支持搜索、或快照格式不对，返回空。"""
    spec = REGISTRY.get(chart_type)
    if spec is None:
        return []
    try:
        return spec["extract"](snapshot) + [(VERSION_KEY, FACTS_VERSION)]
    except (KeyError, TypeError, ValueError, IndexError, AttributeError):
        return []                  # 快照格式不认识：不让它影响存排盘，只是搜不到


def forms() -> list[dict]:
    """给前端画搜索面板：[{type, title, columns, fields:[{key, label, style, options:[{value, label}]}]}]。"""
    return [{"type": t, **spec["form"]} for t, spec in REGISTRY.items()]


def clean_query(blocks) -> list[dict]:
    """前端发来的条件块 → 去掉不认识的类型和字段、空值。条件块本身保留（一个空的八字块 = 要有一张八字）。"""
    out = []
    for b in blocks or []:
        if not isinstance(b, dict):
            continue
        spec = REGISTRY.get(b.get("type"))
        if spec is None:
            continue
        allowed = {f["key"] for f in spec["form"]["fields"]}
        fields = b.get("fields") or {}
        kept = {k: str(v) for k, v in fields.items() if k in allowed and v not in (None, "")}
        out.append({"type": b["type"], "fields": kept})
    return out


def match_distinct(blocks: list[dict], charts: list[dict]) -> bool:
    """每个条件块配一张**不同的**排盘（类型相同、特征都对得上）。charts: [{id, type, facts: {key: value}}]。
    条件块很少（几个），直接回溯就够了。"""
    def ok(block, chart):
        return chart["type"] == block["type"] and all(chart["facts"].get(k) == v for k, v in block["fields"].items())

    used: set[int] = set()

    def place(i: int) -> bool:
        if i == len(blocks):
            return True
        for c in charts:
            if c["id"] not in used and ok(blocks[i], c):
                used.add(c["id"])
                if place(i + 1):
                    return True
                used.discard(c["id"])
        return False

    return place(0)
