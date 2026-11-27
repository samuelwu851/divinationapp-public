"""排盘的「可搜索特征」：从快照里拆出来，存进 chart_facts 表，按排盘搜笔记时用。

每种术数两样东西：
- 拆特征的函数：快照 → [(key, value), ...]，如八字 ("year_gan", "丙")、("hour_zhi", "戌")、("gender", "male")；
- 搜索表单：前端照着画。字段有四种样子（style）：
    "menu"   下拉框：选一个值或「不限」
    "checks" 几个互斥的勾选框（如 男 / 女、有变卦 / 没变卦）：勾一个 = 只要这种，都不勾 = 不限
    "number" 直接填整数（如年份，选项太多放不进下拉框）：空着 = 不限；可带 min / max
    "pairs"  用户自己加的「两项一组」条件，最多 max 组（如六壬「子加寅」「子乘青龙」）：
             每组左边从 options 选、右边从 options2 选，中间显示 joiner；
             条件里的键写成「字段键#序号」（jia#1、jia#2…），值是左右两项拼起来（"子寅"），
             每组都要满足；对应的特征键就是字段键（jia），一张盘可以有很多个值。

一张排盘同一个特征键可以有多个值（如六壬十二个「加临」、课体同时是「涉害」「进连茹」），
条件里的一个值只要是其中之一就算满足。

搜索条件是一串「条件块」：[{"type": "bazi", "fields": {"year_gan": "丙"}}, {"type": "bazi", "fields": {...}}, ...]
笔记要有**不同的**排盘分别满足每一块（加了两个八字块，就要有两张八字各自满足），见 service.list_notes。

特征可以随时从快照重建：每个排盘的特征里带一个版本号（_v），版本变了（比如加了新特征）打开案例库时
service.backfill_chart_facts 会自动重拆，老数据也能按新特征搜。
版本号按术数分开算（见 version_for）：某种术数加了特征，只重拆这一种的排盘。

插件也能加自己的术数：在插件模块里导出
    CHART_FACTS = {"类型": {"extract": 函数, "form": 表单, "version": "1"（可省；改了特征就加一）}}
api 扫描插件时调 register_many 合并进来（同 CHART_BUILDERS 的做法）。
"""
from divination.iching import core as iching_core
from divination.iching import repository as iching_repo
from divination.iching.model import Hexagram
from divination.liuren.core import JIGONG

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


def pairs_field(key: str, label: str, left: list[dict], right: list[dict], joiner: str, most: int = 12) -> dict:
    """两项一组、用户自己加的条件（见文件开头 "pairs"）。"""
    return {"key": key, "label": label, "style": "pairs", "options": left, "options2": right,
            "joiner": joiner, "max": most}


def fact_key(query_key: str) -> str:
    """条件里的键 → 特征键：pairs 的「jia#3」→「jia」，其他不变。"""
    return query_key.split("#", 1)[0]


def number_field(key: str, label: str, lo: int | None = None, hi: int | None = None) -> dict:
    """直接填整数的字段（插件也可以用）。"""
    f = {"key": key, "label": label, "style": "number", "options": []}
    if lo is not None:
        f["min"] = lo
    if hi is not None:
        f["max"] = hi
    return f


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


# ---------- 大六壬 ----------

_JIANG = ["贵人", "螣蛇", "朱雀", "六合", "勾陈", "青龙", "天空", "白虎", "太常", "玄武", "太阴", "天后"]
# 「贼克」「遥克」是大类：选贼克 = 元首或重审，选遥克 = 蒿矢或弹射（按九宗门的顺序，放在细分的上面）
# 「三合」= 润下、炎上、曲直、从革（稼穑是辰戌丑未，不算三合）
_KE_TI_GROUP = {"元首": "贼克", "重审": "贼克", "蒿矢": "遥克", "弹射": "遥克",
                "润下": "三合", "炎上": "三合", "曲直": "三合", "从革": "三合"}
_KE_TI = ["贼克", "元首", "重审", "比用", "涉害", "遥克", "蒿矢", "弹射", "昴星", "别责", "八专", "伏吟", "返吟",
          "进连茹", "退连茹", "进间传", "退间传", "三合", "润下", "炎上", "曲直", "从革", "稼穑"]
# 四课、三传：(特征键前缀, 显示名)；每个都有「支」和「将」两项
_LIUREN_POS = [("gs", "干上"), ("gy", "干阴"), ("zs", "支上"), ("zy", "支阴"),
               ("chu", "初传"), ("zhong", "中传"), ("mo", "末传")]


def _liuren_facts(snapshot: dict) -> list[tuple[str, str]]:
    day = snapshot["day"]
    facts = [("day_gan", day[0]), ("day_zhi", day[1]), ("ke_ti", snapshot["sanchuan"]["ke_ti"])]
    # 日干乘将 = 日干寄宫那个支在天盘上所乘的天将；日支乘将 = 日支在天盘上所乘的天将
    rides = {p["zhi"]: p["jiang"] for p in snapshot["pan"]}
    facts += [("day_gan_j", rides[JIGONG[day[0]]]), ("day_zhi_j", rides[day[1]])]
    if (group := _KE_TI_GROUP.get(snapshot["sanchuan"]["ke_ti"])):
        facts.append(("ke_ti", group))
    for g in snapshot["sanchuan"].get("ke_ge", []):
        facts.append(("ke_ti", g))
        if (group := _KE_TI_GROUP.get(g)):
            facts.append(("ke_ti", group))
    places = snapshot["sike"] + snapshot["sanchuan"]["chuan"]
    for (key, _), p in zip(_LIUREN_POS, places):
        facts += [(key, p["zhi"]), (f"{key}_j", p["jiang"])]
    for p in snapshot["pan"]:
        facts += [("jia", p["zhi"] + p["di"]), ("cheng", p["zhi"] + p["jiang"])]
    return facts


_ZHI_OPTIONS = _options(list(ZHI))
_JIANG_OPTIONS = _options(_JIANG)

_LIUREN_FORM = {
    "title": "大六壬",
    "columns": 2,          # 每行：某位置的「支」和「将」
    "fields": [_menu("ke_ti", "课体", _options(_KE_TI)),
               dict(_menu("day_gan", "日干", _options(list(GAN))), group="日"),
               dict(_menu("day_gan_j", "日干乘将", _JIANG_OPTIONS), group="日"),
               dict(_menu("day_zhi", "日支", _ZHI_OPTIONS), group="日"),
               dict(_menu("day_zhi_j", "日支乘将", _JIANG_OPTIONS), group="日")]
            + [dict(_menu(f"{k}{suffix}", f"{n}{what}", opts), group="四课" if i < 4 else "三传")
               for i, (k, n) in enumerate(_LIUREN_POS)
               for suffix, what, opts in (("", "", _ZHI_OPTIONS), ("_j", "将", _JIANG_OPTIONS))]
            + [pairs_field("jia", "天地盘加临", _ZHI_OPTIONS, _ZHI_OPTIONS, "加"),
               pairs_field("cheng", "乘神", _ZHI_OPTIONS, _JIANG_OPTIONS, "乘")],
}


# 排盘类型 → {"extract": 拆特征函数, "form": 搜索表单}；顺序就是「＋ 选择术数」菜单里的顺序
REGISTRY: dict[str, dict] = {
    "bazi": {"extract": _bazi_facts, "form": _BAZI_FORM},
    "iching": {"extract": _iching_facts, "form": _ICHING_FORM},
    "meihua": {"extract": _gua_facts, "form": _MEIHUA_FORM},
    "daliuren": {"extract": _liuren_facts, "form": _LIUREN_FORM, "version": "3"},   # 1：加了日干 / 日支乘将；2：加了贼克、遥克；3：加了三合
}


def register_many(items: dict) -> None:
    """插件加自己的可搜索术数。不许覆盖已有的。"""
    for chart_type, spec in items.items():
        if chart_type in REGISTRY:
            raise ValueError(f"排盘搜索重复注册：{chart_type}")
        REGISTRY[chart_type] = spec


def version_for(chart_type: str) -> str:
    """某种术数的特征版本：总版本 FACTS_VERSION，加上这种术数自己的 version（有的话）。
    内置的术数不写 version，版本就是 FACTS_VERSION；插件写了，就是「2+1」这种，改了只重拆它自己的。"""
    v = REGISTRY.get(chart_type, {}).get("version")
    return f"{FACTS_VERSION}+{v}" if v else FACTS_VERSION


def extract(chart_type: str, snapshot: dict) -> list[tuple[str, str]]:
    """拆特征（最后带上版本号）；这种排盘不支持搜索、或快照格式不对，返回空。"""
    spec = REGISTRY.get(chart_type)
    if spec is None:
        return []
    try:
        return spec["extract"](snapshot) + [(VERSION_KEY, version_for(chart_type))]
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
        allowed = {f["key"]: f for f in spec["form"]["fields"]}
        fields = b.get("fields") or {}
        kept = {}
        for k, v in fields.items():
            if v in (None, ""):
                continue
            if "#" in k:                                   # pairs：jia#3 → 检查序号和左右两项
                f = allowed.get(fact_key(k))
                if f is None or f.get("style") != "pairs" or not _pair_ok(f, k, str(v)):
                    continue
                kept[k] = str(v)
                continue
            if k not in allowed or allowed[k].get("style") == "pairs":
                continue
            if allowed[k].get("style") == "number":      # 数字统一成整数写法（"01990" → "1990"），填错的忽略
                try:
                    v = int(str(v).strip())
                except ValueError:
                    continue
            kept[k] = str(v)
        out.append({"type": b["type"], "fields": kept})
    return out


def _pair_ok(field: dict, key: str, value: str) -> bool:
    """pairs 条件：序号在 1..max，值 = 左边某个选项 + 右边某个选项。"""
    try:
        n = int(key.split("#", 1)[1])
    except ValueError:
        return False
    if not 1 <= n <= field.get("max", 12):
        return False
    lefts = [o["value"] for o in field["options"]]
    rights = {o["value"] for o in field["options2"]}
    return any(value.startswith(l) and value[len(l):] in rights for l in lefts)


def match_distinct(blocks: list[dict], charts: list[dict]) -> bool:
    """每个条件块配一张**不同的**排盘（类型相同、特征都对得上）。charts: [{id, type, facts: {key: {值…}}}]。
    条件块很少（几个），直接回溯就够了。"""
    def ok(block, chart):
        return chart["type"] == block["type"] and all(v in chart["facts"].get(fact_key(k), ())
                                                      for k, v in block["fields"].items())

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
